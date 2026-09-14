import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/raptor_pathfinding_service.dart';

StopsAndStopTimesModel stop(
  String tripId,
  int sequence,
  String id,
  double lat,
  double lon,
) => StopsAndStopTimesModel(
  tripId: tripId,
  stopSequence: sequence,
  stopId: id,
  stopName: id,
  stopLat: lat,
  stopLon: lon,
);

RoutesModel route(String id, List<StopsAndStopTimesModel> stops) => RoutesModel(
  routeId: id,
  routeLongName: id,
  vehicleType: VehicleType.uvExpress,
  trips: [TripsModel(tripId: '${id}_trip', routeId: id, stopTimes: stops)],
);

void main() {
  final network = GtfsNetworkService.instance;
  final pathfinder = RaptorPathfindingService.instance;

  test('adds 120 seconds per kilometre to non-train transit duration', () {
    expect(
      Journey.adjustTransitDuration(
        vehicleType: VehicleType.bus,
        durationSeconds: 600,
        distanceMeters: 2500,
      ),
      900,
    );
  });

  test('does not adjust train duration', () {
    expect(
      Journey.adjustTransitDuration(
        vehicleType: VehicleType.train,
        durationSeconds: 600,
        distanceMeters: 2500,
      ),
      600,
    );
  });

  setUp(() {
    network.routesMap.clear();
    network.isLoaded = true;
  });

  tearDown(() {
    network.routesMap.clear();
    network.isLoaded = false;
  });

  test('disabled vehicle types add 10% to only their transit score', () {
    for (final type in [
      VehicleType.tricycle,
      VehicleType.train,
      VehicleType.jeep,
      VehicleType.ejeep,
      VehicleType.bus,
      VehicleType.uvExpress,
    ]) {
      Leg leg(VehicleType vehicle, double distance) => Leg(
        fromStopId: 'a',
        toStopId: 'b',
        fromStopName: 'a',
        toStopName: 'b',
        vehicleType: vehicle,
        distance: distance,
      );
      final journey = Journey([
        leg(VehicleType.walk, 200),
        leg(type, 1000),
        leg(VehicleType.walk, 100),
        leg(type, 500),
      ]);
      final transitScore = 1500 * (type == VehicleType.train ? 0.3 : 0.5);
      expect(
        journey.calculateRankingCost(penalizedVehicleTypes: {type}),
        closeTo(300 + 500 + transitScore * 1.1, 0.001),
      );
      expect(journey.rankingCost, closeTo(300 + 500 + transitScore, 0.001));
      expect(journey.cost, 1800);
    }
  });

  test(
    '10% vehicle penalty affects search and post-enrichment ranking',
    () async {
      network.routesMap['uv'] = route('uv', [
        stop('uv_trip', 1, 'start', 14.60, 121),
        stop('uv_trip', 2, 'end', 14.66, 121),
      ]);
      network.routesMap['bus'] = RoutesModel(
        routeId: 'bus',
        routeLongName: 'bus',
        vehicleType: VehicleType.bus,
        trips: [
          TripsModel(
            tripId: 'bus_trip',
            routeId: 'bus',
            stopTimes: [
              stop('bus_trip', 1, 'start', 14.60, 121),
              stop('bus_trip', 2, 'bend', 14.63, 121.006),
              stop('bus_trip', 3, 'end', 14.66, 121),
            ],
          ),
        ],
      );
      const penalized = {VehicleType.uvExpress};
      final journeys = await pathfinder.findJourneys(
        originLat: 14.60,
        originLng: 121,
        destLat: 14.66,
        destLng: 121,
        penalizedVehicleTypes: penalized,
        walkingDistanceResolver:
            (anchor, points, {pointsToAnchor = false}) async => {
              for (final id in points.keys)
                id: id == (pointsToAnchor ? 'end' : 'start')
                    ? 0
                    : double.infinity,
            },
      );
      expect(
        journeys.first.legs.firstWhere((leg) => !leg.isWalking).vehicleType,
        VehicleType.bus,
      );
      final uv = journeys.firstWhere(
        (j) => j.legs.any((l) => l.vehicleType == VehicleType.uvExpress),
      );
      expect(journeys.first.cost, greaterThan(uv.cost));
      expect(
        journeys.first.calculateRankingCost(penalizedVehicleTypes: penalized),
        lessThan(uv.calculateRankingCost(penalizedVehicleTypes: penalized)),
      );
    },
  );

  test(
    'stronger train discount retains a farther station during expansion',
    () async {
      for (var i = 0; i < 3; i++) {
        network.routesMap['uv$i'] = route('uv$i', [
          stop('uv${i}_trip', 1, 'uv${i}_start', 14.60, 121),
          stop('uv${i}_trip', 2, 'uv${i}_end', 14.66, 121),
        ]);
      }
      network.routesMap['train'] = RoutesModel(
        routeId: 'train',
        routeLongName: 'train',
        vehicleType: VehicleType.train,
        trips: [
          TripsModel(
            tripId: 'train_trip',
            routeId: 'train',
            stopTimes: [
              stop('train_trip', 1, 'station', 14.61, 121),
              stop('train_trip', 2, 'terminal', 14.66, 121),
            ],
          ),
        ],
      );
      final journeys = await pathfinder.findJourneys(
        originLat: 14.60,
        originLng: 121,
        destLat: 14.66,
        destLng: 121,
        walkingDistanceResolver:
            (anchor, points, {pointsToAnchor = false}) async => {
              for (final entry in points.entries)
                entry.key: pathfinder.computeDistance(
                  anchor.lat.toDouble(),
                  anchor.lng.toDouble(),
                  entry.value.lat.toDouble(),
                  entry.value.lng.toDouble(),
                ),
            },
      );
      expect(journeys, hasLength(3));
      final winner = journeys.first;
      expect(
        winner.legs.firstWhere((leg) => !leg.isWalking).vehicleType,
        VehicleType.train,
      );
      final walking = winner.legs
          .where((leg) => leg.isWalking)
          .fold<double>(0, (sum, leg) => sum + leg.distance!);
      expect(
        winner.rankingCost,
        closeTo(walking + (winner.cost - walking) * 0.3, 0.001),
      );
      expect(winner.rankingCost, lessThan(journeys[1].rankingCost));
    },
  );

  test(
    'disconnected transit stops are excluded before walking lookups',
    () async {
      network.routesMap['origin_only'] = route('origin_only', [
        stop('origin_trip', 1, 'a', 14.59, 121),
        stop('origin_trip', 2, 'b', 14.60, 121),
      ]);
      network.routesMap['destination_only'] = route('destination_only', [
        stop('destination_trip', 1, 'c', 14.81, 121),
        stop('destination_trip', 2, 'd', 14.80, 121),
      ]);
      final calls = <Set<String>>[];
      await pathfinder.findJourneys(
        originLat: 14.60,
        originLng: 121,
        destLat: 14.80,
        destLng: 121,
        walkingDistanceResolver:
            (anchor, points, {pointsToAnchor = false}) async {
              calls.add(points.keys.toSet());
              return {};
            },
      );
      expect(calls, [
        {'__DIRECT_DESTINATION__'},
      ]);
    },
  );

  test(
    'bounds dense endpoint lookups, covers services and caches coordinates',
    () async {
      final dense = <StopsAndStopTimesModel>[
        for (var i = 0; i < 60; i++)
          stop('dense_trip', i + 1, 'dense_$i', 14.60 + i * 0.0001, 121),
        stop('dense_trip', 61, 'dense_end', 14.65, 121),
      ];
      network.routesMap['dense'] = route('dense', dense);
      for (var i = 0; i < 2; i++) {
        network.routesMap['other_$i'] = route('other_$i', [
          stop(
            'other_${i}_trip',
            1,
            'other_${i}_start',
            14.604 + i * 0.0001,
            121,
          ),
          stop('other_${i}_trip', 2, 'other_${i}_end', 14.65, 121),
        ]);
      }
      final calls = <Map<String, Position>>[];
      Future<Map<String, double>> resolver(
        Position anchor,
        Map<String, Position> points, {
        bool pointsToAnchor = false,
      }) async {
        calls.add(Map.of(points));
        expect(points.length, lessThanOrEqualTo(24));
        expect(points.containsKey('__DIRECT_DESTINATION__'), isFalse);
        expect(
          points.values.map((p) => '${p.lng},${p.lat}').toSet().length,
          points.length,
        );
        return {
          for (final entry in points.entries)
            entry.key:
                pathfinder.computeDistance(
                  anchor.lat.toDouble(),
                  anchor.lng.toDouble(),
                  entry.value.lat.toDouble(),
                  entry.value.lng.toDouble(),
                ) *
                1.4,
        };
      }

      Future<List<Journey>> search() => pathfinder.findJourneys(
        originLat: 14.60,
        originLng: 121,
        destLat: 14.65,
        destLng: 121,
        walkingDistanceResolver: resolver,
      );
      final journeys = await search();
      expect(journeys, hasLength(3));
      expect(calls.length, inInclusiveRange(2, 8));
      expect(calls.first.keys, containsAll(['other_0_start', 'other_1_start']));
      expect(calls.first.keys.any((id) => id.endsWith('_end')), isFalse);
      final beforeRepeat = calls.length;
      await search();
      expect(calls.length, beforeRepeat);
    },
  );

  test(
    'expands beyond 800 meters and defers direct walking until transit fails',
    () async {
      network.routesMap['r'] = route('r', [
        stop('r_trip', 1, 'start', 14.612, 121),
        stop('r_trip', 2, 'end', 14.65, 121),
      ]);
      final requests = <Set<String>>[];
      final journeys = await pathfinder.findJourneys(
        originLat: 14.60,
        originLng: 121,
        destLat: 14.65,
        destLng: 121,
        walkingDistanceResolver:
            (anchor, points, {pointsToAnchor = false}) async {
              requests.add(points.keys.toSet());
              return {for (final id in points.keys) id: double.infinity};
            },
      );
      expect(journeys, isEmpty);
      expect(requests.any((ids) => ids.contains('start')), isTrue);
      expect(requests.last, {'__DIRECT_DESTINATION__'});
      expect(requests.where((ids) => ids.contains('start')), hasLength(1));
    },
  );

  test(
    'long direct walk does not displace available transit journeys',
    () async {
      const originLat = 14.68754;
      const longitude = 121.02875;
      const destinationLat = 14.704426222882072;
      const destinationLng = 121.0367393421618;

      for (var index = 0; index < 3; index++) {
        final id = 'route_$index';
        final tripId = '${id}_trip';
        network.routesMap[id] = route(id, [
          stop(tripId, 1, '${id}_start', originLat + index * 0.0001, longitude),
          stop(
            tripId,
            2,
            '${id}_end',
            destinationLat - index * 0.0001,
            destinationLng,
          ),
        ]);
      }

      final journeys = await pathfinder.findJourneys(
        originLat: originLat,
        originLng: longitude,
        destLat: destinationLat,
        destLng: destinationLng,
      );

      expect(journeys, hasLength(3));
      expect(
        journeys.map((j) => j.rankingCost),
        orderedEquals(
          journeys.map((j) => j.rankingCost).toList()..sort(),
        ),
      );
      expect(
        journeys.every((journey) => journey.legs.any((leg) => !leg.isWalking)),
        isTrue,
      );
    },
  );

  test('walk under 500 meters suppresses out-of-the-way transit', () async {
    network.routesMap['detour'] = route('detour', [
      stop('detour_trip', 1, 'start', 14.61, 121),
      stop('detour_trip', 2, 'end', 14.59, 121),
    ]);

    final journeys = await pathfinder.findJourneys(
      originLat: 14.6000,
      originLng: 121,
      destLat: 14.6005,
      destLng: 121,
      walkingDistanceResolver:
          (anchor, destinations, {pointsToAnchor = false}) async => {
            for (final id in destinations.keys)
              id: id == '__DIRECT_DESTINATION__' ? 60 : 1000,
          },
    );

    expect(journeys.first.legs, hasLength(1));
    expect(journeys.first.legs.single.isWalking, isTrue);
    expect(journeys.first.cost, 60);
    expect(journeys, hasLength(1));
  });

  test('alights before a detour when that minimizes total distance', () async {
    const originLat = 14.60000;
    const destinationLat = 14.65400;
    const longitude = 121.00000;
    const tripId = 'detour_trip';

    network.routesMap['detour'] = route('detour', [
      stop(tripId, 1, 'start', originLat, longitude),
      stop(tripId, 2, 'far_exit', destinationLat - 0.0090, longitude),
      stop(tripId, 3, 'detour', destinationLat - 0.0090, longitude + 0.300),
      stop(tripId, 4, 'near_exit', destinationLat, longitude),
    ]);

    final journeys = await pathfinder.findJourneys(
      originLat: originLat,
      originLng: longitude,
      destLat: destinationLat,
      destLng: longitude,
    );

    final transitJourney = journeys.firstWhere(
      (journey) => journey.legs.any((leg) => !leg.isWalking),
    );
    final transitLeg = transitJourney.legs.firstWhere((leg) => !leg.isWalking);
    expect(transitLeg.toStopId, 'far_exit');
    expect(transitJourney.cost, lessThan(7000));
  });

  test('retains three services sharing the same stops', () async {
    for (var i = 0; i < 3; i++) {
      network.routesMap['r$i'] = route('r$i', [
        stop('r${i}_trip', 1, 'start', 14.68754, 121.02875),
        stop('r${i}_trip', 2, 'end', 14.704426222882072, 121.0367393421618),
      ]);
    }
    final journeys = await pathfinder.findJourneys(
      originLat: 14.68754,
      originLng: 121.02875,
      destLat: 14.704426222882072,
      destLng: 121.0367393421618,
    );
    expect(journeys, hasLength(3));
    expect(
      journeys
          .map((j) => j.legs.firstWhere((l) => !l.isWalking).routeId)
          .toSet(),
      {'r0', 'r1', 'r2'},
    );
  });

  test('does not pad one transit result with walking', () async {
    network.routesMap['r'] = route('r', [
      stop('r_trip', 1, 'start', 14.68754, 121.02875),
      stop('r_trip', 2, 'end', 14.704426222882072, 121.0367393421618),
    ]);
    final journeys = await pathfinder.findJourneys(
      originLat: 14.68754,
      originLng: 121.02875,
      destLat: 14.704426222882072,
      destLng: 121.0367393421618,
    );
    expect(journeys, hasLength(1));
    expect(journeys.single.legs.any((l) => !l.isWalking), isTrue);
  });

  test('preserves alternatives through a shared transfer route', () async {
    for (var i = 0; i < 3; i++) {
      network.routesMap['r$i'] = route('r$i', [
        stop('r${i}_trip', 1, 'start', 14.60, 121),
        stop('r${i}_trip', 2, 'hub', 14.66, 121),
      ]);
    }
    network.routesMap['last'] = route('last', [
      stop('last_trip', 1, 'hub', 14.66, 121),
      stop('last_trip', 2, 'end', 14.72, 121),
    ]);
    final journeys = await pathfinder.findJourneys(
      originLat: 14.60,
      originLng: 121,
      destLat: 14.72,
      destLng: 121,
    );
    expect(journeys, hasLength(3));
    for (final journey in journeys) {
      final rides = journey.legs.where((l) => !l.isWalking).toList();
      expect(rides, hasLength(2));
      expect(rides.last.routeId, 'last');
      expect(rides.first.toStopId, rides.last.fromStopId);
      expect(journey.legs.first.fromStopId, '__ORIGIN__');
      expect(journey.legs.last.toStopId, '__DESTINATION__');
    }
    final originalDistance = journeys[1].legs.last.distance;
    journeys[0].legs.last.distance = 12345;
    expect(journeys[1].legs.last.distance, originalDistance);
  });

  test('counts detours in GTFS geometry between sparse stops', () async {
    network.routesMap['r'] = RoutesModel(
      routeId: 'r',
      routeLongName: 'r',
      vehicleType: VehicleType.uvExpress,
      trips: [
        TripsModel(
          tripId: 'r_trip',
          routeId: 'r',
          shapeId: 'shape',
          stopTimes: [
            stop('r_trip', 1, 'start', 14.68754, 121.02875),
            stop('r_trip', 2, 'end', 14.704426222882072, 121.0367393421618),
          ],
          shapes: [
            ShapesModel(
              shapeId: 'shape',
              shapePtSequence: 1,
              shapePtLat: 14.68754,
              shapePtLon: 121.02875,
            ),
            ShapesModel(
              shapeId: 'shape',
              shapePtSequence: 2,
              shapePtLat: 14.69,
              shapePtLon: 121.10,
            ),
            ShapesModel(
              shapeId: 'shape',
              shapePtSequence: 3,
              shapePtLat: 14.704426222882072,
              shapePtLon: 121.0367393421618,
            ),
          ],
        ),
      ],
    );
    final journeys = await pathfinder.findJourneys(
      originLat: 14.68754,
      originLng: 121.02875,
      destLat: 14.704426222882072,
      destLng: 121.0367393421618,
    );
    final transitJourney = journeys.firstWhere(
      (journey) => journey.legs.any((leg) => !leg.isWalking),
    );
    expect(
      transitJourney.legs.firstWhere((leg) => !leg.isWalking).distance,
      greaterThan(10000),
    );
  });

  test('transit discount favors riding over a shorter walk to board', () async {
    network.routesMap['r'] = route('r', [
      stop('r_trip', 1, 'a', 14.60, 121),
      stop('r_trip', 2, 'b', 14.61, 121),
      stop('r_trip', 3, 'c', 14.62, 121),
    ]);
    final journeys = await pathfinder.findJourneys(
      originLat: 14.60,
      originLng: 121,
      destLat: 14.62,
      destLng: 121,
      walkingDistanceResolver:
          (anchor, destinations, {pointsToAnchor = false}) async =>
              pointsToAnchor
              ? {'a': 4000, 'b': 3000, 'c': 0}
              : {'a': 0, 'b': 700, 'c': 4000},
    );
    final journey = journeys.first;
    expect(journey.legs.firstWhere((l) => !l.isWalking).fromStopId, 'a');
    // First boarding has no penalty; the distance remains physical meters.
    expect(journey.rankingCost, closeTo(journey.cost * 0.5, 0.001));
  });

  test('transfer penalty favors a slightly longer one-seat journey', () async {
    network.routesMap['direct'] = route('direct', [
      stop('direct_trip', 1, 'start', 14.60, 121),
      stop('direct_trip', 2, 'bend', 14.63, 121.01),
      stop('direct_trip', 3, 'end', 14.66, 121),
    ]);
    network.routesMap['first'] = route('first', [
      stop('first_trip', 1, 'start', 14.60, 121),
      stop('first_trip', 2, 'hub', 14.63, 121),
    ]);
    network.routesMap['second'] = route('second', [
      stop('second_trip', 1, 'hub', 14.63, 121),
      stop('second_trip', 2, 'end', 14.66, 121),
    ]);
    final journeys = await pathfinder.findJourneys(
      originLat: 14.60,
      originLng: 121,
      destLat: 14.66,
      destLng: 121,
      walkingDistanceResolver:
          (anchor, destinations, {pointsToAnchor = false}) async => {
            for (final id in destinations.keys)
              id: id == (pointsToAnchor ? 'end' : 'start')
                  ? 0
                  : double.infinity,
          },
    );
    final direct = journeys.first;
    final transfer = journeys.firstWhere(
      (j) => j.legs.where((l) => !l.isWalking).length == 2,
    );
    expect(direct.legs.firstWhere((l) => !l.isWalking).routeId, 'direct');
    expect(direct.cost, greaterThan(transfer.cost));
    expect(direct.rankingCost, lessThan(transfer.rankingCost));
    expect(transfer.rankingCost, closeTo(transfer.cost * 0.5 + 500, 0.001));
    // Enrichment changes distance; the display ordering must use a fresh score.
    direct.legs.firstWhere((l) => !l.isWalking).distance = 20000;
    journeys.sort((a, b) => a.rankingCost.compareTo(b.rankingCost));
    expect(journeys.first, same(transfer));
  });

  test('uses direct walking when transit cannot be reached', () async {
    network.routesMap['remote'] = route('remote', [
      stop('remote_trip', 1, 'a', 15.5, 121),
      stop('remote_trip', 2, 'b', 15.6, 121),
    ]);
    final journeys = await pathfinder.findJourneys(
      originLat: 14.68754,
      originLng: 121.02875,
      destLat: 14.704426222882072,
      destLng: 121.0367393421618,
    );
    expect(journeys.single.legs.single.isWalking, isTrue);
  });

  test('compares boarding cost including distance already ridden', () async {
    network.routesMap['r'] = route('r', [
      stop('r_trip', 1, 'a', 14.68, 121),
      stop('r_trip', 2, 'b', 14.69, 121),
      stop('r_trip', 3, 'c', 14.70, 121),
    ]);
    final journeys = await pathfinder.findJourneys(
      originLat: 14.68,
      originLng: 121,
      destLat: 14.70,
      destLng: 121,
      walkingDistanceResolver:
          (anchor, destinations, {pointsToAnchor = false}) async =>
              pointsToAnchor
              ? {'a': 4000, 'b': 3000, 'c': 0}
              : {'a': 0, 'b': 100, 'c': 4000},
    );
    final ride = journeys.first.legs.firstWhere((l) => !l.isWalking);
    expect(ride.fromStopId, 'b');
    expect(ride.toStopId, 'c');
  });

  test('search radius covers stops more than one grid cell away', () async {
    network.routesMap['r'] = route('r', [
      stop('r_trip', 1, 'a', 14.625, 121),
      stop('r_trip', 2, 'b', 14.70, 121),
    ]);
    final journeys = await pathfinder.findJourneys(
      originLat: 14.60,
      originLng: 121,
      destLat: 14.70,
      destLng: 121,
    );
    expect(journeys.single.legs.any((l) => !l.isWalking), isTrue);
  });

  test('near exit wins when continuing adds unnecessary distance', () async {
    network.routesMap['r'] = route('r', [
      stop('r_trip', 1, 'start', 14.68754, 121.02875),
      stop('r_trip', 2, 'near', 14.704426222882072, 121.0367393421618),
      stop('r_trip', 3, 'far', 14.72, 121.04),
    ]);
    final journeys = await pathfinder.findJourneys(
      originLat: 14.68754,
      originLng: 121.02875,
      destLat: 14.704426222882072,
      destLng: 121.0367393421618,
    );
    expect(
      journeys.first.legs.firstWhere((l) => !l.isWalking).toStopId,
      'near',
    );
  });
}
