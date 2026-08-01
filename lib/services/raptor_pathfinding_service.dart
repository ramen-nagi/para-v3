import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:para_v3/services/gtfs_network_service.dart';

class Leg {
  final String fromStopId;
  final String toStopId;
  final int startTime;
  final int endTime;
  final String? routeId;
  final bool isWalking;
  final double? distance;

  Leg({
    required this.fromStopId,
    required this.toStopId,
    required this.startTime,
    required this.endTime,
    this.routeId,
    required this.isWalking,
    this.distance,
  });
}

class WalkLeg extends Leg {
  final String fromStopName;
  final String toStopName;

  WalkLeg({
    required super.fromStopId,
    required super.toStopId,
    required super.distance,
    required this.fromStopName,
    required this.toStopName,
  }) : super(
          startTime: 0,
          endTime: 0,
          isWalking: true,
        );
}

class TransitLeg extends Leg {
  final String routeLongName;
  final VehicleType vehicleType;
  final String fromStopName;
  final String toStopName;

  TransitLeg({
    required super.fromStopId,
    required super.toStopId,
    required super.routeId,
    required super.distance,
    required this.routeLongName,
    required this.vehicleType,
    required this.fromStopName,
    required this.toStopName,
  }) : super(
          startTime: 0,
          endTime: 0,
          isWalking: false,
        );
}

class Journey {
  final List<Leg> legs;
  Journey(this.legs);

  double get cost => legs.fold(0.0, (sum, leg) => sum + (leg.distance ?? 0.0));
}

class RaptorRoute {
  final String routeId;
  final String routeLongName;
  final VehicleType vehicleType;
  final List<StopsAndStopTimesModel> stops;
  final List<double> cumulativeDistances;

  RaptorRoute({
    required this.routeId,
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
  final double totalCost;
  final double finalDist;
  final Map<String, _Parent> parents;

  _ResultMeta({
    required this.stopId,
    required this.totalCost,
    required this.finalDist,
    required this.parents,
  });
}

class _Parent {
  final String fromStopId;
  final String? routeId;
  final double? distance;

  _Parent({required this.fromStopId, this.routeId, this.distance});
}

class RaptorPathfindingService {
  static final RaptorPathfindingService instance = RaptorPathfindingService._();
  RaptorPathfindingService._();

  static const int infinity = 1000000;

  // ── Algorithm tuning constants ───────────────────────────────────────────
  static const double _maxWalkingRadius    = 5000.0; // meters, dest walk limit
  static const double _transitCostWeight   = 0.05;   // cost per meter on transit
  static const double _transferPenalty     = 500.0;  // discourages extra transfers
  static const double _walkCircuityFactor  = 1.4;    // straight-line → city-block
  static const double _trainCostDivisor    = 1.7;    // trains cheaper relative to cost
  static const double _originSearchRadius  = 3000.0; // initial origin walk radius
  static const int    _maxRounds           = 6;
  static const int    _maxResults          = 3;
  static const int    _maxCandidatesPerRoute = 5;
  // ─────────────────────────────────────────────────────────────────────────

  // Haversine formula to compute distance in meters between two points
  double computeDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // in meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
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
  }) {
    if (!GtfsNetworkService.instance.isLoaded) {
      debugPrint('RAPTOR Error: GTFS dataset not loaded yet.');
      return [];
    }

    // 1. Gather all unique stops and RaptorRoutes
    final Map<String, StopsAndStopTimesModel> allStops = {};
    final List<RaptorRoute> allRoutes = [];
    final Map<String, RaptorRoute> routesById = {};
    final Set<String> seenSequences = {};

    for (final route in GtfsNetworkService.instance.routesMap.values) {
      for (final trip in route.trips) {
        final sortedStops = List<StopsAndStopTimesModel>.from(trip.stopTimes)
          ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
        
        if (sortedStops.isEmpty) continue;

        // Populate stops
        for (final stop in sortedStops) {
          allStops[stop.stopId] = stop;
        }

        // Group into unique routes by stop sequence signature
        final sequenceSignature = sortedStops.map((s) => s.stopId).join('->');
        if (!seenSequences.contains(sequenceSignature)) {
          seenSequences.add(sequenceSignature);
          
          // Precompute cumulative distances along the route
          final List<double> cumulativeDistances = [0.0];
          double accum = 0.0;
          for (int idx = 0; idx < sortedStops.length - 1; idx++) {
            accum += computeDistance(
              sortedStops[idx].stopLat, sortedStops[idx].stopLon,
              sortedStops[idx + 1].stopLat, sortedStops[idx + 1].stopLon,
            );
            cumulativeDistances.add(accum);
          }

          final raptorRouteId = '${route.routeId}_p${seenSequences.length}';
          final rr = RaptorRoute(
            routeId: raptorRouteId,
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
      debugPrint('RAPTOR Warning: No stops or routes found in dataset.');
      return [];
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

    List<StopsAndStopTimesModel> getNearbyStops(double lat, double lon, double maxDist) {
      final List<StopsAndStopTimesModel> nearby = [];
      final int latKey = (lat * 100).floor();
      final int lonKey = (lon * 100).floor();

      for (int dl = -1; dl <= 1; dl++) {
        for (int dg = -1; dg <= 1; dg++) {
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
      final nearby = getNearbyStops(stop.stopLat, stop.stopLon, 800.0);
      final List<Transfer> list = [];
      for (final other in nearby) {
        if (other.stopId == stop.stopId) continue;
        final d = computeDistance(stop.stopLat, stop.stopLon, other.stopLat, other.stopLon);
        list.add(Transfer(toStopId: other.stopId, distance: d));
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

    final parents = <String, _Parent>{};

    // --- Initial Walking Phase (Origin -> Stops) ---
    List<Transfer> originNearby = [];
    double currentOriginRadius = _originSearchRadius;

    // Expand radius until at least one stop is found, up to 5km
    while (originNearby.isEmpty && currentOriginRadius <= 5000.0) {
      final nearby = getNearbyStops(originLat, originLng, currentOriginRadius);
      originNearby = nearby.map((s) => Transfer(
        toStopId: s.stopId,
        distance: computeDistance(originLat, originLng, s.stopLat, s.stopLon),
      )).toList();

      if (originNearby.isEmpty) {
        currentOriginRadius += 500.0;
      }
    }

    var markedStops = <String>{};
    for (var transfer in originNearby) {
      final realWalkingDist = transfer.distance * _walkCircuityFactor;
      bestCostOverall[transfer.toStopId] = realWalkingDist;
      roundCosts[0][transfer.toStopId] = realWalkingDist;
      parents[transfer.toStopId] = _Parent(
        fromStopId: "__ORIGIN__",
        routeId: null,
        distance: realWalkingDist,
      );
      markedStops.add(transfer.toStopId);
    }

    var currentRound = 0;

    // Track best candidates from each round for multi-journey options
    final candidates = <String, _ResultMeta>{};

    // --- Direct Walk Option ---
    final directWalkDist =
        computeDistance(originLat, originLng, destLat, destLng) * _walkCircuityFactor;
    candidates["__DIRECT__"] = _ResultMeta(
      stopId: "__DIRECT__",
      totalCost: directWalkDist,
      finalDist: directWalkDist,
      parents: {},
    );

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
            final penalty = currentRound > 1 ? _transferPenalty : 0.0;
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
            final isTrain = routeId.startsWith('ROUTE') || (rr?.vehicleType == VehicleType.train);
            final effectiveWeight = isTrain
                ? (_transitCostWeight / _trainCostDivisor)
                : _transitCostWeight;

            final arrivalCost =
                costAtBoarding + (transitDist * effectiveWeight);

            if (arrivalCost < bestCostOverall[stopId]!) {
              bestCostOverall[stopId] = arrivalCost;
              roundCosts[currentRound][stopId] = arrivalCost;
              parents[stopId] = _Parent(
                fromStopId: boardingStopId!,
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
          final newTotalCost = bestCostOverall[stopId]! + realTransferDist;
          if (newTotalCost < bestCostOverall[transfer.toStopId]!) {
            bestCostOverall[transfer.toStopId] = newTotalCost;
            roundCosts[currentRound][transfer.toStopId] = newTotalCost;
            parents[transfer.toStopId] = _Parent(
              fromStopId: stopId,
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
        final d = computeDistance(stop.stopLat, stop.stopLon, destLat, destLng);
        if (d <= _maxWalkingRadius) {
          roundReachable.add(_ResultMeta(
            stopId: stopId,
            totalCost: costToStop + d,
            finalDist: d,
            parents: Map.from(parents),
          ));
        }
      }

      roundReachable.sort((a, b) => a.totalCost.compareTo(b.totalCost));

      // Keep the cheapest candidate per distinct arrival route this round.
      final seenRoutesThisRound = <String>{};
      for (final meta in roundReachable) {
        final arrivalRoute = parents[meta.stopId]?.routeId ?? 'walk';
        if (seenRoutesThisRound.add(arrivalRoute)) {
          candidates['${arrivalRoute}_r$currentRound'] = meta;
        }
        if (seenRoutesThisRound.length >= _maxCandidatesPerRoute) break;
      }
    }

    // --- Exhaustive Fallback ---
    if (candidates.length <= 1) {
      String? fallbackStop;
      double fallbackCost = infinity.toDouble();
      double? fallbackDist;

      for (var entry in bestCostOverall.entries) {
        final stopId = entry.key;
        final costToStop = entry.value;
        if (costToStop >= infinity) continue;

        final stop = allStops[stopId]!;
        final d = computeDistance(stop.stopLat, stop.stopLon, destLat, destLng);
        if (d <= 5000.0) {
          final realWalkDist = d * _walkCircuityFactor;
          final totalCost = costToStop + realWalkDist;
          if (totalCost < fallbackCost) {
            fallbackCost = totalCost;
            fallbackStop = stopId;
            fallbackDist = realWalkDist;
          }
        }
      }
      if (fallbackStop != null) {
        candidates["fallback"] = _ResultMeta(
          stopId: fallbackStop,
          totalCost: fallbackCost,
          finalDist: fallbackDist!,
          parents: Map.from(parents),
        );
      }
    }

    // --- Reconstruct Results ---
    final allJourneys = <Journey>[];

    final sortedMetas = candidates.values.toList()
      ..sort((a, b) => a.totalCost.compareTo(b.totalCost));

    for (var meta in sortedMetas) {
      Journey journey;
      if (meta.stopId == "__DIRECT__") {
        journey = Journey([
          WalkLeg(
            fromStopId: "__ORIGIN__",
            toStopId: "__DESTINATION__",
            distance: meta.finalDist,
            fromStopName: 'origin',
            toStopName: 'destination',
          ),
        ]);
      } else {
        journey = _reconstructSingleJourney(
          meta.stopId,
          meta.finalDist,
          meta.parents,
          allStops,
          routesById,
        );
      }

      allJourneys.add(journey);

      if (allJourneys.length >= _maxResults) break;
    }

    return allJourneys;
  }

  Journey _reconstructSingleJourney(
    String lastStopId,
    double lastDist,
    Map<String, _Parent> parents,
    Map<String, StopsAndStopTimesModel> allStops,
    Map<String, RaptorRoute> routesById,
  ) {
    final legs = <Leg>[];

    final lastStop = allStops[lastStopId]!;
    legs.add(
      WalkLeg(
        fromStopId: lastStopId,
        toStopId: "__DESTINATION__",
        distance: lastDist,
        fromStopName: lastStop.stopName,
        toStopName: 'destination',
      ),
    );

    String currentStopId = lastStopId;
    while (currentStopId != "__ORIGIN__") {
      final parent = parents[currentStopId];
      if (parent == null) break;

      final isWalking = parent.routeId == null;
      final fromStop = parent.fromStopId == "__ORIGIN__" ? null : allStops[parent.fromStopId];
      final toStop = allStops[currentStopId];

      if (isWalking) {
        legs.insert(
          0,
          WalkLeg(
            fromStopId: parent.fromStopId,
            toStopId: currentStopId,
            distance: parent.distance ?? 0.0,
            fromStopName: fromStop?.stopName ?? 'origin',
            toStopName: toStop!.stopName,
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
            transitDist = rr.cumulativeDistances[endIdx] - rr.cumulativeDistances[startIdx];
          }
        }

        legs.insert(
          0,
          TransitLeg(
            fromStopId: parent.fromStopId,
            toStopId: currentStopId,
            routeId: parent.routeId!,
            distance: transitDist,
            routeLongName: rr?.routeLongName ?? 'Unknown Route',
            vehicleType: rr?.vehicleType ?? VehicleType.bus,
            fromStopName: fromStop?.stopName ?? 'origin',
            toStopName: toStop!.stopName,
          ),
        );
      }
      currentStopId = parent.fromStopId;
    }

    return Journey(legs);
  }
}
