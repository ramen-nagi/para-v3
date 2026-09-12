import 'package:flutter_test/flutter_test.dart';
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

  setUp(() {
    network.routesMap.clear();
    network.isLoaded = true;
  });

  tearDown(() {
    network.routesMap.clear();
    network.isLoaded = false;
  });

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
    expect(
      journeys.single.legs.firstWhere((l) => !l.isWalking).distance,
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
