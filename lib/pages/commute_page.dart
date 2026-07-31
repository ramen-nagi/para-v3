import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/universal_map_tile.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/raptor_pathfinding_service.dart';

class CommutePage extends StatefulWidget {
  const CommutePage({super.key});

  @override
  State<CommutePage> createState() => _CommutePageState();
}

class _CommutePageState extends State<CommutePage> {
  // ignore: unused_field
  MapboxMap? _mapboxMap;
  Position? _originLatLng;
  Position? _destinationLatLng;
  CircleAnnotationManager? _circleAnnotationManager;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    GtfsNetworkService.instance.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    GtfsNetworkService.instance.removeListener(_onServiceUpdate);
    _sheetController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
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

  Future<void> _drawOriginDestinationMarker() async {
    if (_mapboxMap == null) return;

    _circleAnnotationManager ??= await _mapboxMap!.annotations.createCircleAnnotationManager();
    await _circleAnnotationManager!.deleteAll();

    final List<CircleAnnotationOptions> annotations = [];

    if (_originLatLng != null) {
      annotations.add(CircleAnnotationOptions(
        geometry: Point(coordinates: _originLatLng!),
        circleRadius: 8.0,
        circleColor: Colors.blue.value,
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.value,
      ));
    }

    if (_destinationLatLng != null) {
      annotations.add(CircleAnnotationOptions(
        geometry: Point(coordinates: _destinationLatLng!),
        circleRadius: 8.0,
        circleColor: Colors.red.value,
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.value,
      ));
    }

    if (annotations.isNotEmpty) {
      await _circleAnnotationManager!.createMulti(annotations);
    }
  }

  void _runRaptorPathfinding() {
    if (_originLatLng == null || _destinationLatLng == null) return;

    print('Running RAPTOR Pathfinding...');
    final journeys = RaptorPathfindingService.instance.findJourneys(
      originLat: _originLatLng!.lat.toDouble(),
      originLng: _originLatLng!.lng.toDouble(),
      destLat: _destinationLatLng!.lat.toDouble(),
      destLng: _destinationLatLng!.lng.toDouble(),
    );

    if (journeys.isEmpty) {
      print('No journeys found.');
      return;
    }

    for (int i = 0; i < journeys.length; i++) {
      final journey = journeys[i];
      print('Journey ${i + 1}');
      for (int j = 0; j < journey.legs.length; j++) {
        final leg = journey.legs[j];
        final numStr = '${j + 1}.';
        if (leg is WalkLeg) {
          print('$numStr Walk');
          print('from ${leg.fromStopName}');
          print('to ${leg.toStopName}');
        } else if (leg is TransitLeg) {
          final typeStr = _getVehicleTypeString(leg.vehicleType);
          print('$numStr $typeStr (${leg.routeLongName})');
          print('from ${leg.fromStopName}');
          print('to ${leg.toStopName}');
        }
      }
      print('');
    }
  }

  String _getVehicleTypeString(VehicleType type) {
    switch (type) {
      case VehicleType.tricycle:
        return 'Tricycle';
      case VehicleType.train:
        return 'Train';
      case VehicleType.jeep:
        return 'Jeep';
      case VehicleType.bus:
        return 'Bus';
      case VehicleType.uvExpress:
        return 'UV Express';
      default:
        return 'Transit';
    }
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
            onLongTap: (Point point) async {
              final coordinates = point.coordinates;
              setState(() {
                if (_originLatLng == null) {
                  _originLatLng = coordinates;
                } else if (_destinationLatLng == null) {
                  _destinationLatLng = coordinates;
                } else {
                  _originLatLng = null;
                  _destinationLatLng = null;
                }
              });

              print('Origin: ${_originLatLng != null ? "${_originLatLng!.lat}, ${_originLatLng!.lng}" : "null"}');
              print('Destination: ${_destinationLatLng != null ? "${_destinationLatLng!.lat}, ${_destinationLatLng!.lng}" : "null"}');

              await _drawOriginDestinationMarker();
            },
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
                  ],
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: (_originLatLng != null && _destinationLatLng != null)
          ? FloatingActionButton(
              onPressed: _runRaptorPathfinding,
              child: const Icon(Icons.directions),
            )
          : null,
    );
  }
}
