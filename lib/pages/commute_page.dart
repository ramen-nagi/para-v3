import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/universal_map_tile.dart';

class CommutePage extends StatefulWidget {
  const CommutePage({super.key});

  @override
  State<CommutePage> createState() => _CommutePageState();
}

class _CommutePageState extends State<CommutePage> {
  // ignore: unused_field
  MapboxMap? _mapboxMap;

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          UniversalMapTile(
            key: const PageStorageKey("CommuteMapTile"),
            initialZoom: 12.0,
            onMapCreated: _onMapCreated,
          ),
        ],
      ),
    );
  }
}
