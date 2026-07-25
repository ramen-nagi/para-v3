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
  MapboxMap? _mapboxMap;

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    debugPrint('Map initialized for route: ${widget.route.routeLongName}');
  }

  @override
  Widget build(BuildContext context) {
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
            initialCenter: Point(
              coordinates: Position(121.0403, 14.5895),
            ),
            initialZoom: 12.0,
            onMapCreated: _onMapCreated,
          ),

        ],
      ),
    );
  }
}
