import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/raptor_pathfinding_service.dart';

class RouteMetadataResult {
  final List<Position> coordinates;
  final double distanceMeters;
  final double? durationSeconds;
  final List<String?>? traffic;
  final List<NavigationStep>? steps;

  const RouteMetadataResult({
    required this.coordinates,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.traffic,
    this.steps,
  });
}

class MapMatchingService {
  static const int _matrixDestinationsPerRequest = 24;

  /// Returns pedestrian-network distances between [anchor] and each keyed
  /// point. Set [pointsToAnchor] for point-to-anchor routing.
  /// Mapbox's walking matrix accepts at most 25 coordinates, so larger sets
  /// are split into batches containing one start and up to 24 destinations.
  static Future<Map<String, double>> fetchWalkingDistances(
    Position anchor,
    Map<String, Position> destinations, {
    bool pointsToAnchor = false,
  }) async {
    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
    if (accessToken == null || accessToken.isEmpty || destinations.isEmpty) {
      return {};
    }

    final entries = destinations.entries.toList();
    final resolved = <String, double>{};

    // The Matrix API rejects a one-origin/one-destination request because it
    // produces only one matrix element. Use Directions for the genuinely
    // single-destination case.
    if (entries.length == 1) {
      final entry = entries.single;
      final start = pointsToAnchor ? entry.value : anchor;
      final end = pointsToAnchor ? anchor : entry.value;
      final metadata = await fetchWalkingDirections(start, end);
      if (metadata != null) {
        resolved[entry.key] = metadata.distanceMeters;
      }
      return resolved;
    }

    var offset = 0;
    while (offset < entries.length) {
      final remaining = entries.length - offset;
      // Avoid leaving a final singleton batch (for example 25 -> 23 + 2).
      final batchSize = remaining == _matrixDestinationsPerRequest + 1
          ? _matrixDestinationsPerRequest - 1
          : math.min(_matrixDestinationsPerRequest, remaining);
      final end = offset + batchSize;
      final batch = entries.sublist(offset, end);
      // Advance before any error/empty-response continue in this batch.
      offset = end;
      final coordinates = <Position>[
        anchor,
        ...batch.map((entry) => entry.value),
      ];
      final formattedCoordinates = coordinates
          .map((position) => '${position.lng},${position.lat}')
          .join(';');
      final destinationIndexes = List.generate(
        batch.length,
        (index) => index + 1,
      ).join(';');
      final sources = pointsToAnchor ? destinationIndexes : '0';
      final destinationQuery = pointsToAnchor ? '0' : destinationIndexes;
      final uri = Uri.parse(
        'https://api.mapbox.com/directions-matrix/v1/mapbox/walking/'
        '$formattedCoordinates'
        '?sources=$sources'
        '&destinations=$destinationQuery'
        '&annotations=distance'
        '&access_token=$accessToken',
      );

      try {
        final response = await http.get(uri);
        if (response.statusCode != 200) {
          continue;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rows = data['distances'] as List?;
        if (rows == null || rows.isEmpty) continue;

        for (var index = 0; index < batch.length; index++) {
          final row = pointsToAnchor
              ? (index < rows.length ? rows[index] as List? : null)
              : rows.first as List?;
          final value = pointsToAnchor
              ? (row?.isNotEmpty == true ? row!.first : null)
              : (index < (row?.length ?? 0) ? row![index] : null);
          if (value is num) {
            resolved[batch[index].key] = value.toDouble();
          } else {
            resolved[batch[index].key] = double.infinity;
          }
        }
      } on Exception {
        // Walking distances are optional; callers use geographic estimates.
      }
    }

    return resolved;
  }

  static Future<RouteMetadataResult?> fetchWalkingDirections(
    Position start,
    Position end,
  ) async {
    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
    if (accessToken == null || accessToken.isEmpty) return null;
    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/walking/'
      '${start.lng},${start.lat};${end.lng},${end.lat}'
      '?steps=true'
      '&geometries=geojson'
      '&overview=full'
      '&annotations=distance,duration'
      '&access_token=$accessToken',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List? ?? const [];
      if (routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final geometryCoordinates = geometry?['coordinates'] as List? ?? const [];
      final coordinates = geometryCoordinates
          .map(
            (coordinate) => Position(
              (coordinate[0] as num).toDouble(),
              (coordinate[1] as num).toDouble(),
            ),
          )
          .toList();
      final steps = <NavigationStep>[];
      for (final leg in route['legs'] as List? ?? const []) {
        for (final step
            in (leg as Map<String, dynamic>)['steps'] as List? ?? const []) {
          final stepData = step as Map<String, dynamic>;
          final maneuver = stepData['maneuver'] as Map<String, dynamic>?;
          final instruction = maneuver?['instruction'] as String?;
          if (instruction == null || instruction.isEmpty) continue;
          steps.add(
            NavigationStep(
              instruction: instruction,
              distanceMeters: (stepData['distance'] as num?)?.toDouble(),
              durationSeconds: (stepData['duration'] as num?)?.toDouble(),
            ),
          );
        }
      }

      final distanceMeters = (route['distance'] as num?)?.toDouble() ?? 0;
      final durationSeconds = (route['duration'] as num?)?.toDouble() ?? 0;
      return RouteMetadataResult(
        coordinates: coordinates,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        traffic: null,
        steps: steps.isEmpty ? null : steps,
      );
    } on Exception {
      // Walking directions are optional; callers can use route estimates.
      return null;
    }
  }

  static Future<RouteMetadataResult?> fetchMapMatching(
    String profile,
    List<Position> coordinates,
  ) async {
    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
    if (accessToken == null || accessToken.isEmpty || coordinates.length < 2) {
      return null;
    }

    final formattedCoordinates = coordinates
        .map((position) => '${position.lng},${position.lat}')
        .join(';');

    final radiuses = List.filled(coordinates.length, '25').join(';');
    final annotations = profile == 'driving-traffic'
        ? 'distance,duration,congestion'
        : 'distance,duration';

    final uri = Uri.parse(
      'https://api.mapbox.com/matching/v5/mapbox/$profile/'
      '$formattedCoordinates'
      '?steps=true'
      '&radiuses=$radiuses'
      '&annotations=$annotations'
      '&geometries=geojson'
      '&overview=full'
      '&tidy=true'
      '&access_token=$accessToken',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final matchings = data['matchings'] as List? ?? const [];
      if (matchings.isEmpty) return null;

      final distances = <double>[];
      final durationsInSeconds = <double>[];
      final congestionValues = <String?>[];
      final matchedCoordinates = <Position>[];
      final navigationSteps = <NavigationStep>[];

      for (
        var matchingIndex = 0;
        matchingIndex < matchings.length;
        matchingIndex++
      ) {
        final matching = matchings[matchingIndex] as Map<String, dynamic>;
        final legs = matching['legs'] as List? ?? const [];
        final geometry = matching['geometry'] as Map<String, dynamic>?;
        final geometryCoordinates =
            geometry?['coordinates'] as List? ?? const [];
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
          final steps = leg['steps'] as List? ?? const [];
          for (final step in steps) {
            final stepData = step as Map<String, dynamic>;
            final maneuver = stepData['maneuver'] as Map<String, dynamic>?;
            final instruction = maneuver?['instruction'] as String?;
            if (instruction == null || instruction.isEmpty) continue;
            navigationSteps.add(
              NavigationStep(
                instruction: instruction,
                distanceMeters: (stepData['distance'] as num?)?.toDouble(),
                durationSeconds: (stepData['duration'] as num?)?.toDouble(),
              ),
            );
          }
        }
      }

      final totalDistance = distances.fold(0.0, (sum, value) => sum + value);
      final totalDurationInSeconds = durationsInSeconds.fold(
        0.0,
        (sum, value) => sum + value,
      );

      return RouteMetadataResult(
        coordinates: matchedCoordinates,
        distanceMeters: totalDistance,
        durationSeconds: totalDurationInSeconds,
        traffic: congestionValues.isEmpty ? null : congestionValues,
        steps: navigationSteps.isEmpty ? null : navigationSteps,
      );
    } on Exception {
      // Map matching is optional; callers retain the unsnapped route geometry.
      return null;
    }
  }

  static Future<RouteMetadataResult> fetchRouteMetadataResultTrain(
    VehicleType vehicleType,
    List<Position> shapeCoordinates, {
    String? routeId,
  }) async {
    var distanceMeters = 0.0;
    for (var index = 1; index < shapeCoordinates.length; index++) {
      distanceMeters += _straightLineDistanceMeters(
        shapeCoordinates[index - 1],
        shapeCoordinates[index],
      );
    }

    const speedsKmh = <String, double>{
      'ROUTE_880747': 40.0,
      'ROUTE_880801': 40.0,
      'ROUTE_880854': 35.0,
    };
    final speedKmh = speedsKmh[routeId] ?? 35.0;
    final durationSeconds = distanceMeters / 1000 / speedKmh * 3600;

    return RouteMetadataResult(
      coordinates: shapeCoordinates,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      traffic: null,
    );
  }

  // exclusively for trains, computes distance based on shapes pts
  static double _straightLineDistanceMeters(Position first, Position second) {
    const metersPerLatitudeDegree = 110540.0;
    const metersPerLongitudeDegreeAtEquator = 111320.0;

    final averageLatitudeRadians =
        ((first.lat.toDouble() + second.lat.toDouble()) / 2) * math.pi / 180;
    final deltaX =
        (second.lng.toDouble() - first.lng.toDouble()) *
        metersPerLongitudeDegreeAtEquator *
        math.cos(averageLatitudeRadians);
    final deltaY =
        (second.lat.toDouble() - first.lat.toDouble()) *
        metersPerLatitudeDegree;

    return math.sqrt(deltaX * deltaX + deltaY * deltaY);
  }

  // Use List<Position> on RouteMetadataResult.coordinates to snap polylines to roads
  static Future<void> drawPolyline(
    MapboxMap map,
    List<Position> positions, {
    String sourceId = 'map-matching-route-source',
    String layerId = 'map-matching-route-layer',
    bool dotted = false,
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
        lineColor: 0xFF0081FB,
        lineWidth: 5.0,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
        lineDasharray: dotted ? [0.5, 1.5] : null,
      ),
    );
  }
}
