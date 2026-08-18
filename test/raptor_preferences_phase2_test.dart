import 'package:flutter_test/flutter_test.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/profile_store.dart';
import 'package:para_v3/services/raptor_pathfinding_service.dart';

const _lat = 14.6;
const _originLng = 121.0;
const _destinationLng = 121.03;

RoutesModel _route(
  String id,
  VehicleType type,
  List<(String, double)> stops,
) {
  final tripId = '$id-trip';
  return RoutesModel(
    routeId: id,
    routeLongName: id,
    vehicleType: type,
    trips: [
      TripsModel(
        tripId: tripId,
        routeId: id,
        stopTimes: [
          for (var index = 0; index < stops.length; index++)
            StopsAndStopTimesModel(
              tripId: tripId,
              stopSequence: index,
              stopId: stops[index].$1,
              stopName: stops[index].$1,
              stopLat: _lat,
              stopLon: stops[index].$2,
            ),
        ],
      ),
    ],
  );
}

RaptorRoutingOptions _options(
  RoutePriority priority,
  Set<TransportMode> modes, {
  int walking = 400,
}) => RaptorRoutingOptions(
  priority: priority,
  maxWalkingDistance: walking,
  enabledModes: modes,
);

List<Journey> _find(RaptorRoutingOptions options) =>
    RaptorPathfindingService.instance.findJourneys(
      originLat: _lat,
      originLng: _originLng,
      destLat: _lat,
      destLng: _destinationLng,
      options: options,
    );

void main() {
  final network = GtfsNetworkService.instance;

  setUp(() {
    network
      ..routesMap.clear()
      ..isLoaded = true;
  });

  tearDown(() {
    network
      ..routesMap.clear()
      ..isLoaded = false;
  });

  test('disabled transit modes never appear and route IDs stay stable', () {
    network.routesMap.addAll({
      'bus-route': _route('bus-route', VehicleType.bus, [
        ('b0', _originLng),
        ('bd', _destinationLng),
      ]),
      'train-route': _route('train-route', VehicleType.train, [
        ('t0', _originLng),
        ('td', _destinationLng),
      ]),
    });

    final journeys = _find(
      _options(RoutePriority.fastest, {TransportMode.train}),
    );
    expect(journeys, isNotEmpty);
    final transit = journeys
        .expand((journey) => journey.legs)
        .where(
          (leg) => !leg.isWalking,
        );
    expect(transit, isNotEmpty);
    expect(
      transit.every((leg) => leg.vehicleType == VehicleType.train),
      isTrue,
    );
    expect(transit.every((leg) => leg.routeId == 'train-route'), isTrue);
    expect(transit.every((leg) => !leg.routeId!.contains('_p')), isTrue);
  });

  test('walking stays available independently of transit modes', () {
    final journeys = RaptorPathfindingService.instance.findJourneys(
      originLat: _lat,
      originLng: _originLng,
      destLat: _lat,
      destLng: _originLng + 0.001,
      options: _options(RoutePriority.fastest, const {}),
    );
    expect(journeys, hasLength(1));
    expect(journeys.single.legs.single.vehicleType, VehicleType.walk);
    expect(journeys.single.legs.single.distance!, lessThanOrEqualTo(400.1));
  });

  test('direct walking remains available while transit data loads', () {
    network.isLoaded = false;
    final journeys = RaptorPathfindingService.instance.findJourneys(
      originLat: _lat,
      originLng: _originLng,
      destLat: _lat,
      destLng: _originLng + 0.001,
      options: _options(RoutePriority.fastest, const {}),
    );
    expect(journeys.single.legs.single.vehicleType, VehicleType.walk);
  });

  test('every access and destination walk obeys the hard limit', () {
    network.routesMap['train-route'] = _route(
      'train-route',
      VehicleType.train,
      [
        ('t0', _originLng + 0.001),
        ('td', _destinationLng - 0.001),
      ],
    );
    final journeys = _find(
      _options(RoutePriority.fastest, {TransportMode.train}),
    );
    expect(journeys, isNotEmpty);
    for (final leg in journeys.expand((journey) => journey.legs)) {
      if (leg.isWalking) {
        expect(leg.distance!, lessThanOrEqualTo(400.1));
      }
    }
  });

  test('over-limit direct and access walks produce no match', () {
    network.routesMap['train-route'] = _route(
      'train-route',
      VehicleType.train,
      [
        ('t0', _originLng + 0.003),
        ('td', _destinationLng),
      ],
    );
    expect(
      _find(_options(RoutePriority.fastest, {TransportMode.train})),
      isEmpty,
    );
    expect(_find(_options(RoutePriority.fastest, const {})), isEmpty);
  });

  test('priority biases candidates and ordering deterministically', () {
    network.routesMap.addAll({
      'bus-route': _route('bus-route', VehicleType.bus, [
        ('b0', _originLng),
        ('bd', _destinationLng),
      ]),
      'train-route': _route('train-route', VehicleType.train, [
        ('t0', _originLng + 0.001),
        ('td', _destinationLng),
      ]),
    });
    String firstRoute(RoutePriority priority) => _find(
      _options(priority, {TransportMode.bus, TransportMode.train}),
    ).first.legs.firstWhere((leg) => !leg.isWalking).routeId!;

    expect(firstRoute(RoutePriority.fastest), 'train-route');
    expect(firstRoute(RoutePriority.lessWalking), 'bus-route');
    final first = _find(
      _options(RoutePriority.fastest, {TransportMode.bus, TransportMode.train}),
    ).map((journey) => journey.signature).toList();
    final second = _find(
      _options(RoutePriority.fastest, {TransportMode.bus, TransportMode.train}),
    ).map((journey) => journey.signature).toList();
    expect(second, first);
  });

  test('transfer cap and fewer-transfers priority affect generation', () {
    network.routesMap.addAll({
      'bus': _route('bus', VehicleType.bus, [
        ('o', _originLng),
        ('west', _originLng - 0.03),
        ('d', _destinationLng),
      ]),
      'rail-a': _route('rail-a', VehicleType.train, [
        ('o', _originLng),
        ('x', 121.014),
      ]),
      'rail-b': _route('rail-b', VehicleType.train, [
        ('y', 121.0145),
        ('d', _destinationLng),
      ]),
    });

    Journey first(RoutePriority priority) => _find(
      _options(priority, {TransportMode.bus, TransportMode.train}),
    ).first;
    expect(first(RoutePriority.fastest).boardings, 2);
    expect(first(RoutePriority.fewerTransfers).boardings, 1);
    expect(
      first(
        RoutePriority.fewerTransfers,
      ).legs.firstWhere((leg) => !leg.isWalking).routeId,
      'bus',
    );
    expect(
      _find(
        _options(
          RoutePriority.fastest,
          {TransportMode.train},
          walking: 50,
        ),
      ),
      isEmpty,
    );
  });
}
