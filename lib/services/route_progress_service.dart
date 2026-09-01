import 'dart:math' as math;

import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class RouteProgressResult {
  final List<Position> remainingCoordinates;
  final double distanceFromRouteMeters;
  final double traveledMeters;
  final double remainingMeters;

  const RouteProgressResult({
    required this.remainingCoordinates,
    required this.distanceFromRouteMeters,
    required this.traveledMeters,
    required this.remainingMeters,
  });
}

class RouteProgressService {
  static RouteProgressResult? calculate(
    Position currentPosition,
    List<Position> route,
  ) {
    if (route.length < 2) return null;

    final cumulativeDistances = <double>[0];
    for (var index = 1; index < route.length; index++) {
      cumulativeDistances.add(
        cumulativeDistances.last + _distance(route[index - 1], route[index]),
      );
    }

    var nearestSegment = 0;
    var nearestFraction = 0.0;
    var nearestDistance = double.infinity;
    for (var index = 0; index < route.length - 1; index++) {
      final fraction = _projectionFraction(
        currentPosition,
        route[index],
        route[index + 1],
      );
      final projected = _interpolate(
        route[index],
        route[index + 1],
        fraction,
      );
      final distanceFromRoute = _distance(currentPosition, projected);
      if (distanceFromRoute < nearestDistance) {
        nearestSegment = index;
        nearestFraction = fraction;
        nearestDistance = distanceFromRoute;
      }
    }

    final segmentStart = route[nearestSegment];
    final segmentEnd = route[nearestSegment + 1];
    final projected = _interpolate(
      segmentStart,
      segmentEnd,
      nearestFraction,
    );
    final traveled =
        cumulativeDistances[nearestSegment] +
        _distance(segmentStart, segmentEnd) * nearestFraction;
    final remaining = cumulativeDistances.last - traveled;

    return RouteProgressResult(
      remainingCoordinates: [
        projected,
        ...route.skip(nearestSegment + 1),
      ],
      distanceFromRouteMeters: nearestDistance,
      traveledMeters: traveled,
      remainingMeters: remaining,
    );
  }

  static double _distance(Position first, Position second) =>
      geo.Geolocator.distanceBetween(
        first.lat.toDouble(),
        first.lng.toDouble(),
        second.lat.toDouble(),
        second.lng.toDouble(),
      );

  static double _projectionFraction(
    Position current,
    Position start,
    Position end,
  ) {
    final latitudeScale = 111320.0;
    final longitudeScale =
        latitudeScale * math.cos(current.lat.toDouble() * math.pi / 180);
    final startX =
        (start.lng.toDouble() - current.lng.toDouble()) * longitudeScale;
    final startY =
        (start.lat.toDouble() - current.lat.toDouble()) * latitudeScale;
    final endX = (end.lng.toDouble() - current.lng.toDouble()) * longitudeScale;
    final endY = (end.lat.toDouble() - current.lat.toDouble()) * latitudeScale;
    final differenceX = endX - startX;
    final differenceY = endY - startY;
    final lengthSquared = differenceX * differenceX + differenceY * differenceY;
    if (lengthSquared == 0) return 0;
    return (-(startX * differenceX + startY * differenceY) / lengthSquared)
        .clamp(0.0, 1.0);
  }

  static Position _interpolate(Position start, Position end, double fraction) {
    return Position(
      start.lng.toDouble() +
          (end.lng.toDouble() - start.lng.toDouble()) * fraction,
      start.lat.toDouble() +
          (end.lat.toDouble() - start.lat.toDouble()) * fraction,
    );
  }
}
