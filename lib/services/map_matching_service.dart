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

  static Position? getStopCoordinate(String stopId) {
    for (final route in GtfsNetworkService.instance.routesMap.values) {
      for (final trip in route.trips) {
        for (final stopTime in trip.stopTimes) {
          if (stopTime.stopId == stopId) {
            return Position(stopTime.stopLon, stopTime.stopLat);
          }
        }
      }
    }
    return null;
  }

  static Future<void> clearCommuteLegPolylines(MapboxMap map) async {
    final style = map.style;
    for (var index = 0; index < 20; index++) {
      final layerId = 'commute-leg-layer-$index';
      final sourceId = 'commute-leg-source-$index';
      if (await style.styleLayerExists(layerId)) {
        await style.removeStyleLayer(layerId);
      }
      if (await style.styleSourceExists(sourceId)) {
        await style.removeStyleSource(sourceId);
      }
    }
  }

  static Future<List<Position>> drawCommuteLegPolyline({
    required MapboxMap map,
    required List<Position> coordinates,
    required String profile,
    required int legIndex,
    VehicleType? vehicleType,
    String? tripId,
    String? fromStopName,
    String? toStopName,
  }) async {
    final sourceId = 'commute-leg-source-$legIndex';
    final layerId = 'commute-leg-layer-$legIndex';
    final trip = tripId == null ? null : _findTripById(tripId);

    if (vehicleType == VehicleType.train) {
      if (trip == null) {
        debugPrint('No GTFS trip found for the train leg.');
        return _drawCommuteFallback(
          map,
          coordinates,
          sourceId,
          layerId,
          profile,
        );
      }

      final shapePositions = _getClippedShapePositions(
        trip,
        fromStopName,
        toStopName,
      );
      if (shapePositions.isEmpty) {
        debugPrint('No shape geometry found for the train leg.');
        return _drawCommuteFallback(
          map,
          _getTripLegStopCoordinates(trip, fromStopName, toStopName),
          sourceId,
          layerId,
          profile,
        );
      }

      await _drawPolylineAndFitCamera(
        map,
        shapePositions,
        sourceId: sourceId,
        layerId: layerId,
        fitCamera: false,
      );
      return shapePositions;
    }

    var matchingCoordinates = coordinates;
    if (vehicleType != null && trip != null) {
      final transitCoordinates = _getTripLegStopCoordinates(
        trip,
        fromStopName,
        toStopName,
      );
      if (transitCoordinates.isNotEmpty) {
        matchingCoordinates = transitCoordinates;
      }
    }

    if (matchingCoordinates.length < 2) return [];

    final formattedCoords = matchingCoordinates
        .map((position) => '${position.lng},${position.lat}')
        .join(';');
    final radiusesParam = List.filled(matchingCoordinates.length, '50').join(';');
    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('MAPBOX_ACCESS_TOKEN is missing or null.');
      return _drawCommuteFallback(
        map,
        matchingCoordinates,
        sourceId,
        layerId,
        profile,
      );
    }

    final uri = Uri.parse(
      'https://api.mapbox.com/matching/v5/mapbox/$profile/$formattedCoords'
      '?radiuses=$radiusesParam'
      '&geometries=geojson'
      '&overview=full'
      '&access_token=$accessToken',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint(
          'Mapbox $profile matching failed (${response.statusCode}): ${response.body}',
        );
        return _drawCommuteFallback(
          map,
          matchingCoordinates,
          sourceId,
          layerId,
          profile,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final matchings = data['matchings'] as List?;
      if (matchings == null || matchings.isEmpty) {
        debugPrint(
          'Mapbox $profile matching returned no match: '
          '${data['code']} ${data['message'] ?? ''}',
        );
        return _drawCommuteFallback(
          map,
          matchingCoordinates,
          sourceId,
          layerId,
          profile,
        );
      }

      final linePositions = matchings
          .expand((matching) => matching['geometry']['coordinates'] as List)
          .map(
            (coordinate) => Position(
              (coordinate[0] as num).toDouble(),
              (coordinate[1] as num).toDouble(),
            ),
          )
          .toList();
      if (linePositions.isEmpty) return [];

      await _drawPolylineAndFitCamera(
        map,
        linePositions,
        sourceId: sourceId,
        layerId: layerId,
        lineDasharray: profile == 'walking'
            ? const <double?>[0.1, 2.0]
            : null,
        fitCamera: false,
      );
      return linePositions;
    } catch (e) {
      debugPrint('Error requesting commute leg polyline: $e');
      return _drawCommuteFallback(
        map,
        matchingCoordinates,
        sourceId,
        layerId,
        profile,
      );
    }
  }

  static Future<List<Position>> _drawCommuteFallback(
    MapboxMap map,
    List<Position> positions,
    String sourceId,
    String layerId,
    String profile,
  ) async {
    if (positions.length < 2) return [];
    await _drawPolylineAndFitCamera(
      map,
      positions,
      sourceId: sourceId,
      layerId: layerId,
      lineDasharray: profile == 'walking'
          ? const <double?>[0.1, 2.0]
          : null,
      fitCamera: false,
    );
    return positions;
  }

  static TripsModel? _findTripById(String tripId) {
    for (final route in GtfsNetworkService.instance.routesMap.values) {
      for (final trip in route.trips) {
        if (trip.tripId == tripId) return trip;
      }
    }
    return null;
  }

  static List<StopsAndStopTimesModel> _getTripLegStops(
    TripsModel trip,
    String? fromStopName,
    String? toStopName,
  ) {
    if (fromStopName == null || toStopName == null) return [];

    final stops = getStopsAndStopTimes(trip);
    final fromIndex = stops.indexWhere((stop) => stop.stopName == fromStopName);
    if (fromIndex == -1) return [];

    var toIndex = -1;
    for (var index = fromIndex + 1; index < stops.length; index++) {
      if (stops[index].stopName == toStopName) {
        toIndex = index;
        break;
      }
    }
    if (toIndex == -1) return [];
    return stops.sublist(fromIndex, toIndex + 1);
  }

  static List<Position> _getTripLegStopCoordinates(
    TripsModel trip,
    String? fromStopName,
    String? toStopName,
  ) {
    final positions = _getTripLegStops(trip, fromStopName, toStopName)
        .map((stop) => Position(stop.stopLon, stop.stopLat))
        .toList();
    if (positions.length <= 100) return positions;

    return List.generate(100, (index) {
      final sourceIndex = (index * (positions.length - 1) / 99).round();
      return positions[sourceIndex];
    });
  }

  static List<Position> _getClippedShapePositions(
    TripsModel trip,
    String? fromStopName,
    String? toStopName,
  ) {
    final shapePositions = getShapesPoints(trip);
    if (shapePositions.isEmpty) return [];

    final legStops = _getTripLegStops(trip, fromStopName, toStopName);
    if (legStops.length < 2) return [];
    final fromPosition = Position(legStops.first.stopLon, legStops.first.stopLat);
    final toPosition = Position(legStops.last.stopLon, legStops.last.stopLat);

    final fromIndex = _nearestPositionIndex(shapePositions, fromPosition);
    final toIndex = _nearestPositionIndex(shapePositions, toPosition);
    if (fromIndex <= toIndex) {
      return shapePositions.sublist(fromIndex, toIndex + 1);
    }
    return shapePositions.sublist(toIndex, fromIndex + 1).reversed.toList();
  }

  static int _nearestPositionIndex(
    List<Position> positions,
    Position target,
  ) {
    var nearestIndex = 0;
    var nearestDistance = double.infinity;

    for (var index = 0; index < positions.length; index++) {
      final latDifference =
          positions[index].lat.toDouble() - target.lat.toDouble();
      final lngDifference =
          positions[index].lng.toDouble() - target.lng.toDouble();
      final distance =
          latDifference * latDifference + lngDifference * lngDifference;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }
    return nearestIndex;
  }

  static Future<void> fitCameraToPositions(
    MapboxMap map,
    List<Position> positions,
  ) async {
    if (positions.isEmpty) return;
    await _fitCamera(map, positions);
  }

  static Future<void> _drawPolylineAndFitCamera(
    MapboxMap map,
    List<Position> positions, {
    String sourceId = 'route-line-source',
    String layerId = 'route-line-layer',
    List<double?>? lineDasharray,
    bool fitCamera = true,
  }) async {
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
        id: layerId,
        sourceId: sourceId,
        lineColor: 0xFF2196F3,
        lineWidth: 5.0,
        lineDasharray: lineDasharray,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
      ),
    );

    if (fitCamera) {
      await _fitCamera(map, positions);
    }
  }

  static Future<void> _fitCamera(
    MapboxMap map,
    List<Position> positions,
  ) async {
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
