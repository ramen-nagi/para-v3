import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/module/universal_map_tile.dart';

class RoutesPageMap extends StatefulWidget {
  final RouteModel route;

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

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  bool _isExpanded = false;

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    debugPrint('Map initialized for route: ${widget.route.routeLongName}');
  }

  void _toggleSheetPosition() {
    final double targetSize = _isExpanded ? 0.3 : 0.9;

    _sheetController.animateTo(
      targetSize,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );

    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  String _getTripHeader(TripModel trip) {
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
          onTap: () {
            debugPrint('Selected Trip: ${trip.tripId}');
          },
        ),
      );
    }).toList();
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

          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.3,
            minChildSize: 0.1,
            maxChildSize: 0.9,
            snap: false,
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20.0),
                  ),
                ),
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    GestureDetector(
                      onTap: _toggleSheetPosition,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 12),

                          Container(
                            width: 40,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),

                          const SizedBox(height: 12),
                        ],
                      ),
                    ),

                    // TODO: Add card widget with trips content
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Available Directions / Trips (${trips.length})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

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
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // TODO: Refactor this function and the one in route_page.dart into gtfs_network_service.dart
  IconData _getIconForType(VehicleType type) {
    switch (type) {
      case VehicleType.bus:
        return Icons.directions_bus;
      case VehicleType.jeep:
        return Icons.airport_shuttle;
      case VehicleType.train:
        return Icons.train;
      case VehicleType.tricycle:
        return Icons.pedal_bike;
      case VehicleType.uvExpress:
        return Icons.directions_car;
      default:
        return Icons.alt_route;
    }
  }
}
