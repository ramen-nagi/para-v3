import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/universal_map_tile.dart';
import 'package:para_v3/pages/commute_page.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/map_matching_service.dart';
import 'package:para_v3/services/raptor_pathfinding_service.dart';

class CommutePageMap extends StatefulWidget {
  const CommutePageMap({
    super.key,
    required this.originSuggestion,
    required this.destinationSuggestion,
    required this.originLatLng,
    required this.destinationLatLng,
  });

  final PlaceSuggestion originSuggestion;
  final PlaceSuggestion destinationSuggestion;
  final Position? originLatLng;
  final Position? destinationLatLng;

  @override
  State<CommutePageMap> createState() => _CommutePageMapState();
}

class _CommutePageMapState extends State<CommutePageMap> {
  // ignore: unused_field
  MapboxMap? _mapboxMap;

  Position? _originLatLng;
  Position? _destinationLatLng;
  PlaceSuggestion? _originSuggestion;
  PlaceSuggestion? _destinationSuggestion;

  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  CircleAnnotationManager? _circleAnnotationManager;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  bool _isExpanded = false;
  bool _hasRunPathfinding = false;
  bool _hasCompletedPathfinding = false;
  List<Journey> _journeys = [];

  @override
  void initState() {
    super.initState();
    _originSuggestion = widget.originSuggestion;
    _destinationSuggestion = widget.destinationSuggestion;
    _originLatLng = widget.originLatLng;
    _destinationLatLng = widget.destinationLatLng;
    _originController.text = _originSuggestion?.fullText ?? '';
    _destinationController.text = _destinationSuggestion?.fullText ?? '';
    GtfsNetworkService.instance.addListener(_onServiceUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runRaptorPathfindingWhenReady();
    });
  }

  @override
  void dispose() {
    GtfsNetworkService.instance.removeListener(_onServiceUpdate);
    _sheetController.dispose();
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {});
      _runRaptorPathfindingWhenReady();
    }
  }

  void _runRaptorPathfindingWhenReady() {
    if (_hasRunPathfinding || !GtfsNetworkService.instance.isLoaded) {
      return;
    }

    _hasRunPathfinding = true;
    _runRaptorPathfinding();
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    _drawOriginDestinationMarker();
    _fitCameraToOriginAndDestination();
  }

  Future<void> _fitCameraToOriginAndDestination() async {
    final map = _mapboxMap;
    final origin = _originLatLng;
    final destination = _destinationLatLng;
    if (map == null || origin == null || destination == null) return;

    final cameraOptions = await map.cameraForCoordinatesPadding(
      [Point(coordinates: origin), Point(coordinates: destination)],
      CameraOptions(),
      MbxEdgeInsets(top: 50, left: 50, bottom: 250, right: 50),
      null,
      null,
    );

    await map.easeTo(
      cameraOptions,
      MapAnimationOptions(duration: 750),
    );
  }

  void _toggleSheetPosition() {
    final double targetSize = _isExpanded ? 0.2 : 0.9;

    _sheetController.animateTo(
      targetSize,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );

    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  void _goBackToPreviousPage() {
    Navigator.of(context).pop();
  }

  Future<void> _drawOriginDestinationMarker({Journey? journey}) async {
    if (_mapboxMap == null) return;

    _circleAnnotationManager ??= await _mapboxMap!.annotations
        .createCircleAnnotationManager();
    await _circleAnnotationManager!.deleteAll();

    final List<CircleAnnotationOptions> annotations = [];

    if (_originLatLng != null) {
      annotations.add(
        CircleAnnotationOptions(
          geometry: Point(coordinates: _originLatLng!),
          circleRadius: 8.0,
          circleColor: Colors.blue.value,
          circleStrokeWidth: 2.0,
          circleStrokeColor: Colors.white.value,
        ),
      );
    }

    if (_destinationLatLng != null) {
      annotations.add(
        CircleAnnotationOptions(
          geometry: Point(coordinates: _destinationLatLng!),
          circleRadius: 8.0,
          circleColor: Colors.red.value,
          circleStrokeWidth: 2.0,
          circleStrokeColor: Colors.white.value,
        ),
      );
    }

    if (journey != null) {
      final significantStopIds = <String>{};
      for (final leg in journey.legs) {
        if (!leg.fromStopId.startsWith('__')) {
          significantStopIds.add(leg.fromStopId);
        }
        if (!leg.toStopId.startsWith('__')) {
          significantStopIds.add(leg.toStopId);
        }
      }

      for (final stopId in significantStopIds) {
        final position = _positionForLegStop(stopId);
        if (position == null) continue;
        annotations.add(
          CircleAnnotationOptions(
            geometry: Point(coordinates: position),
            circleRadius: 5.0,
            circleColor: 0xFF2196F3,
            circleStrokeWidth: 2.0,
            circleStrokeColor: 0xFFFAF9F6,
          ),
        );
      }
    }

    if (annotations.isNotEmpty) {
      await _circleAnnotationManager!.createMulti(annotations);
    }
  }

  void _runRaptorPathfinding() {
    if (_originLatLng == null || _destinationLatLng == null) return;

    final journeys = RaptorPathfindingService.instance.findJourneys(
      originLat: _originLatLng!.lat.toDouble(),
      originLng: _originLatLng!.lng.toDouble(),
      destLat: _destinationLatLng!.lat.toDouble(),
      destLng: _destinationLatLng!.lng.toDouble(),
    );

    setState(() {
      _journeys = journeys.take(3).toList();
      _hasCompletedPathfinding = true;
    });
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

  Widget _buildTextField({
    required TextEditingController controller,
    required IconData icon,
    required Color iconColor,
    required String hintText,
  }) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: _goBackToPreviousPage,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: iconColor),
        hintText: hintText,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // TODO: make journey cards neater ui-wise
  Widget _buildJourneyCard(Journey journey, int journeyIndex) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Journey ${journeyIndex + 1}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < journey.legs.length; index++)
              _buildJourneyLeg(journey.legs[index], index),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.navigation),
                label: const Text('Start Commute'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJourneyLeg(Leg leg, int legIndex) {
    final String title;
    final String fromStopName;
    final String toStopName;

    if (leg is WalkLeg) {
      title = '${legIndex + 1}. Walk';
      fromStopName = leg.fromStopName;
      toStopName = leg.toStopName;
    } else if (leg is TransitLeg) {
      title = '${legIndex + 1}. '
          '${_getVehicleTypeString(leg.vehicleType)} (${leg.routeLongName})';
      fromStopName = leg.fromStopName;
      toStopName = leg.toStopName;
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          Text('from $fromStopName'),
          Text('to $toStopName'),
        ],
      ),
    );
  }

  Future<void> _drawJourneyPolylines(Journey journey) async {
    final map = _mapboxMap;
    if (map == null) return;

    await _drawOriginDestinationMarker(journey: journey);
    await MapMatchingService.clearCommuteLegPolylines(map);
    final journeyPositions = <Position>[];

    for (var index = 0; index < journey.legs.length; index++) {
      final leg = journey.legs[index];
      final fromPosition = _positionForLegStop(leg.fromStopId);
      final toPosition = _positionForLegStop(leg.toStopId);
      if (fromPosition == null || toPosition == null) {
        debugPrint('Unable to find coordinates for commute leg $index.');
        continue;
      }

      final legPositions = await MapMatchingService.drawCommuteLegPolyline(
        map: map,
        coordinates: [fromPosition, toPosition],
        profile: leg is WalkLeg ? 'walking' : 'driving',
        vehicleType: leg is TransitLeg ? leg.vehicleType : null,
        tripId: leg is TransitLeg ? leg.tripId : null,
        fromStopName: leg is TransitLeg ? leg.fromStopName : null,
        toStopName: leg is TransitLeg ? leg.toStopName : null,
        legIndex: index,
      );
      journeyPositions.addAll(legPositions);
    }

    await MapMatchingService.fitCameraToPositions(map, journeyPositions);
  }

  Position? _positionForLegStop(String stopId) {
    if (stopId == '__ORIGIN__') return _originLatLng;
    if (stopId == '__DESTINATION__') return _destinationLatLng;
    return MapMatchingService.getStopCoordinate(stopId);
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
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 16,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              shape: const CircleBorder(),
              elevation: 4,
              child: SizedBox.square(
                dimension: 48,
                child: IconButton(
                  alignment: Alignment.center,
                  padding: EdgeInsets.zero,
                  onPressed: _goBackToPreviousPage,
                  icon: const Icon(Icons.arrow_back_ios),
                ),
              ),
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.2,
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

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        children: [
                          _buildTextField(
                            controller: _originController,
                            icon: Icons.location_on,
                            iconColor: Colors.blue,
                            hintText: 'Origin Location',
                          ),
                          const SizedBox(height: 10),
                          _buildTextField(
                            controller: _destinationController,
                            icon: Icons.location_on,
                            iconColor: Colors.red,
                            hintText: 'Target Destination',
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),

                    const Divider(height: 10),

                    if (_hasCompletedPathfinding && _journeys.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No journeys found.'),
                      ),
                    for (var index = 0; index < _journeys.length; index++)
                      GestureDetector(
                        onTap: () => _drawJourneyPolylines(_journeys[index]),
                        child: _buildJourneyCard(_journeys[index], index),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
