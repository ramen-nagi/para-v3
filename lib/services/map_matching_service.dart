import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/gtfs_network_service.dart';

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

  static Future<List<Position>> fetchMapMatching({
    required String profile,
    required String tripId,
    String? startStop,
    String? endStop,
  }) async {
    final trip = _findTripById(tripId);
    if (trip == null) {
      debugPrint('No GTFS trip found for map matching: $tripId');
      return [];
    }

    final stops = _getTripStops(trip, startStop, endStop);
    final coordinates = _samplePositions(
      stops.map((stop) => Position(stop.stopLon, stop.stopLat)).toList(),
    );
    if (coordinates.length < 2) {
      debugPrint('At least two stops are required for map matching.');
      return [];
    }

    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('MAPBOX_ACCESS_TOKEN is missing or null.');
      return [];
    }

    final formattedCoords = coordinates
        .map((position) => '${position.lng},${position.lat}')
        .join(';');
    final radiusesParam = List.filled(coordinates.length, '25').join(';');
    final Uri uri = Uri.parse(
      'https://api.mapbox.com/matching/v5/mapbox/$profile/$formattedCoords'
      '?steps=true'
      '&radiuses=$radiusesParam'
      '&geometries=geojson'
      '&overview=full'
      '&tidy=true'
      '&access_token=$accessToken',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint(
          'Mapbox map matching failed (${response.statusCode}): ${response.body}',
        );
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final matchings = data['matchings'] as List?;
      if (matchings == null || matchings.isEmpty) return [];

      return matchings
          .expand((matching) => matching['geometry']['coordinates'] as List)
          .map(
            (coordinate) => Position(
              (coordinate[0] as num).toDouble(),
              (coordinate[1] as num).toDouble(),
            ),
          )
          .toList();
    } catch (error) {
      debugPrint('Error requesting map matching polyline: $error');
      return [];
    }
  }

  static Future<void> drawRoutePolyline(
    MapboxMap map,
    List<Position> positions,
  ) async {
    if (positions.length < 2) return;

    const sourceId = 'route-line-source';
    const layerId = 'route-line-layer';
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
        lineColor: 0xFF2196F3,
        lineWidth: 5.0,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
      ),
    );

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
    TripsModel trip,
  ) async {
    final shapes = List<ShapesModel>.from(trip.shapes ?? [])
      ..sort((a, b) => a.shapePtSequence.compareTo(b.shapePtSequence));

    final positions = shapes
        .map((shape) => Position(shape.shapePtLon, shape.shapePtLat))
        .toList();
    if (positions.length < 2) {
      debugPrint('No usable shape points found for trip ${trip.tripId}.');
      return;
    }

    await drawRoutePolyline(map, positions);
  }
}
