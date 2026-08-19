import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/drag_scroll_sheet.dart';
import 'package:para_v3/module/universal_map_tile.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/mapbox_services.dart';

class RoutesPageMap extends StatefulWidget {
  final RoutesModel route;

  const RoutesPageMap({
    super.key,
    required this.route,
  });

  @override
  State<RoutesPageMap> createState() => _RoutesPageMapState();
}

class _RoutesPageMapState extends State<RoutesPageMap> {
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _stopAnnotationManager;

  List<Position> _getStopTimesStopsCoord(String tripId) {
    final trip = widget.route.trips.where((trip) => trip.tripId == tripId);
    if (trip.isEmpty) return [];

    final stopTimes = List<StopsAndStopTimesModel>.from(
      trip.first.stopTimes,
    )..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));

    return stopTimes
        .map((stopTime) => Position(stopTime.stopLon, stopTime.stopLat))
        .toList();
  }

  List<Position> _getShapeCoordinates(TripsModel trip) {
    final shapes = List<ShapesModel>.from(trip.shapes ?? [])
      ..sort((a, b) => a.shapePtSequence.compareTo(b.shapePtSequence));

    return shapes
        .map((shape) => Position(shape.shapePtLon, shape.shapePtLat))
        .toList();
  }

  Future<void> _drawRouteStops(String tripId) async {
    final map = _mapboxMap;
    if (map == null) return;

    final positions = _getStopTimesStopsCoord(tripId);
    final manager = _stopAnnotationManager ??= await map.annotations
        .createCircleAnnotationManager(id: 'route-stop-markers');
    await manager.deleteAll();
    if (positions.isEmpty) return;

    await manager.createMulti(
      positions
          .map(
            (position) => CircleAnnotationOptions(
              geometry: Point(coordinates: position),
              circleColor: 0xFF1976D2,
              circleRadius: 4,
              circleStrokeColor: 0xFFFFFFFF,
              circleStrokeWidth: 1.5,
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.route.routeLongName),
      ),
      body: Stack(
        children: [
          UniversalMapTile(
            onMapCreated: (mapboxMap) {
              _mapboxMap = mapboxMap;
              _stopAnnotationManager = null;
            },
          ),
          DragScrollSheet(
            children: [
              for (final trip in widget.route.trips)
                ElevatedButton(
                  onPressed: () async {
                    final map = _mapboxMap;
                    if (map == null) return;

                    final isTrain = widget.route.vehicleType == VehicleType.train;
                    final result = isTrain
                        ? await MapMatchingService.fetchRouteMetadataResultTrain(
                            widget.route.vehicleType,
                            _getShapeCoordinates(trip),
                          )
                        : await MapMatchingService.fetchMapMatching(
                            'driving-traffic',
                            _getStopTimesStopsCoord(trip.tripId),
                          );
                    if (result == null) return;

                    await MapMatchingService.drawPolyline(
                      map,
                      result.coordinates,
                    );
                    await _drawRouteStops(trip.tripId);
                  },
                  // TODO: Make the button display the start and end stopNames
                  child: Text(trip.tripId),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
