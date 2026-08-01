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

  static List<Position> getSampleStopsCoordinates(TripsModel trip) {
    final stopTimes = getStopsAndStopTimes(trip);
    if (stopTimes.isEmpty) return [];

    if (stopTimes.length <= 100) {
      return stopTimes.map((st) => Position(st.stopLon, st.stopLat)).toList();
    }

    final List<StopsAndStopTimesModel> selectedStops = [];

    final first5Stops = stopTimes.take(5).toList();
    selectedStops.addAll(first5Stops);

    final last5Stops = stopTimes.skip(stopTimes.length - 5).toList();
    selectedStops.addAll(last5Stops);

    final int minSeq = first5Stops.last.stopSequence;
    final int maxSeq = last5Stops.first.stopSequence;
    final int totalRange = maxSeq - minSeq;

    final double step = totalRange / 91.0;

    StopsAndStopTimesModel getClosestStop(int targetSeq) {
      return stopTimes.reduce((a, b) {
        final aDiff = (a.stopSequence - targetSeq).abs();
        final bDiff = (b.stopSequence - targetSeq).abs();
        return aDiff <= bDiff ? a : b;
      });
    }

    for (int i = 1; i <= 90; i++) {
      final int targetSeq = (minSeq + (i * step)).round();
      selectedStops.add(getClosestStop(targetSeq));
    }

    return selectedStops.map((st) => Position(st.stopLon, st.stopLat)).toList();
  }

  static List<Position> getShapesPoints(TripsModel trip) {
    if (trip.shapes == null || trip.shapes!.isEmpty) {
      return [];
    }

    final sortedShapes = List<ShapesModel>.from(trip.shapes!)
      ..sort((a, b) => a.shapePtSequence.compareTo(b.shapePtSequence));

    return sortedShapes
        .map((shape) => Position(shape.shapePtLon, shape.shapePtLat))
        .toList();
  }

  static Future<void> drawTripPolylineOnMap(
    MapboxMap map,
    TripsModel trip,
  ) async {
    final coordinates = getSampleStopsCoordinates(trip);
    if (coordinates.isEmpty) return;

    final String formattedCoords = coordinates
        .map((pos) => '${pos.lng},${pos.lat}')
        .join(';');

    final String radiusesParam = List.filled(
      coordinates.length,
      '25',
    ).join(';');

    final String? accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('Error: MAPBOX_ACCESS_TOKEN is missing or null.');
      return;
    }

    final Uri uri = Uri.parse(
      'https://api.mapbox.com/matching/v5/mapbox/driving/$formattedCoords'
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
          'Mapbox Map Matching API Failed (${response.statusCode}): ${response.body}',
        );
        return;
      }

      final data = json.decode(response.body);
      final matchings = data['matchings'] as List?;
      if (matchings == null || matchings.isEmpty) return;

      final linePositions = matchings
          .expand((match) => match['geometry']['coordinates'] as List)
          .map((c) => Position(c[0] as double, c[1] as double))
          .toList();

      if (linePositions.isEmpty) return;

      await _drawPolylineAndFitCamera(map, linePositions);
    } catch (e) {
      debugPrint('Error requesting map matching polyline: $e');
    }
  }

  static Future<void> drawTripShapePolylineOnMap(
    MapboxMap map,
    TripsModel trip,
  ) async {
    final shapePositions = getShapesPoints(trip);

    if (shapePositions.isEmpty) {
      debugPrint(
        'No shapes found for train trip, falling back to stop coordinates.',
      );
      final stopTimes = getStopsAndStopTimes(trip);
      shapePositions.addAll(
        stopTimes.map((st) => Position(st.stopLon, st.stopLat)),
      );
    }

    if (shapePositions.isEmpty) return;

    await _drawPolylineAndFitCamera(map, shapePositions);
  }

  static Future<void> _drawPolylineAndFitCamera(
    MapboxMap map,
    List<Position> positions,
  ) async {
    final style = map.style;

    if (await style.styleLayerExists('route-line-layer')) {
      await style.removeStyleLayer('route-line-layer');
    }
    if (await style.styleSourceExists('route-line-source')) {
      await style.removeStyleSource('route-line-source');
    }

    await style.addSource(
      GeoJsonSource(
        id: 'route-line-source',
        data: jsonEncode({
          "type": "Feature",
          "properties": {},
          "geometry": {
            "type": "LineString",
            "coordinates": positions.map((p) => [p.lng, p.lat]).toList(),
          },
        }),
      ),
    );

    await style.addLayer(
      LineLayer(
        id: 'route-line-layer',
        sourceId: 'route-line-source',
        lineColor: 0xFF1976D2,
        lineWidth: 5.0,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
      ),
    );

    final List<Point> points = positions
        .map((pos) => Point(coordinates: pos))
        .toList();

    final cameraOptions = await map.cameraForCoordinatesPadding(
      points,
      CameraOptions(),
      MbxEdgeInsets(top: 50.0, left: 50.0, bottom: 250.0, right: 50.0),
      null,
      null,
    );

    await map.easeTo(
      cameraOptions,
      MapAnimationOptions(duration: 1000),
    );
  }
}
