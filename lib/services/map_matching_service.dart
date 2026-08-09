import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class MapMatchingResult {
  final List<Position> coordinates;
  final double distanceMeters;
  final double durationSeconds;
  final List<String?> traffic;

  const MapMatchingResult({
    required this.coordinates,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.traffic,
  });
}

class MapMatchingService {
  static Future<MapMatchingResult?> fetchMapMatching(
    String profile,
    List<Position> coordinates,
  ) async {
    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];

    final formattedCoordinates = coordinates
        .map((position) => '${position.lng},${position.lat}')
        .join(';');

    final radiuses = List.filled(coordinates.length, '25').join(';');

    final uri = Uri.parse(
      'https://api.mapbox.com/matching/v5/mapbox/$profile/'
      '$formattedCoordinates'
      '?steps=true'
      '&radiuses=$radiuses'
      '&annotations=distance,duration,congestion'
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
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final matchings = data['matchings'] as List? ?? const [];
      debugPrint('Map Matching response code: ${data['code']}');
      if (matchings.isEmpty) {
        debugPrint('Map Matching returned no matchings: ${jsonEncode(data)}');
        return null;
      }

      final distances = <double>[];
      final durationsInSeconds = <double>[];
      final congestionValues = <String?>[];
      final matchedCoordinates = <Position>[];

      for (var matchingIndex = 0;
          matchingIndex < matchings.length;
          matchingIndex++) {
        final matching = matchings[matchingIndex] as Map<String, dynamic>;
        final legs = matching['legs'] as List? ?? const [];
        final geometry = matching['geometry'] as Map<String, dynamic>?;
        final geometryCoordinates = geometry?['coordinates'] as List? ?? const [];
        matchedCoordinates.addAll(
          geometryCoordinates.map(
            (coordinate) => Position(
              (coordinate[0] as num).toDouble(),
              (coordinate[1] as num).toDouble(),
            ),
          ),
        );

        for (var legIndex = 0; legIndex < legs.length; legIndex++) {
          final leg = legs[legIndex] as Map<String, dynamic>;
          final annotation = leg['annotation'] as Map<String, dynamic>?;
          final distanceMeters = (leg['distance'] as num?)?.toDouble();
          final durationSeconds = (leg['duration'] as num?)?.toDouble();
          final congestion = annotation?['congestion'];
          if (distanceMeters != null) distances.add(distanceMeters);
          if (durationSeconds != null) durationsInSeconds.add(durationSeconds);
          if (congestion is List) {
            congestionValues.addAll(
              congestion.map((value) => value is String ? value : null),
            );
          }

          debugPrint(
            'Match ${matchingIndex + 1}, leg ${legIndex + 1}: '
            'distance=${distanceMeters?.toStringAsFixed(2) ?? 'unknown'} m; '
            'duration=${durationSeconds?.toStringAsFixed(2) ?? 'unknown'} s; '
            'congestion=${jsonEncode(congestion ?? const [])}',
          );
        }
      }

      final totalDistance = distances.fold(0.0, (sum, value) => sum + value);
      final totalDurationInSeconds = durationsInSeconds.fold(
        0.0,
        (sum, value) => sum + value,
      );
      debugPrint(
        'Map Matching totals: '
        'distance=${totalDistance.toStringAsFixed(2)} m; '
        'duration=${totalDurationInSeconds.toStringAsFixed(2)} s',
      );

      return MapMatchingResult(
        coordinates: matchedCoordinates,
        distanceMeters: totalDistance,
        durationSeconds: totalDurationInSeconds,
        traffic: congestionValues,
      );
    } catch (error) {
      debugPrint('Error requesting Mapbox map matching: $error');
      return null;
    }
  }

  static Future<void> drawPolyline(
    MapboxMap map,
    List<Position> positions, {
    String sourceId = 'map-matching-route-source',
    String layerId = 'map-matching-route-layer',
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
        lineColor: 0xFF81D4FA,
        lineWidth: 5.0,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
      ),
    );
  }
}
