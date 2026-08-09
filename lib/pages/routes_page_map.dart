import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/drag_scroll_sheet.dart';
import 'package:para_v3/module/universal_map_tile.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/map_matching_service.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.route.routeLongName),
      ),
      body: Stack(
        children: [
          UniversalMapTile(
            onMapCreated: (mapboxMap) => _mapboxMap = mapboxMap,
          ),
          DragScrollSheet(
            children: [
              for (final trip in widget.route.trips)
                ElevatedButton(
                  onPressed: () async {
                    final map = _mapboxMap;
                    if (map == null) return;

                    final coordinates = _getStopTimesStopsCoord(trip.tripId);
                    final result = await MapMatchingService.fetchMapMatching(
                      'driving-traffic',
                      coordinates,
                    );
                    if (result == null) return;

                    await MapMatchingService.drawPolyline(
                      map,
                      result.coordinates,
                    );
                  },
                  child: Text(trip.tripId),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
