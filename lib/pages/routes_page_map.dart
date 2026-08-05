import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/map_matching_service.dart';
import 'package:para_v3/module/drag_scroll_sheet.dart';
import 'package:para_v3/module/universal_map_tile.dart';

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
  // ignore: unused_field
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _circleAnnotationManager;

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
  }

  String _getTripHeader(TripsModel trip) {
    if (trip.stopTimes.isEmpty) {
      return 'Trip ID: ${trip.tripId}';
    }

    final firstStop = trip.stopTimes.first.stopName;
    final lastStop = trip.stopTimes.last.stopName;

    return '$firstStop - $lastStop';
  }

  List<Widget> _displayTripsCards(List<dynamic> trips) {
    return trips.map((trip) {
      final tripHeader = _getTripHeader(trip);

      return Card(
        margin: const EdgeInsets.only(bottom: 8.0),
        elevation: 1,
        child: ListTile(
          title: Text(
            tripHeader,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            '${trip.stopTimes.length} stops',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            size: 20,
          ),
          onTap: () async {
            debugPrint('Selected Trip: ${trip.tripId}');

            final map = _mapboxMap;
            if (map == null) return;

            await _drawStopMarkersOnMap(trip);

            //TOOD: Modify card widget to display all intermediate stops in an ordered list

            if (widget.route.vehicleType == VehicleType.train) {
              await MapMatchingService.drawShapePolyline(map, trip);
            } else {
              final positions = await MapMatchingService.fetchMapMatching(
                profile: 'driving-traffic',
                tripId: trip.tripId,
              );
              await MapMatchingService.drawRoutePolyline(map, positions);
            }
          },
        ),
      );
    }).toList();
  }

  Future<void> _drawStopMarkersOnMap(TripsModel trip) async {
    if (_mapboxMap == null) return;

    _circleAnnotationManager ??= await _mapboxMap!.annotations
        .createCircleAnnotationManager();

    await _circleAnnotationManager!.deleteAll();

    final stopTimes = MapMatchingService.getStopsAndStopTimes(trip);
    if (stopTimes.isEmpty) return;

    final List<CircleAnnotationOptions> annotations = [];

    for (int i = 0; i < stopTimes.length; i++) {
      final stop = stopTimes[i];
      final bool isStart = i == 0;
      final bool isEnd = i == stopTimes.length - 1;

      int circleColor = 0xFF1976D2;

      if (isStart) {
        circleColor = 0xFF388E3C;
      } else if (isEnd) {
        circleColor = 0xFFD32F2F;
      }

      final options = CircleAnnotationOptions(
        geometry: Point(
          coordinates: Position(stop.stopLon, stop.stopLat),
        ),
        circleRadius: isStart || isEnd ? 8.0 : 5.0,
        circleColor: circleColor,
        circleStrokeWidth: 2.0,
        circleStrokeColor: 0xFFFFFFFF,
      );

      annotations.add(options);
    }

    await _circleAnnotationManager!.createMulti(annotations);
  }

  @override
  Widget build(BuildContext context) {
    final trips = widget.route.trips;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.route.routeLongName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          UniversalMapTile(
            initialZoom: 12.0,
            onMapCreated: _onMapCreated,
          ),

          DragScrollSheet(
            children: [
              Text(
                'Available Directions / Trips (${trips.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 10),
              const SizedBox(height: 12),
              if (trips.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Text('No trip direction data available.'),
                )
              else
                ..._displayTripsCards(trips),
            ],
          ),
        ],
      ),
    );
  }
}
