import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/gtfs_network_service.dart';

class MatchedRouteResult {
  final List<Position> positions;
  final double? distanceMeters;

  const MatchedRouteResult({
    required this.positions,
    required this.distanceMeters,
  });
}

class MapMatchingService {
  static List<StopsAndStopTimesModel> getStopsAndStopTimes(TripsModel trip) {
    if (trip.stopTimes.isEmpty) return [];
    return List<StopsAndStopTimesModel>.from(trip.stopTimes)
      ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
  }

  static TripsModel? _findTripById(String tripId) {
    for (final route in GtfsNetworkService.instance.routesMap.values) {
      for (final trip in route.trips) {
        if (trip.tripId == tripId) return trip;
      }
    }
    return null;
  }

  static TripsModel? getTripById(String tripId) => _findTripById(tripId);

  static List<StopsAndStopTimesModel> _getTripStops(
    TripsModel trip,
    String? fromStopName,
    String? toStopName,
  ) {
    final stops = getStopsAndStopTimes(trip);
    if (stops.isEmpty) return [];
    if (fromStopName == null && toStopName == null) return stops;
    if (fromStopName == null || toStopName == null) return [];

    final fromIndex = stops.indexWhere((stop) => stop.stopName == fromStopName);
    if (fromIndex == -1) return [];

    final toIndex = stops.indexWhere(
      (stop) => stop.stopName == toStopName,
      fromIndex + 1,
    );
    if (toIndex == -1) return [];

    return stops.sublist(fromIndex, toIndex + 1);
  }

  // Used for transit other than vehicleType.train to draw polylines, get distance etc...
  static Future<MatchedRouteResult?> fetchMapMatchingDriving({
    required String profile,
    required String tripId,
    String? startStop,
    String? endStop,
  }) async {
    final trip = _findTripById(tripId);
    if (trip == null) {
      debugPrint('No GTFS trip found for map matching: $tripId');
      return null;
    }

    final stops = _getTripStops(trip, startStop, endStop);
    final coordinates = _samplePositions(
      stops.map((stop) => Position(stop.stopLon, stop.stopLat)).toList(),
    );
    if (coordinates.length < 2) {
      debugPrint('At least two stops are required for map matching.');
      return null;
    }

    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('MAPBOX_ACCESS_TOKEN is missing or null.');
      return null;
    }

    final formattedCoords = coordinates
        .map((position) => '${position.lng},${position.lat}')
        .join(';');
    debugPrint(formattedCoords);
    final radiusesParam = List.filled(coordinates.length, '25').join(';');
    final Uri uri = Uri.parse(
      'https://api.mapbox.com/matching/v5/mapbox/driving-traffic/$formattedCoords'
      '?steps=true'
      '&annotations=distance,congestion_numeric'
      '&radiuses=$radiusesParam'
      '&geometries=geojson'
      '&overview=full'
      '&tidy=true'
      '&access_token=$accessToken',
    );

    try {
      final response = await http.get(uri);
      final formattedResponse = const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(response.body));
      debugPrint(
        'Mapbox driving map matching response:\n$formattedResponse',
        wrapWidth: 120,
      );
      if (response.statusCode != 200) {
        debugPrint(
          'Mapbox map matching failed (${response.statusCode}): ${response.body}',
        );
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final matchings = data['matchings'] as List?;
      if (matchings == null || matchings.isEmpty) return null;

      final positions = matchings
          .expand((matching) => matching['geometry']['coordinates'] as List)
          .map(
            (coordinate) => Position(
              (coordinate[0] as num).toDouble(),
              (coordinate[1] as num).toDouble(),
            ),
          )
          .toList();
      final distanceMeters = matchings.fold<double>(
        0,
        (total, matching) =>
            total + ((matching['distance'] as num?)?.toDouble() ?? 0),
      );
      return MatchedRouteResult(
        positions: positions,
        distanceMeters: distanceMeters,
      );
    } catch (error) {
      debugPrint('Error requesting map matching polyline: $error');
      return null;
    }
  }

  // Used for walking legs of a journey to get distance, polylines etc...
  static Future<MatchedRouteResult?> fetchMapMatchingWalking(
    Position start,
    Position end,
  ) async {
    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('MAPBOX_ACCESS_TOKEN is missing or null.');
      return null;
    }

    final Uri uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/walking/'
      '${start.lng},${start.lat};${end.lng},${end.lat}'
      '?geometries=geojson'
      '&overview=full'
      '&annotations=distance'
      '&steps=true'
      '&access_token=$accessToken',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint(
          'Mapbox walking directions failed (${response.statusCode}): ${response.body}',
        );
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final totalDistance = (route['distance'] as num?)?.toDouble();
      final coordinates = route['geometry']['coordinates'] as List;
      final positions = coordinates
          .map(
            (coordinate) => Position(
              (coordinate[0] as num).toDouble(),
              (coordinate[1] as num).toDouble(),
            ),
          )
          .toList();
      return MatchedRouteResult(
        positions: positions,
        distanceMeters: totalDistance,
      );
    } catch (error) {
      debugPrint('Error requesting walking route: $error');
      return null;
    }
  }

  static Future<void> drawRoutePolyline(
    MapboxMap map,
    List<Position> positions, {
    String sourceId = 'route-line-source',
    String layerId = 'route-line-layer',
    bool fitCamera = true,
    List<double?>? lineDasharray,
  }) async {
    if (positions.length < 2) return;

    final style = map.style;
    if (await style.styleLayerExists(layerId)) {
      await style.removeStyleLayer(layerId);
    }
    if (await style.styleSourceExists(sourceId)) {
      await style.removeStyleSource(sourceId);
    }

    await style.addSource(
      GeoJsonSource(
        id: sourceId,
        data: jsonEncode({
          'type': 'Feature',
          'properties': {},
          'geometry': {
            'type': 'LineString',
            'coordinates': positions
                .map((position) => [position.lng, position.lat])
                .toList(),
          },
        }),
      ),
    );
    await style.addLayer(
      LineLayer(
        id: layerId,
        sourceId: sourceId,
        lineColor: 0xFF53b3ff,
        lineWidth: 5.0,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
        lineDasharray: lineDasharray,
      ),
    );

    if (!fitCamera) return;

    final cameraOptions = await map.cameraForCoordinatesPadding(
      positions.map((position) => Point(coordinates: position)).toList(),
      CameraOptions(),
      MbxEdgeInsets(top: 50.0, left: 50.0, bottom: 300.0, right: 50.0),
      null,
      null,
    );
    await map.easeTo(
      cameraOptions,
      MapAnimationOptions(duration: 1000),
    );
  }

  static Future<void> drawWalkPolyline(
    MapboxMap map,
    List<Position> positions, {
    String sourceId = 'walk-line-source',
    String layerId = 'walk-line-layer',
    bool fitCamera = false,
  }) {
    return drawRoutePolyline(
      map,
      positions,
      sourceId: sourceId,
      layerId: layerId,
      fitCamera: fitCamera,
      lineDasharray: const <double?>[0.1, 2.0],
    );
  }

  static List<Position> _samplePositions(List<Position> positions) {
    const maxMapMatchingCoordinates = 100;
    if (positions.length <= maxMapMatchingCoordinates) return positions;

    return List.generate(maxMapMatchingCoordinates, (index) {
      final sourceIndex =
          (index * (positions.length - 1) / (maxMapMatchingCoordinates - 1))
              .round();
      return positions[sourceIndex];
    });
  }

  static Future<void> drawShapePolyline(
    MapboxMap map,
    TripsModel trip, {
    String? startStop,
    String? endStop,
    String sourceId = 'route-line-source',
    String layerId = 'route-line-layer',
    bool fitCamera = true,
  }) async {
    final shapes = List<ShapesModel>.from(trip.shapes ?? [])
      ..sort((a, b) => a.shapePtSequence.compareTo(b.shapePtSequence));

    var positions = shapes
        .map((shape) => Position(shape.shapePtLon, shape.shapePtLat))
        .toList();
    final legStops = _getTripStops(trip, startStop, endStop);
    if (startStop != null && endStop != null && legStops.length >= 2) {
      final startPosition = Position(legStops.first.stopLon, legStops.first.stopLat);
      final endPosition = Position(legStops.last.stopLon, legStops.last.stopLat);
      final startIndex = _nearestPositionIndex(positions, startPosition);
      final endIndex = _nearestPositionIndex(positions, endPosition);
      positions = startIndex <= endIndex
          ? positions.sublist(startIndex, endIndex + 1)
          : positions.sublist(endIndex, startIndex + 1).reversed.toList();
    }
    if (positions.length < 2) {
      debugPrint('No usable shape points found for trip ${trip.tripId}.');
      return;
    }

    await drawRoutePolyline(
      map,
      positions,
      sourceId: sourceId,
      layerId: layerId,
      fitCamera: fitCamera,
    );
  }

  static int _nearestPositionIndex(
    List<Position> positions,
    Position target,
  ) {
    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var index = 0; index < positions.length; index++) {
      final latitudeDifference =
          positions[index].lat.toDouble() - target.lat.toDouble();
      final longitudeDifference =
          positions[index].lng.toDouble() - target.lng.toDouble();
      final distance = latitudeDifference * latitudeDifference +
          longitudeDifference * longitudeDifference;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }
    return nearestIndex;
  }
}
