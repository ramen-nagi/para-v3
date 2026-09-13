import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/gtfs_network_service.dart';

typedef WalkingDistanceResolver =
    Future<Map<String, double>> Function(
      Position anchor,
      Map<String, Position> destinations, {
      bool pointsToAnchor,
    });

class NavigationStep {
  final String instruction;
  final double? distanceMeters;
  final double? durationSeconds;

  const NavigationStep({
    required this.instruction,
    this.distanceMeters,
    this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
    'instruction': instruction,
    'distanceMeters': distanceMeters,
    'durationSeconds': durationSeconds,
  };

  factory NavigationStep.fromJson(Map<String, dynamic> json) => NavigationStep(
    instruction: json['instruction'] as String,
    distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
    durationSeconds: (json['durationSeconds'] as num?)?.toDouble(),
  );
}

class Leg {
  final String fromStopId;
  final String toStopId;
  final String fromStopName;
  final String toStopName;
  final String? routeId;
  final String? raptorRouteId;
  final String? tripId;
  final String? routeLongName;
  final VehicleType vehicleType;
  List<Position>? coordinates;
  double? distance;
  double? durationSeconds;
  double? fare;
  List<String?>? traffic;
  List<NavigationStep>? steps;

  Leg({
    required this.fromStopId,
    required this.toStopId,
    required this.fromStopName,
    required this.toStopName,
    required this.vehicleType,
    this.routeId,
    this.raptorRouteId,
    this.tripId,
    this.routeLongName,
    this.coordinates,
    this.distance,
    this.durationSeconds,
    this.fare,
    this.traffic,
    this.steps,
  });

  bool get isWalking => vehicleType == VehicleType.walk;

  Map<String, dynamic> toJson() => {
    'fromStopId': fromStopId,
    'toStopId': toStopId,
    'fromStopName': fromStopName,
    'toStopName': toStopName,
    'routeId': routeId,
    'raptorRouteId': raptorRouteId,
    'tripId': tripId,
    'routeLongName': routeLongName,
    'vehicleType': vehicleType.rawValue,
    'coordinates': coordinates
        ?.map((position) => [position.lng, position.lat])
        .toList(),
    'distance': distance,
    'durationSeconds': durationSeconds,
    'fare': fare,
    'traffic': traffic,
    'steps': steps?.map((step) => step.toJson()).toList(),
  };

  factory Leg.fromJson(Map<String, dynamic> json) {
    final coordinateValues = json['coordinates'] as List?;
    final trafficValues = json['traffic'] as List?;
    final stepValues = json['steps'] as List?;
    final serializedRouteId = json['routeId'] as String?;
    final legacySourceRouteId = json['sourceRouteId'] as String?;
    return Leg(
      fromStopId: json['fromStopId'] as String,
      toStopId: json['toStopId'] as String,
      fromStopName: json['fromStopName'] as String,
      toStopName: json['toStopName'] as String,
      routeId: legacySourceRouteId ?? serializedRouteId,
      raptorRouteId:
          json['raptorRouteId'] as String? ??
          (legacySourceRouteId == null ? null : serializedRouteId),
      tripId: json['tripId'] as String?,
      routeLongName: json['routeLongName'] as String?,
      vehicleType: VehicleType.fromInt((json['vehicleType'] as num).toInt()),
      coordinates: coordinateValues?.map((value) {
        final pair = value as List;
        return Position(
          (pair[0] as num).toDouble(),
          (pair[1] as num).toDouble(),
        );
      }).toList(),
      distance: (json['distance'] as num?)?.toDouble(),
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble(),
      fare: (json['fare'] as num?)?.toDouble(),
      traffic: trafficValues?.map((value) => value as String?).toList(),
      steps: stepValues
          ?.map(
            (value) => NavigationStep.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(),
    );
  }
}

class Journey {
  // Generalized distance score, not fare or physical distance.
  static const double transitDistanceWeight = 0.5;
  static const double trainDistanceWeight = 0.3;
  static const double transferPenalty = 500.0;

  static double distanceWeight(VehicleType type, {bool penalized = false}) =>
      (type == VehicleType.train
          ? trainDistanceWeight
          : transitDistanceWeight) *
      (penalized ? 1.1 : 1.0);

  final List<Leg> legs;
  final String? originMainText;
  final String? destinationMainText;

  Journey(
    this.legs, {
    this.originMainText,
    this.destinationMainText,
  });

  double get cost => legs.fold(0.0, (sum, leg) => sum + (leg.distance ?? 0.0));

  double get rankingCost => calculateRankingCost();

  double calculateRankingCost({
    Set<VehicleType> penalizedVehicleTypes = const {},
  }) {
    var score = 0.0;
    var boardings = 0;
    for (final leg in legs) {
      final distance = leg.distance ?? 0.0;
      if (leg.isWalking) {
        score += distance;
      } else {
        score +=
            distance *
            distanceWeight(
              leg.vehicleType,
              penalized: penalizedVehicleTypes.contains(leg.vehicleType),
            );
        if (boardings > 0) score += transferPenalty;
        boardings++;
      }
    }
    return score;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'originMainText': originMainText,
    'destinationMainText': destinationMainText,
    'legs': legs.map((leg) => leg.toJson()).toList(),
  };

  factory Journey.fromJson(Map<String, dynamic> json) {
    final legValues = json['legs'] as List;
    return Journey(
      legValues
          .map((value) => Leg.fromJson(Map<String, dynamic>.from(value as Map)))
          .toList(),
      originMainText: json['originMainText'] as String?,
      destinationMainText: json['destinationMainText'] as String?,
    );
  }
}

class RaptorRoute {
  final String routeId;
  final String raptorRouteId;
  final String tripId;
  final String routeLongName;
  final VehicleType vehicleType;
  final List<StopsAndStopTimesModel> stops;
  final List<double> cumulativeDistances;

  RaptorRoute({
    required this.routeId,
    required this.raptorRouteId,
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

// Each label owns its path; later rounds cannot change its ancestry.
class _Label {
  final double cost;
  final List<Leg> legs;
  final String signature;

  _Label(this.cost, this.legs)
    : signature = legs
          .where((leg) => !leg.isWalking)
          .map((leg) => leg.raptorRouteId)
          .join('|');
}

class _Boarding {
  final _Label label;
  final int index;
  final double offset;
  _Boarding(this.label, this.index, this.offset);
}

class RaptorPathfindingService {
  static final RaptorPathfindingService instance = RaptorPathfindingService._();
  RaptorPathfindingService._();

  static const int infinity = 1000000;

  // Algorithm tuning constants.
  static const double _maxWalkingRadius = 5000.0; // meters, dest walk limit
  static const double _walkOnlyThreshold = 500.0;
  static const double _walkCircuityFactor = 1.4; // Estimated walking distance.
  static const int _endpointBatchSize = 24;
  static const List<double> _endpointRadii = [800, 1600, 3000, 5000];
  final _walkingCache = <String, ({double distance, DateTime expires})>{};
  WalkingDistanceResolver? _cachedResolver;
  static const int _maxRounds = 6;
  static const int _maxResults = 3;

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

  /// Returns up to three distinct transit service sequences by weighted distance
  /// plus transfer penalties, using the same scoring as [Journey.rankingCost].
  /// A direct walk is preferred when it scores better than the best transit
  /// journey. Disabled vehicle types cost 10% more per transit meter; walking
  /// and transfer penalties are unaffected.
  /// Search is bounded by the walking radii and six boardings; missing road
  /// distances or GTFS geometry use geographic estimates.
  Future<List<Journey>> findJourneys({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    Set<VehicleType> penalizedVehicleTypes = const {},
    WalkingDistanceResolver? walkingDistanceResolver,
  }) async {
    if (!GtfsNetworkService.instance.isLoaded) {
      debugPrint('RAPTOR Error: GTFS dataset not loaded yet.');
      return [];
    }

    const directKey = '__DIRECT_DESTINATION__';
    final directWalkLowerBound = computeDistance(
      originLat,
      originLng,
      destLat,
      destLng,
    );
    double? resolvedDirectWalkDistance;
    Future<double> resolveDirectWalkDistance() async {
      final resolved = resolvedDirectWalkDistance;
      if (resolved != null) return resolved;
      final directDistances = walkingDistanceResolver == null
          ? <String, double>{}
          : await _resolveWalkingDistances(
              walkingDistanceResolver,
              Position(originLng, originLat),
              {directKey: Position(destLng, destLat)},
            );
      return resolvedDirectWalkDistance =
          directDistances[directKey] ??
          directWalkLowerBound * _walkCircuityFactor;
    }

    Journey directWalkJourney(double distance) => Journey([
      Leg(
        fromStopId: '__ORIGIN__',
        toStopId: '__DESTINATION__',
        fromStopName: 'origin',
        toStopName: 'destination',
        vehicleType: VehicleType.walk,
        distance: distance,
      ),
    ]);

    // A route cannot be shorter than its geographic lower bound, so only a
    // nearby pair can qualify for the walk-only rule.
    if (directWalkLowerBound < _walkOnlyThreshold) {
      final directWalkDistance = await resolveDirectWalkDistance();
      if (directWalkDistance.isFinite &&
          directWalkDistance >= 0 &&
          directWalkDistance < _walkOnlyThreshold) {
        return [directWalkJourney(directWalkDistance)];
      }
    }

    // 1. Gather all unique stops and RaptorRoutes
    final Map<String, StopsAndStopTimesModel> allStops = {};
    final List<RaptorRoute> allRoutes = [];
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
        final sequenceSignature =
            '${route.routeId}:${trip.shapeId}:'
            '${sortedStops.map((s) => s.stopId).join('->')}';
        if (!seenSequences.contains(sequenceSignature)) {
          seenSequences.add(sequenceSignature);

          // Precompute cumulative distances along the route
          final cumulativeDistances = _routeDistances(sortedStops, trip.shapes);

          final raptorRouteId = '${route.routeId}_p${seenSequences.length}';
          final rr = RaptorRoute(
            routeId: route.routeId,
            raptorRouteId: raptorRouteId,
            tripId: trip.tripId,
            routeLongName: route.routeLongName,
            vehicleType: route.vehicleType,
            stops: sortedStops,
            cumulativeDistances: cumulativeDistances,
          );
          allRoutes.add(rr);
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

    List<StopsAndStopTimesModel> getNearbyStops(
      double lat,
      double lon,
      double maxDist,
    ) {
      final List<StopsAndStopTimesModel> nearby = [];
      final int latKey = (lat * 100).floor();
      final int lonKey = (lon * 100).floor();

      final latCellRadius = (maxDist / 1105.4).ceil();
      final longitudeMetersPerDegree = 111320 * math.cos(_toRadians(lat)).abs();
      final lonCellRadius = longitudeMetersPerDegree < 1
          ? latCellRadius
          : (maxDist * 100 / longitudeMetersPerDegree).ceil();

      for (int dl = -latCellRadius; dl <= latCellRadius; dl++) {
        for (int dg = -lonCellRadius; dg <= lonCellRadius; dg++) {
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

    // Precompute transfers (walks between stops)
    final Map<String, List<Transfer>> transfers = {};
    for (final stop in allStops.values) {
      final nearby = getNearbyStops(stop.stopLat, stop.stopLon, 800.0);
      final List<Transfer> list = [];
      for (final other in nearby) {
        if (other.stopId == stop.stopId) continue;
        final d = computeDistance(
          stop.stopLat,
          stop.stopLon,
          other.stopLat,
          other.stopLon,
        );
        list.add(Transfer(toStopId: other.stopId, distance: d));
      }
      transfers[stop.stopId] = list;
    }

    final boardingServices = <String, Set<String>>{};
    final alightingServices = <String, Set<String>>{};
    for (final route in allRoutes) {
      for (var i = 0; i < route.stops.length; i++) {
        final id = route.stops[i].stopId;
        if (i < route.stops.length - 1) {
          boardingServices.putIfAbsent(id, () => {}).add(route.raptorRouteId);
        }
        if (i > 0) {
          alightingServices.putIfAbsent(id, () => {}).add(route.raptorRouteId);
        }
      }
    }
    List<Transfer> endpoints(
      double lat,
      double lng,
      Map<String, Set<String>> services,
    ) =>
        getNearbyStops(lat, lng, _maxWalkingRadius)
            .where((stop) => services.containsKey(stop.stopId))
            .map(
              (stop) => Transfer(
                toStopId: stop.stopId,
                distance: computeDistance(lat, lng, stop.stopLat, stop.stopLon),
              ),
            )
            .toList()
          ..sort((a, b) => a.distance.compareTo(b.distance));
    final originOptions = endpoints(originLat, originLng, boardingServices);
    final destinationOptions = endpoints(destLat, destLng, alightingServices);
    // Optimistic connectivity filter: only stop order and possible footpaths,
    // with no network requests. Reverse scans use the symmetric footpath graph.
    Set<String> reachable(Set<String> seeds, {bool reverse = false}) {
      var previous = seeds;
      final reached = <String>{};
      for (var round = 0; round < _maxRounds; round++) {
        final rides = <String>{};
        for (final route in allRoutes) {
          var aboard = false;
          for (final stop in reverse ? route.stops.reversed : route.stops) {
            if (aboard) rides.add(stop.stopId);
            if (previous.contains(stop.stopId)) aboard = true;
          }
        }
        final next = <String>{...rides};
        for (final id in rides) {
          next.addAll((transfers[id] ?? <Transfer>[]).map((t) => t.toStopId));
        }
        final oldSize = reached.length;
        reached.addAll(next);
        if (reached.length == oldSize) break;
        previous = next;
      }
      return reached;
    }

    final canReachDestination = reachable(
      destinationOptions.map((stop) => stop.toStopId).toSet(),
      reverse: true,
    );
    final originPool = originOptions
        .where((stop) => canReachDestination.contains(stop.toStopId))
        .toList();
    final fromOrigin = reachable(
      originPool.map((stop) => stop.toStopId).toSet(),
    );
    final destinationPool = destinationOptions
        .where((stop) => fromOrigin.contains(stop.toStopId))
        .toList();
    final originNearby = <Transfer>[];
    final destinationNearby = <Transfer>[];
    final originRoadDistances = <String, double>{};
    final destinationRoadDistances = <String, double>{};
    // Bounds must allow the cheapest available mode, including a later train
    // transfer, or they could incorrectly prune a competitive train journey.
    final minimumTransitWeight = allRoutes.fold<double>(
      Journey.transitDistanceWeight,
      (weight, route) => math.min(
        weight,
        Journey.distanceWeight(
          route.vehicleType,
          penalized: penalizedVehicleTypes.contains(route.vehicleType),
        ),
      ),
    );

    List<_Label> search() {
      final destinationIds = destinationNearby
          .map((stop) => stop.toStopId)
          .toSet();
      var previousRound = <String, List<_Label>>{};
      for (final transfer in originNearby) {
        final distance =
            originRoadDistances[transfer.toStopId] ??
            transfer.distance * _walkCircuityFactor;
        if (!distance.isFinite ||
            distance < 0 ||
            distance > _maxWalkingRadius) {
          continue;
        }
        previousRound[transfer.toStopId] = [
          _Label(distance, [
            Leg(
              fromStopId: '__ORIGIN__',
              toStopId: transfer.toStopId,
              fromStopName: 'origin',
              toStopName: allStops[transfer.toStopId]!.stopName,
              vehicleType: VehicleType.walk,
              distance: distance,
            ),
          ]),
        ];
      }

      final candidates = <String, _Label>{};
      // Weighted-distance RAPTOR: one round per vehicle boarded. Keep the
      // cheapest three distinct service sequences at each stop.
      for (
        var round = 1;
        round <= _maxRounds && previousRound.isNotEmpty;
        round++
      ) {
        final arrivals = <String, List<_Label>>{};
        for (final rr in allRoutes) {
          final transitWeight = Journey.distanceWeight(
            rr.vehicleType,
            penalized: penalizedVehicleTypes.contains(rr.vehicleType),
          );
          final boardings = <_Boarding>[];
          for (var i = 0; i < rr.stops.length; i++) {
            final stop = rr.stops[i];
            // Alight before considering boarding here (no zero-length rides).
            for (final boarding in boardings) {
              final distance =
                  rr.cumulativeDistances[i] -
                  rr.cumulativeDistances[boarding.index];
              final from = rr.stops[boarding.index];
              _retainLabel(
                arrivals,
                stop.stopId,
                _Label(
                  boarding.offset + rr.cumulativeDistances[i] * transitWeight,
                  [
                    ...boarding.label.legs,
                    Leg(
                      fromStopId: from.stopId,
                      toStopId: stop.stopId,
                      fromStopName: from.stopName,
                      toStopName: stop.stopName,
                      routeId: rr.routeId,
                      raptorRouteId: rr.raptorRouteId,
                      tripId: rr.tripId,
                      routeLongName: rr.routeLongName,
                      vehicleType: rr.vehicleType,
                      distance: distance,
                    ),
                  ],
                ),
              );
            }
            for (final label in previousRound[stop.stopId] ?? <_Label>[]) {
              // Reboarding the same service only creates redundant alternatives.
              if (label.legs.any(
                (leg) => leg.raptorRouteId == rr.raptorRouteId,
              )) {
                continue;
              }
              final boarding = _Boarding(
                label,
                i,
                label.cost +
                    (round > 1 ? Journey.transferPenalty : 0) -
                    rr.cumulativeDistances[i] * transitWeight,
              );
              final existing = boardings.indexWhere(
                (item) => item.label.signature == label.signature,
              );
              if (existing >= 0) {
                if (boardings[existing].offset <= boarding.offset) continue;
                boardings.removeAt(existing);
              }
              boardings.add(boarding);
              boardings.sort((a, b) => a.offset.compareTo(b.offset));
              if (boardings.length > _maxResults) boardings.removeLast();
            }
          }
        }

        // Evaluate every alighting stop before transfers can replace its label.
        for (final entry in arrivals.entries) {
          if (!destinationIds.contains(entry.key)) continue;
          final stop = allStops[entry.key]!;
          final distance =
              destinationRoadDistances[entry.key] ??
              computeDistance(stop.stopLat, stop.stopLon, destLat, destLng) *
                  _walkCircuityFactor;
          if (!distance.isFinite ||
              distance < 0 ||
              distance > _maxWalkingRadius) {
            continue;
          }
          for (final label in entry.value) {
            final result = _Label(label.cost + distance, [
              ...label.legs,
              Leg(
                fromStopId: stop.stopId,
                toStopId: '__DESTINATION__',
                fromStopName: stop.stopName,
                toStopName: 'destination',
                vehicleType: VehicleType.walk,
                distance: distance,
              ),
            ]);
            final existing = candidates[result.signature];
            if (existing == null || result.cost < existing.cost) {
              candidates[result.signature] = result;
            }
          }
        }

        // Read only transit arrivals, so footpaths cannot chain in one round.
        final nextRound = <String, List<_Label>>{
          for (final entry in arrivals.entries) entry.key: List.of(entry.value),
        };
        for (final entry in arrivals.entries) {
          for (final transfer in transfers[entry.key] ?? <Transfer>[]) {
            final distance = transfer.distance * _walkCircuityFactor;
            for (final label in entry.value) {
              _retainLabel(
                nextRound,
                transfer.toStopId,
                _Label(
                  label.cost + distance,
                  [
                    ...label.legs,
                    Leg(
                      fromStopId: entry.key,
                      toStopId: transfer.toStopId,
                      fromStopName: allStops[entry.key]!.stopName,
                      toStopName: allStops[transfer.toStopId]!.stopName,
                      vehicleType: VehicleType.walk,
                      distance: distance,
                    ),
                  ],
                ),
              );
            }
          }
        }
        previousRound = nextRound;
      }

      final ranked = candidates.values.toList()
        ..sort((a, b) {
          final byScore = a.cost.compareTo(b.cost);
          if (byScore != 0) return byScore;
          int preferenceCount(_Label label) => label.legs
              .where((leg) => penalizedVehicleTypes.contains(leg.vehicleType))
              .length;
          return preferenceCount(a).compareTo(preferenceCount(b));
        });

      return ranked;
    }

    var ranked = <_Label>[];
    for (final radius in _endpointRadii) {
      final threshold = ranked.length >= _maxResults
          ? ranked[_maxResults - 1].cost
          : double.infinity;
      // A geographic lower bound never uses the 1.4 walking estimate.
      // Even if all remaining travel were discounted transit, this stop
      // cannot beat an incumbent whose score is below that bound.
      List<Transfer> shortlist(
        List<Transfer> pool,
        List<Transfer> selected,
        Map<String, Set<String>> services,
        double otherLat,
        double otherLng,
      ) {
        final usedIds = selected.map((stop) => stop.toStopId).toSet();
        final covered = <String>{
          for (final stop in selected) ...services[stop.toStopId]!,
        };
        final eligible = pool.where((stop) {
          if (usedIds.contains(stop.toStopId) || stop.distance > radius) {
            return false;
          }
          final point = allStops[stop.toStopId]!;
          final bound =
              stop.distance +
              minimumTransitWeight *
                  computeDistance(
                    point.stopLat,
                    point.stopLon,
                    otherLat,
                    otherLng,
                  );
          return bound <= threshold;
        }).toList();
        final batch = <Transfer>[];
        final locations = <String>{};
        String location(Transfer stop) {
          final point = allStops[stop.toStopId]!;
          return '${point.stopLon},${point.stopLat}';
        }

        void add(Transfer stop) {
          locations.add(location(stop));
          usedIds.add(stop.toStopId);
          covered.addAll(services[stop.toStopId]!);
          batch.add(stop);
        }

        // Cover different directional service patterns before filling by proximity.
        for (final stop in eligible) {
          if (locations.length >= _endpointBatchSize) break;
          if (services[stop.toStopId]!.any((id) => !covered.contains(id))) {
            add(stop);
          }
        }
        for (final stop in eligible) {
          if (usedIds.contains(stop.toStopId)) continue;
          if (locations.contains(location(stop)) ||
              locations.length < _endpointBatchSize) {
            add(stop);
          }
        }
        return batch;
      }

      final originBatch = shortlist(
        originPool,
        originNearby,
        boardingServices,
        destLat,
        destLng,
      );
      final destinationBatch = shortlist(
        destinationPool,
        destinationNearby,
        alightingServices,
        originLat,
        originLng,
      );
      if (originBatch.isEmpty && destinationBatch.isEmpty) continue;

      Future<Map<String, double>> resolve(
        Position anchor,
        List<Transfer> batch, {
        bool pointsToAnchor = false,
      }) async {
        if (walkingDistanceResolver == null || batch.isEmpty) return {};
        return _resolveWalkingDistances(walkingDistanceResolver, anchor, {
          for (final stop in batch)
            stop.toStopId: Position(
              allStops[stop.toStopId]!.stopLon,
              allStops[stop.toStopId]!.stopLat,
            ),
        }, pointsToAnchor: pointsToAnchor);
      }

      // Independent endpoint batches: at most two requests in flight.
      final distances = await Future.wait([
        resolve(Position(originLng, originLat), originBatch),
        resolve(
          Position(destLng, destLat),
          destinationBatch,
          pointsToAnchor: true,
        ),
      ]);
      originNearby.addAll(originBatch);
      destinationNearby.addAll(destinationBatch);
      originRoadDistances.addAll(distances[0]);
      destinationRoadDistances.addAll(distances[1]);
      ranked = search();
    }
    List<Journey> transitJourneys([int limit = _maxResults]) {
      // Copy legs: enrichment mutates them, and labels can share prefixes.
      return ranked
          .take(limit)
          .map(
            (label) => _mergeAdjacentWalkingLegs(
              Journey(
                label.legs.map((leg) => Leg.fromJson(leg.toJson())).toList(),
              ),
            ),
          )
          .toList();
    }

    // Road distance cannot be shorter than the geographic distance. Avoid an
    // extra directions request when a direct walk cannot beat the best route.
    final couldBeWalkOnly = directWalkLowerBound < _walkOnlyThreshold;
    if (ranked.isNotEmpty &&
        !couldBeWalkOnly &&
        directWalkLowerBound >= ranked.first.cost) {
      return transitJourneys();
    }

    final directWalkDist = await resolveDirectWalkDistance();
    if (!directWalkDist.isFinite || directWalkDist < 0) {
      return transitJourneys();
    }
    final directWalk = directWalkJourney(directWalkDist);
    if (directWalkDist < _walkOnlyThreshold) return [directWalk];
    if (ranked.isEmpty) return [directWalk];
    if (directWalkDist < ranked.first.cost) {
      return [directWalk, ...transitJourneys(_maxResults - 1)];
    }
    return transitJourneys();
  }

  Future<Map<String, double>> _resolveWalkingDistances(
    WalkingDistanceResolver resolver,
    Position anchor,
    Map<String, Position> points, {
    bool pointsToAnchor = false,
  }) async {
    // Resolver identity prevents mixing test/custom backends in the cache.
    if (_cachedResolver != resolver) {
      _walkingCache.clear();
      _cachedResolver = resolver;
    }
    final now = DateTime.now();
    _walkingCache.removeWhere((key, value) => !value.expires.isAfter(now));
    final result = <String, double>{};
    final pending = <String, Position>{};
    final aliases = <String, List<String>>{};
    final representative = <String, String>{};
    String key(Position point) => pointsToAnchor
        ? '${point.lng},${point.lat}>${anchor.lng},${anchor.lat}'
        : '${anchor.lng},${anchor.lat}>${point.lng},${point.lat}';
    for (final entry in points.entries) {
      final cacheKey = key(entry.value);
      final cached = _walkingCache[cacheKey];
      if (cached != null) {
        result[entry.key] = cached.distance;
      } else {
        final id = representative.putIfAbsent(cacheKey, () => entry.key);
        aliases.putIfAbsent(id, () => []).add(entry.key);
        pending[id] = entry.value;
      }
    }
    if (pending.isEmpty) return result;
    try {
      final resolved = await resolver(
        anchor,
        pending,
        pointsToAnchor: pointsToAnchor,
      );
      for (final entry in pending.entries) {
        final distance = resolved[entry.key];
        if (distance == null || distance.isNaN || distance < 0) continue;
        for (final id in aliases[entry.key]!) {
          result[id] = distance;
        }
        _walkingCache[key(entry.value)] = (
          distance: distance,
          expires: now.add(const Duration(minutes: 5)),
        );
      }
      while (_walkingCache.length > 2048) {
        _walkingCache.remove(_walkingCache.keys.first);
      }
    } catch (error) {
      debugPrint('Walking-distance lookup failed; using estimates: $error');
    }
    return result;
  }

  void _retainLabel(
    Map<String, List<_Label>> labels,
    String stopId,
    _Label label,
  ) {
    final atStop = labels.putIfAbsent(stopId, () => []);
    final existing = atStop.indexWhere(
      (item) => item.signature == label.signature,
    );
    if (existing >= 0) {
      if (atStop[existing].cost <= label.cost) return;
      atStop.removeAt(existing);
    }
    atStop.add(label);
    atStop.sort((a, b) => a.cost.compareTo(b.cost));
    if (atStop.length > _maxResults) atStop.removeLast();
  }

  // Project stops onto the ordered GTFS shape so curves and detours count.
  // Without a usable shape, stop-to-stop distances remain estimates.
  List<double> _routeDistances(
    List<StopsAndStopTimesModel> stops,
    List<ShapesModel>? shapePoints,
  ) {
    final shape = List<ShapesModel>.of(shapePoints ?? [])
      ..sort((a, b) => a.shapePtSequence.compareTo(b.shapePtSequence));
    final shapeDistances = <double>[0];
    for (var i = 1; i < shape.length; i++) {
      shapeDistances.add(
        shapeDistances.last +
            computeDistance(
              shape[i - 1].shapePtLat,
              shape[i - 1].shapePtLon,
              shape[i].shapePtLat,
              shape[i].shapePtLon,
            ),
      );
    }
    final projected = <double>[];
    for (final stop in stops) {
      var nearest = double.infinity;
      double? along;
      final scale = math.cos(_toRadians(stop.stopLat));
      for (var i = 1; i < shape.length; i++) {
        final a = shape[i - 1];
        final b = shape[i];
        final dx = (b.shapePtLon - a.shapePtLon) * scale;
        final dy = b.shapePtLat - a.shapePtLat;
        final lengthSquared = dx * dx + dy * dy;
        if (lengthSquared == 0) continue;
        final t =
            (((stop.stopLon - a.shapePtLon) * scale * dx +
                        (stop.stopLat - a.shapePtLat) * dy) /
                    lengthSquared)
                .clamp(0.0, 1.0);
        final offset =
            shapeDistances[i - 1] +
            t * (shapeDistances[i] - shapeDistances[i - 1]);
        if (projected.isNotEmpty && offset < projected.last) continue;
        final distance = computeDistance(
          stop.stopLat,
          stop.stopLon,
          a.shapePtLat + t * dy,
          a.shapePtLon + t * (b.shapePtLon - a.shapePtLon),
        );
        if (distance < nearest) {
          nearest = distance;
          along = offset;
        }
      }
      if (along == null || nearest > 250) {
        projected.clear();
        break;
      }
      projected.add(along);
    }
    final result = <double>[0];
    for (var i = 1; i < stops.length; i++) {
      final direct = computeDistance(
        stops[i - 1].stopLat,
        stops[i - 1].stopLon,
        stops[i].stopLat,
        stops[i].stopLon,
      );
      result.add(
        result.last +
            (projected.length == stops.length
                ? math.max(direct, projected[i] - projected[i - 1])
                : direct),
      );
    }
    return result;
  }

  Journey _mergeAdjacentWalkingLegs(Journey journey) {
    final merged = <Leg>[];

    for (final leg in journey.legs) {
      if (merged.isNotEmpty && merged.last.isWalking && leg.isWalking) {
        final previous = merged.removeLast();
        merged.add(
          Leg(
            fromStopId: previous.fromStopId,
            toStopId: leg.toStopId,
            fromStopName: previous.fromStopName,
            toStopName: leg.toStopName,
            vehicleType: VehicleType.walk,
            distance: (previous.distance ?? 0) + (leg.distance ?? 0),
          ),
        );
      } else {
        merged.add(leg);
      }
    }

    return Journey(
      merged,
      originMainText: journey.originMainText,
      destinationMainText: journey.destinationMainText,
    );
  }
}
