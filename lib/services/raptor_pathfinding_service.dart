import 'dart:math' as math;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/profile_store.dart';

class NavigationStep {
  final String instruction;

  const NavigationStep({required this.instruction});
}

class Leg {
  final String fromStopId;
  final String toStopId;
  final String fromStopName;
  final String toStopName;
  final String? routeId;
  final String? tripId;
  final String? routeLongName;
  final VehicleType vehicleType;
  List<Position>? coordinates;
  double? distance;
  double? durationSeconds;
  List<String?>? traffic;
  List<NavigationStep>? steps;

  Leg({
    required this.fromStopId,
    required this.toStopId,
    required this.fromStopName,
    required this.toStopName,
    required this.vehicleType,
    this.routeId,
    this.tripId,
    this.routeLongName,
    this.coordinates,
    this.distance,
    this.durationSeconds,
    this.traffic,
    this.steps,
  });

  bool get isWalking => vehicleType == VehicleType.walk;
}

class Journey {
  final List<Leg> legs;
  final double routingCost;
  Journey(this.legs, {this.routingCost = 0});

  late final double walkingDistance = legs
      .where((leg) => leg.isWalking)
      .fold(0.0, (sum, leg) => sum + (leg.distance ?? 0));
  int get boardings => legs.where((leg) => !leg.isWalking).length;
  late final double estimatedDurationSeconds = legs.fold(
    boardings * 120.0,
    (sum, leg) => sum + (leg.distance ?? 0) / _speed(leg.vehicleType),
  );
  late final String signature = legs
      .map(
        (leg) =>
            '${leg.vehicleType.name}:${leg.routeId}:${leg.fromStopId}:${leg.toStopId}',
      )
      .join('|');

  static double _speed(VehicleType type) => switch (type) {
    VehicleType.walk => 1.4,
    VehicleType.train => 10,
    VehicleType.bus || VehicleType.uvExpress => 7,
    VehicleType.jeep => 6,
    VehicleType.tricycle => 5,
    VehicleType.unknown => 1,
  };
}

class RaptorRoutingOptions {
  final RoutePriority priority;
  final int maxWalkingDistance;
  final Set<TransportMode> enabledModes;

  RaptorRoutingOptions({
    required this.priority,
    required this.maxWalkingDistance,
    required Set<TransportMode> enabledModes,
  }) : enabledModes = Set.unmodifiable(enabledModes);

  factory RaptorRoutingOptions.fromProfile(ProfileData profile) =>
      RaptorRoutingOptions(
        priority: profile.routePriority,
        maxWalkingDistance: profile.maxWalkingDistance,
        enabledModes: profile.enabledModes,
      );
}

class RaptorRoute {
  final String routeId;
  final String sourceRouteId;
  final String tripId;
  final String routeLongName;
  final VehicleType vehicleType;
  final List<StopsAndStopTimesModel> stops;
  final List<double> cumulativeDistances;

  RaptorRoute({
    required this.routeId,
    required this.sourceRouteId,
    required this.tripId,
    required this.routeLongName,
    required this.vehicleType,
    required this.stops,
    required this.cumulativeDistances,
  });
}

class Transfer {
  final String toStopId;
  final double distance;
  Transfer({required this.toStopId, required this.distance});
}

class _ResultMeta {
  final String stopId;
  final int round;
  final double totalCost;
  final double finalDist;

  _ResultMeta({
    required this.stopId,
    required this.round,
    required this.totalCost,
    required this.finalDist,
  });
}

class _Parent {
  final String fromStopId;
  final int fromRound;
  final String? routeId;
  final double? distance;

  _Parent({
    required this.fromStopId,
    required this.fromRound,
    this.routeId,
    this.distance,
  });
}

class RaptorPathfindingService {
  static final RaptorPathfindingService instance = RaptorPathfindingService._();
  RaptorPathfindingService._();

  static const int infinity = 1000000;

  // ── Algorithm tuning constants ───────────────────────────────────────────
  static const double _transitCostWeight = 0.05; // cost per meter on transit
  static const double _transferPenalty = 500.0; // discourages extra transfers
  static const double _walkCircuityFactor = 1.4; // straight-line → city-block
  static const double _trainCostDivisor =
      1.7; // trains cheaper relative to cost
  static const int _maxRounds = 6;
  static const int _maxResults = 6;
  static const int _maxCandidatesPerRoute = 5;
  // ─────────────────────────────────────────────────────────────────────────

  // Haversine formula to compute distance in meters between two points
  double computeDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // in meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degree) {
    return degree * math.pi / 180;
  }

  List<Journey> findJourneys({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    required RaptorRoutingOptions options,
  }) {
    final walkingLimit = options.maxWalkingDistance.toDouble();
    final directWalkDist =
        computeDistance(originLat, originLng, destLat, destLng) *
        _walkCircuityFactor;
    double walkingCost(double distance) => switch (options.priority) {
      RoutePriority.fastest => distance / 1.4,
      RoutePriority.fewerTransfers => distance,
      RoutePriority.lessWalking => distance * 4,
    };
    double transitCost(VehicleType type, double distance) =>
        options.priority == RoutePriority.fastest
        ? distance / Journey._speed(type)
        : distance *
              (type == VehicleType.train
                  ? _transitCostWeight / _trainCostDivisor
                  : _transitCostWeight);
    final transferPenalty = switch (options.priority) {
      RoutePriority.fastest => 120.0,
      RoutePriority.fewerTransfers => _transferPenalty * 8,
      RoutePriority.lessWalking => _transferPenalty,
    };
    Journey directJourney() => Journey([
      Leg(
        fromStopId: '__ORIGIN__',
        toStopId: '__DESTINATION__',
        distance: directWalkDist,
        fromStopName: 'origin',
        toStopName: 'destination',
        vehicleType: VehicleType.walk,
      ),
    ], routingCost: walkingCost(directWalkDist));
    if (!GtfsNetworkService.instance.isLoaded) {
      return directWalkDist <= walkingLimit ? [directJourney()] : [];
    }

    // 1. Gather all unique stops and RaptorRoutes
    final Map<String, StopsAndStopTimesModel> allStops = {};
    final List<RaptorRoute> allRoutes = [];
    final Map<String, RaptorRoute> routesById = {};
    final Set<String> seenSequences = {};

    for (final route in GtfsNetworkService.instance.routesMap.values) {
      final mode = _transportMode(route.vehicleType);
      if (mode == null || !options.enabledModes.contains(mode)) continue;
      for (final trip in route.trips) {
        final sortedStops = List<StopsAndStopTimesModel>.from(trip.stopTimes)
          ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));

        if (sortedStops.isEmpty) continue;

        // Populate stops
        for (final stop in sortedStops) {
          allStops[stop.stopId] = stop;
        }

        // Group into unique routes by stop sequence signature
        final sequenceSignature =
            '${route.routeId}:${sortedStops.map((s) => s.stopId).join('->')}';
        if (!seenSequences.contains(sequenceSignature)) {
          seenSequences.add(sequenceSignature);

          // Precompute cumulative distances along the route
          final List<double> cumulativeDistances = [0.0];
          double accum = 0.0;
          for (int idx = 0; idx < sortedStops.length - 1; idx++) {
            accum += computeDistance(
              sortedStops[idx].stopLat,
              sortedStops[idx].stopLon,
              sortedStops[idx + 1].stopLat,
              sortedStops[idx + 1].stopLon,
            );
            cumulativeDistances.add(accum);
          }

          final raptorRouteId = '${route.routeId}_p${seenSequences.length}';
          final rr = RaptorRoute(
            routeId: raptorRouteId,
            sourceRouteId: route.routeId,
            tripId: trip.tripId,
            routeLongName: route.routeLongName,
            vehicleType: route.vehicleType,
            stops: sortedStops,
            cumulativeDistances: cumulativeDistances,
          );
          allRoutes.add(rr);
          routesById[raptorRouteId] = rr;
        }
      }
    }

    if (allStops.isEmpty || allRoutes.isEmpty) {
      return directWalkDist <= walkingLimit ? [directJourney()] : [];
    }

    // Build spatial grid for stops to speed up local searches
    final Map<String, List<StopsAndStopTimesModel>> stopGrid = {};
    String getGridKey(double lat, double lon) {
      final int latKey = (lat * 100).floor();
      final int lonKey = (lon * 100).floor();
      return '$latKey,$lonKey';
    }

    for (final stop in allStops.values) {
      final key = getGridKey(stop.stopLat, stop.stopLon);
      stopGrid.putIfAbsent(key, () => []).add(stop);
    }

    List<StopsAndStopTimesModel> getNearbyStops(
      double lat,
      double lon,
      double maxDist,
    ) {
      final List<StopsAndStopTimesModel> nearby = [];
      final int latKey = (lat * 100).floor();
      final int lonKey = (lon * 100).floor();
      final cells = math.max(1, (maxDist / 900).ceil());

      for (int dl = -cells; dl <= cells; dl++) {
        for (int dg = -cells; dg <= cells; dg++) {
          final cellKey = '${latKey + dl},${lonKey + dg}';
          final cellStops = stopGrid[cellKey];
          if (cellStops != null) {
            for (final s in cellStops) {
              final d = computeDistance(lat, lon, s.stopLat, s.stopLon);
              if (d <= maxDist) {
                nearby.add(s);
              }
            }
          }
        }
      }
      return nearby;
    }

    // Build routing indices
    final Map<String, List<String>> routesByStop = {};
    final Map<String, List<String>> stopsByRoute = {};
    final Map<String, List<double>> routeDistances = {};

    for (final rr in allRoutes) {
      stopsByRoute[rr.routeId] = rr.stops.map((s) => s.stopId).toList();
      routeDistances[rr.routeId] = rr.cumulativeDistances;
      for (final stop in rr.stops) {
        routesByStop.putIfAbsent(stop.stopId, () => []).add(rr.routeId);
      }
    }

    // Precompute transfers (walks between stops)
    final Map<String, List<Transfer>> transfers = {};
    for (final stop in allStops.values) {
      final nearby = getNearbyStops(
        stop.stopLat,
        stop.stopLon,
        walkingLimit / _walkCircuityFactor,
      );
      final List<Transfer> list = [];
      for (final other in nearby) {
        if (other.stopId == stop.stopId) continue;
        final d = computeDistance(
          stop.stopLat,
          stop.stopLon,
          other.stopLat,
          other.stopLon,
        );
        if (d * _walkCircuityFactor <= walkingLimit) {
          list.add(Transfer(toStopId: other.stopId, distance: d));
        }
      }
      transfers[stop.stopId] = list;
    }

    // --- ALGORITHM START ---

    // Track best overall cost reached at each stop
    final bestCostOverall = <String, double>{
      for (var s in allStops.keys) s: infinity.toDouble(),
    };
    // Track best cost reached in EACH round
    final roundCosts = List.generate(
      7,
      (_) => {for (var s in allStops.keys) s: infinity.toDouble()},
    );

    final parents = <(int, String), _Parent>{};

    // --- Initial Walking Phase (Origin -> Stops) ---
    final originNearby =
        getNearbyStops(
              originLat,
              originLng,
              walkingLimit / _walkCircuityFactor,
            )
            .map(
              (s) => Transfer(
                toStopId: s.stopId,
                distance: computeDistance(
                  originLat,
                  originLng,
                  s.stopLat,
                  s.stopLon,
                ),
              ),
            )
            .where(
              (walk) => walk.distance * _walkCircuityFactor <= walkingLimit,
            )
            .toList();

    var markedStops = <String>{};
    for (var transfer in originNearby) {
      final realWalkingDist = transfer.distance * _walkCircuityFactor;
      final cost = walkingCost(realWalkingDist);
      bestCostOverall[transfer.toStopId] = cost;
      roundCosts[0][transfer.toStopId] = cost;
      parents[(0, transfer.toStopId)] = _Parent(
        fromStopId: "__ORIGIN__",
        fromRound: 0,
        routeId: null,
        distance: realWalkingDist,
      );
      markedStops.add(transfer.toStopId);
    }

    var currentRound = 0;

    // Track best candidates from each round for multi-journey options
    final candidates = <String, _ResultMeta>{};

    // --- Direct Walk Option ---
    if (directWalkDist <= walkingLimit) {
      candidates['__DIRECT__'] = _ResultMeta(
        stopId: '__DIRECT__',
        round: -1,
        totalCost: walkingCost(directWalkDist),
        finalDist: directWalkDist,
      );
    }

    while (markedStops.isNotEmpty && currentRound < _maxRounds) {
      currentRound++;

      final routesToProcess = <String, String>{};
      for (var stopId in markedStops) {
        final routes = routesByStop[stopId] ?? [];
        for (var rid in routes) {
          final stops = stopsByRoute[rid]!;
          final stopIdx = stops.indexOf(stopId);
          if (routesToProcess.containsKey(rid)) {
            final eStopId = routesToProcess[rid]!;
            if (stopIdx < stops.indexOf(eStopId)) {
              routesToProcess[rid] = stopId;
            }
          } else {
            routesToProcess[rid] = stopId;
          }
        }
      }

      markedStops.clear();

      for (var entry in routesToProcess.entries) {
        final routeId = entry.key;
        final startStopId = entry.value;
        final stops = stopsByRoute[routeId]!;
        final dists = routeDistances[routeId]!;
        final startIdx = stops.indexOf(startStopId);

        bool boarding = false;
        String? boardingStopId;
        double costAtBoarding = infinity.toDouble();
        double distAtBoarding = 0.0;

        for (int i = startIdx; i < stops.length; i++) {
          final stopId = stops[i];
          final currentDistOnRoute = dists[i];

          // 1. Can we board here? (Improve boarding point)
          final prevRoundCost = roundCosts[currentRound - 1][stopId]!;
          if (prevRoundCost < infinity) {
            // First boarding from origin has no penalty; subsequent are transfers
            final penalty = currentRound > 1 ? transferPenalty : 0.0;
            final potentialBoardingCost = prevRoundCost + penalty;
            if (!boarding || potentialBoardingCost < costAtBoarding) {
              boarding = true;
              boardingStopId = stopId;
              costAtBoarding = potentialBoardingCost;
              distAtBoarding = currentDistOnRoute;
            }
          }

          // 2. Traversal
          if (boarding && stopId != boardingStopId) {
            final transitDist = currentDistOnRoute - distAtBoarding;

            final rr = routesById[routeId];
            final arrivalCost =
                costAtBoarding + transitCost(rr!.vehicleType, transitDist);

            if (arrivalCost < bestCostOverall[stopId]!) {
              bestCostOverall[stopId] = arrivalCost;
              roundCosts[currentRound][stopId] = arrivalCost;
              parents[(currentRound, stopId)] = _Parent(
                fromStopId: boardingStopId!,
                fromRound: currentRound - 1,
                routeId: routeId,
              );
              markedStops.add(stopId);
            }
          }
        }
      }

      // --- Walking Transfers Phase (Stop -> Stop) ---
      final newlyMarkedByWalk = <String>{};
      for (var stopId in markedStops) {
        final stopTransfers = transfers[stopId] ?? [];
        for (var transfer in stopTransfers) {
          final realTransferDist = transfer.distance * _walkCircuityFactor;
          final newTotalCost =
              bestCostOverall[stopId]! + walkingCost(realTransferDist);
          if (newTotalCost < bestCostOverall[transfer.toStopId]!) {
            bestCostOverall[transfer.toStopId] = newTotalCost;
            roundCosts[currentRound][transfer.toStopId] = newTotalCost;
            parents[(currentRound, transfer.toStopId)] = _Parent(
              fromStopId: stopId,
              fromRound: currentRound,
              routeId: null,
              distance: realTransferDist,
            );
            newlyMarkedByWalk.add(transfer.toStopId);
          }
        }
      }
      markedStops.addAll(newlyMarkedByWalk);

      // --- Final Walking Check (Stop -> Destination) ---
      final roundReachable = <_ResultMeta>[];

      for (var stopId in allStops.keys) {
        final costToStop = roundCosts[currentRound][stopId]!;
        if (costToStop >= infinity) continue;

        final stop = allStops[stopId]!;
        final d =
            computeDistance(
              stop.stopLat,
              stop.stopLon,
              destLat,
              destLng,
            ) *
            _walkCircuityFactor;
        if (d <= walkingLimit) {
          roundReachable.add(
            _ResultMeta(
              stopId: stopId,
              round: currentRound,
              totalCost: costToStop + walkingCost(d),
              finalDist: d,
            ),
          );
        }
      }

      roundReachable.sort((a, b) => a.totalCost.compareTo(b.totalCost));

      // Keep the cheapest candidate per distinct arrival route this round.
      final seenRoutesThisRound = <String>{};
      for (final meta in roundReachable) {
        final arrivalRoute =
            parents[(currentRound, meta.stopId)]?.routeId ?? 'walk';
        if (seenRoutesThisRound.add(arrivalRoute)) {
          candidates['${arrivalRoute}_r$currentRound'] = meta;
        }
        if (seenRoutesThisRound.length >= _maxCandidatesPerRoute) break;
      }
    }

    // --- Reconstruct Results ---
    final allJourneys = <Journey>[];
    for (final meta in candidates.values) {
      Journey journey;
      if (meta.stopId == "__DIRECT__") {
        journey = Journey([
          Leg(
            fromStopId: "__ORIGIN__",
            toStopId: "__DESTINATION__",
            distance: meta.finalDist,
            fromStopName: 'origin',
            toStopName: 'destination',
            vehicleType: VehicleType.walk,
          ),
        ], routingCost: meta.totalCost);
      } else {
        journey = _reconstructSingleJourney(
          meta.stopId,
          meta.round,
          meta.finalDist,
          parents,
          allStops,
          routesById,
          meta.totalCost,
        );
      }

      allJourneys.add(journey);
    }
    sortJourneys(allJourneys, options.priority);
    final seen = <String>{};
    return allJourneys
        .where((journey) => seen.add(journey.signature))
        .take(_maxResults)
        .toList();
  }

  void sortJourneys(List<Journey> journeys, RoutePriority priority) =>
      journeys.sort((a, b) => _compareJourneys(a, b, priority));

  int _compareJourneys(
    Journey a,
    Journey b,
    RoutePriority priority,
  ) {
    final primary = switch (priority) {
      RoutePriority.fastest => a.estimatedDurationSeconds.compareTo(
        b.estimatedDurationSeconds,
      ),
      RoutePriority.fewerTransfers => a.boardings.compareTo(b.boardings),
      RoutePriority.lessWalking => a.walkingDistance.compareTo(
        b.walkingDistance,
      ),
    };
    if (primary != 0) return primary;
    if (priority != RoutePriority.fastest) {
      final duration = a.estimatedDurationSeconds.compareTo(
        b.estimatedDurationSeconds,
      );
      if (duration != 0) return duration;
    }
    final cost = a.routingCost.compareTo(b.routingCost);
    return cost != 0 ? cost : a.signature.compareTo(b.signature);
  }

  TransportMode? _transportMode(VehicleType type) => switch (type) {
    VehicleType.train => TransportMode.train,
    VehicleType.bus => TransportMode.bus,
    VehicleType.jeep => TransportMode.jeep,
    VehicleType.uvExpress => TransportMode.uvExpress,
    VehicleType.tricycle => TransportMode.tricycle,
    VehicleType.walk || VehicleType.unknown => null,
  };

  Journey _reconstructSingleJourney(
    String lastStopId,
    int lastRound,
    double lastDist,
    Map<(int, String), _Parent> parents,
    Map<String, StopsAndStopTimesModel> allStops,
    Map<String, RaptorRoute> routesById,
    double routingCost,
  ) {
    final legs = <Leg>[];

    final lastStop = allStops[lastStopId]!;
    legs.add(
      Leg(
        fromStopId: lastStopId,
        toStopId: "__DESTINATION__",
        distance: lastDist,
        fromStopName: lastStop.stopName,
        toStopName: 'destination',
        vehicleType: VehicleType.walk,
      ),
    );

    String currentStopId = lastStopId;
    var currentRound = lastRound;
    while (currentStopId != "__ORIGIN__") {
      final parent = parents[(currentRound, currentStopId)];
      if (parent == null) break;

      final isWalking = parent.routeId == null;
      final fromStop = parent.fromStopId == "__ORIGIN__"
          ? null
          : allStops[parent.fromStopId];
      final toStop = allStops[currentStopId];

      if (isWalking) {
        legs.insert(
          0,
          Leg(
            fromStopId: parent.fromStopId,
            toStopId: currentStopId,
            distance: parent.distance ?? 0.0,
            fromStopName: fromStop?.stopName ?? 'origin',
            toStopName: toStop!.stopName,
            vehicleType: VehicleType.walk,
          ),
        );
      } else {
        final rr = routesById[parent.routeId!];

        // Calculate transit distance along the route
        double transitDist = 0.0;
        if (rr != null) {
          final stops = rr.stops.map((s) => s.stopId).toList();
          final startIdx = stops.indexOf(parent.fromStopId);
          final endIdx = stops.indexOf(currentStopId);
          if (startIdx != -1 && endIdx != -1 && startIdx < endIdx) {
            transitDist =
                rr.cumulativeDistances[endIdx] -
                rr.cumulativeDistances[startIdx];
          }
        }

        legs.insert(
          0,
          Leg(
            fromStopId: parent.fromStopId,
            toStopId: currentStopId,
            routeId: rr?.sourceRouteId ?? parent.routeId!,
            tripId: rr?.tripId ?? '',
            distance: transitDist,
            routeLongName: rr?.routeLongName ?? 'Unknown Route',
            vehicleType: rr?.vehicleType ?? VehicleType.bus,
            fromStopName: fromStop?.stopName ?? 'origin',
            toStopName: toStop!.stopName,
          ),
        );
      }
      currentStopId = parent.fromStopId;
      currentRound = parent.fromRound;
    }

    return Journey(legs, routingCost: routingCost);
  }
}
