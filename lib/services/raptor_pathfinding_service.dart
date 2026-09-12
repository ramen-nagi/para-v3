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
  static const double transferPenalty = 500.0;

  final List<Leg> legs;
  final String? originMainText;
  final String? destinationMainText;

  Journey(
    this.legs, {
    this.originMainText,
    this.destinationMainText,
  });

  double get cost => legs.fold(0.0, (sum, leg) => sum + (leg.distance ?? 0.0));

  double get rankingCost {
    var score = 0.0;
    var boardings = 0;
    for (final leg in legs) {
      final distance = leg.distance ?? 0.0;
      if (leg.isWalking) {
        score += distance;
      } else {
        score += distance * transitDistanceWeight;
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
  static const double _walkCircuityFactor = 1.4; // Estimated walking distance.
  static const double _originSearchRadius =
      3000.0; // initial origin walk radius
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
  /// Walking-only is a fallback. Vehicle preferences break score ties only.
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

    // --- ALGORITHM START ---

    var previousRound = <String, List<_Label>>{};

    // --- Initial Walking Phase (Origin -> Stops) ---
    List<Transfer> originNearby = [];
    double currentOriginRadius = _originSearchRadius;

    // Expand radius until at least one stop is found, up to 5km
    while (originNearby.isEmpty && currentOriginRadius <= 5000.0) {
      final nearby = getNearbyStops(originLat, originLng, currentOriginRadius);
      originNearby = nearby
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
          .toList();

      if (originNearby.isEmpty) {
        currentOriginRadius += 500.0;
      }
    }

    originNearby.sort((a, b) => a.distance.compareTo(b.distance));

    const directDestinationKey = '__DIRECT_DESTINATION__';
    var originRoadDistances = <String, double>{};
    if (walkingDistanceResolver != null) {
      final endpointPositions = <String, Position>{
        for (final transfer in originNearby)
          transfer.toStopId: Position(
            allStops[transfer.toStopId]!.stopLon,
            allStops[transfer.toStopId]!.stopLat,
          ),
        directDestinationKey: Position(destLng, destLat),
      };
      try {
        originRoadDistances = await walkingDistanceResolver(
          Position(originLng, originLat),
          endpointPositions,
        );
      } catch (error) {
        debugPrint('Walking-distance lookup failed; using estimates: $error');
      }
    }

    for (final transfer in originNearby) {
      final distance =
          originRoadDistances[transfer.toStopId] ??
          transfer.distance * _walkCircuityFactor;
      if (!distance.isFinite || distance < 0 || distance > _maxWalkingRadius) {
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

    final directWalkDist =
        originRoadDistances[directDestinationKey] ??
        computeDistance(originLat, originLng, destLat, destLng) *
            _walkCircuityFactor;
    final candidates = <String, _Label>{};

    final destinationNearby =
        getNearbyStops(
            destLat,
            destLng,
            _maxWalkingRadius,
          ).map((stop) {
            return Transfer(
              toStopId: stop.stopId,
              distance: computeDistance(
                destLat,
                destLng,
                stop.stopLat,
                stop.stopLon,
              ),
            );
          }).toList()
          ..sort((a, b) => a.distance.compareTo(b.distance));

    var destinationRoadDistances = <String, double>{};
    if (walkingDistanceResolver != null && destinationNearby.isNotEmpty) {
      try {
        destinationRoadDistances = await walkingDistanceResolver(
          Position(destLng, destLat),
          {
            for (final transfer in destinationNearby)
              transfer.toStopId: Position(
                allStops[transfer.toStopId]!.stopLon,
                allStops[transfer.toStopId]!.stopLat,
              ),
          },
          pointsToAnchor: true,
        );
      } catch (error) {
        debugPrint('Destination walking-distance lookup failed: $error');
      }
    }

    // Weighted-distance RAPTOR: one round per vehicle boarded. Keep the
    // cheapest three distinct service sequences at each stop.
    for (
      var round = 1;
      round <= _maxRounds && previousRound.isNotEmpty;
      round++
    ) {
      final arrivals = <String, List<_Label>>{};
      for (final rr in allRoutes) {
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
                boarding.offset +
                    rr.cumulativeDistances[i] * Journey.transitDistanceWeight,
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
                  rr.cumulativeDistances[i] * Journey.transitDistanceWeight,
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
    if (ranked.isNotEmpty) {
      // Copy legs: enrichment mutates them, and labels can share prefixes.
      return ranked
          .take(_maxResults)
          .map(
            (label) => _mergeAdjacentWalkingLegs(
              Journey(
                label.legs.map((leg) => Leg.fromJson(leg.toJson())).toList(),
              ),
            ),
          )
          .toList();
    }
    if (!directWalkDist.isFinite || directWalkDist < 0) return [];
    return [
      Journey([
        Leg(
          fromStopId: '__ORIGIN__',
          toStopId: '__DESTINATION__',
          fromStopName: 'origin',
          toStopName: 'destination',
          vehicleType: VehicleType.walk,
          distance: directWalkDist,
        ),
      ]),
    ];
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
