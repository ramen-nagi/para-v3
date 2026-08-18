import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/drag_scroll_sheet.dart';
import 'package:para_v3/module/location_textfield.dart';
import 'package:para_v3/module/universal_map_tile.dart';
import 'package:para_v3/pages/commute_page_input.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/commute_history_service.dart';
import 'package:para_v3/services/map_matching_service.dart';
import 'package:para_v3/services/profile_store.dart';
import 'package:para_v3/services/raptor_pathfinding_service.dart';
import 'package:share_plus/share_plus.dart';

class CommuteEndpoint {
  final String label;
  final double latitude;
  final double longitude;

  const CommuteEndpoint({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  factory CommuteEndpoint.fromSavedPlace(SavedPlace place) => CommuteEndpoint(
    label: place.address,
    latitude: place.latitude,
    longitude: place.longitude,
  );

  Position get position => Position(longitude, latitude);
}

class CommutePage extends StatefulWidget {
  final CommuteEndpoint? initialOrigin;
  final CommuteEndpoint? initialDestination;

  const CommutePage({
    super.key,
    this.initialOrigin,
    this.initialDestination,
  });

  @override
  State<CommutePage> createState() => _CommutePageState();
}

enum _CommuteSheetView { journeyOverviews, journeyDetails, activeLeg }

class _CommutePageState extends State<CommutePage> {
  final _store = ProfileStore();
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  Position? _originPosition;
  Position? _destinationPosition;
  List<Journey> _journeys = [];
  Journey? _selectedJourney;
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _endpointAnnotationManager;
  CircleAnnotationManager? _intermediateStopsAnnotationManager;
  _CommuteSheetView _sheetView = _CommuteSheetView.journeyOverviews;
  int _activeLegIndex = 0;
  int _drawnJourneyPolylineCount = 0;
  int _planningRequest = 0;
  bool _hasSearched = false;
  bool _isPlanning = false;
  bool _datasetUnavailable = false;

  bool get _isCommuting => _sheetView == _CommuteSheetView.activeLeg;

  @override
  void initState() {
    super.initState();
    final origin = widget.initialOrigin;
    final destination = widget.initialDestination;
    if (origin != null) {
      _originController.text = origin.label;
      _originPosition = origin.position;
    }
    if (destination != null) {
      _destinationController.text = destination.label;
      _destinationPosition = destination.position;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (origin != null && destination != null) {
        _runRaptor(origin.position, destination.position);
      } else if (origin != null || destination != null) {
        _openInputPage(
          origin == null
              ? CommuteInputField.origin
              : CommuteInputField.destination,
        );
      }
    });
  }

  @override
  void dispose() {
    _planningRequest++;
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _openInputPage(CommuteInputField initialField) async {
    final result = await Navigator.of(context).push<CommuteInputResult>(
      MaterialPageRoute(
        builder: (context) => CommutePageInput(
          originController: _originController,
          destinationController: _destinationController,
          initialField: initialField,
          originPosition: _originPosition,
          destinationPosition: _destinationPosition,
        ),
      ),
    );
    if (!mounted || result == null) return;

    await _clearJourneyMapOverlays();
    setState(() {
      _originPosition = result.originPosition;
      _destinationPosition = result.destinationPosition;
    });
    await _showOriginDestinationMarkersAndFit();
    await _runRaptor(result.originPosition, result.destinationPosition);
  }

  Future<void> _shareCurrentLocation(BuildContext sourceContext) async {
    final shareOrigin = sourceContext.findRenderObject() as RenderBox?;
    final sharePositionOrigin = shareOrigin == null
        ? null
        : shareOrigin.localToGlobal(Offset.zero) & shareOrigin.size;
    try {
      if (!await geo.Geolocator.isLocationServiceEnabled()) {
        _showLocationShareMessage('Turn on device location to share it.');
        return;
      }

      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied ||
          permission == geo.LocationPermission.deniedForever) {
        _showLocationShareMessage('Location permission is needed to share it.');
        return;
      }

      final position = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;

      final latitude = position.latitude.toStringAsFixed(6);
      final longitude = position.longitude.toStringAsFixed(6);
      await SharePlus.instance.share(
        ShareParams(
          subject: 'My location from Para',
          text:
              'Here is my current location: '
              'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    } catch (_) {
      _showLocationShareMessage(
        'Could not get your current location. Please try again.',
      );
    }
  }

  void _showLocationShareMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runRaptor(Position origin, Position destination) async {
    final request = ++_planningRequest;
    setState(() {
      _isPlanning = true;
      _hasSearched = false;
      _journeys = [];
      _selectedJourney = null;
      _sheetView = _CommuteSheetView.journeyOverviews;
    });
    var journeys = <Journey>[];
    try {
      final profile = await _store.load();
      if (!mounted || request != _planningRequest) return;
      final options = RaptorRoutingOptions.fromProfile(profile);
      journeys = RaptorPathfindingService.instance.findJourneys(
        originLat: origin.lat.toDouble(),
        originLng: origin.lng.toDouble(),
        destLat: destination.lat.toDouble(),
        destLng: destination.lng.toDouble(),
        options: options,
      );

      for (final journey in journeys) {
        await _enrichJourneyLegs(journey);
      }
      journeys.removeWhere(
        (journey) => journey.legs.any(
          (leg) =>
              leg.isWalking &&
              (leg.distance ?? double.infinity) >
                  options.maxWalkingDistance + 1,
        ),
      );
      RaptorPathfindingService.instance.sortJourneys(
        journeys,
        options.priority,
      );
      if (journeys.length > 3) journeys.removeRange(3, journeys.length);
      if (!mounted || request != _planningRequest) return;

      setState(() {
        _journeys = journeys;
        _hasSearched = true;
        _datasetUnavailable = !GtfsNetworkService.instance.isLoaded;
      });
    } catch (_) {
      if (!mounted || request != _planningRequest) return;
      setState(() {
        _hasSearched = true;
        _datasetUnavailable = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not plan this journey. Please try again.'),
          ),
        );
    } finally {
      if (mounted && request == _planningRequest) {
        setState(() => _isPlanning = false);
      }
    }
  }

  Future<void> _finishCommute() async {
    var saved = false;
    try {
      saved = await CommuteHistoryService.add(
        CommuteHistoryEntry(
          origin: _originController.text.trim(),
          destination: _destinationController.text.trim(),
          completedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this commute.')),
      );
      return;
    }
    setState(() {
      _journeys = [];
      _selectedJourney = null;
      _sheetView = _CommuteSheetView.journeyOverviews;
      _activeLegIndex = 0;
      _hasSearched = false;
    });
    await _clearJourneyMapOverlays();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Commute completed and saved.')),
      );
  }

  Future<void> _enrichJourneyLegs(Journey journey) async {
    for (final leg in journey.legs) {
      RouteMetadataResult? metadata;

      if (leg.vehicleType == VehicleType.train) {
        final trip = _findTripById(leg.tripId);
        final shapeCoordinates = trip == null
            ? const <Position>[]
            : _getTrainLegShapeCoordinates(trip, leg);
        if (shapeCoordinates.length < 2) continue;
        metadata = await MapMatchingService.fetchRouteMetadataResultTrain(
          leg.vehicleType,
          shapeCoordinates,
        );
      } else if (leg.isWalking) {
        final start = _positionForLegStop(leg.fromStopId);
        final end = _positionForLegStop(leg.toStopId);
        if (start == null || end == null) continue;
        metadata = await MapMatchingService.fetchMapMatching(
          'walking',
          [start, end],
        );
      } else {
        final trip = _findTripById(leg.tripId);
        if (trip == null) continue;

        final stopCoordinates = _getTransitLegStopCoordinates(trip, leg);
        if (stopCoordinates.length < 2) continue;
        metadata = await MapMatchingService.fetchMapMatching(
          'driving-traffic',
          stopCoordinates,
        );
      }

      if (metadata == null) continue;
      leg.coordinates = metadata.coordinates;
      leg.distance = metadata.distanceMeters;
      leg.durationSeconds = metadata.durationSeconds;
      leg.traffic = metadata.traffic;
      leg.steps = metadata.steps;
    }
  }

  TripsModel? _findTripById(String? tripId) {
    if (tripId == null) return null;
    for (final route in GtfsNetworkService.instance.routesMap.values) {
      for (final trip in route.trips) {
        if (trip.tripId == tripId) return trip;
      }
    }
    return null;
  }

  Position? _positionForLegStop(String stopId) {
    if (stopId == '__ORIGIN__') return _originPosition;
    if (stopId == '__DESTINATION__') return _destinationPosition;

    for (final route in GtfsNetworkService.instance.routesMap.values) {
      for (final trip in route.trips) {
        for (final stop in trip.stopTimes) {
          if (stop.stopId == stopId) {
            return Position(stop.stopLon, stop.stopLat);
          }
        }
      }
    }
    return null;
  }

  List<Position> _getTransitLegStopCoordinates(TripsModel trip, Leg leg) {
    final stops = List<StopsAndStopTimesModel>.from(trip.stopTimes)
      ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    final fromIndex = stops.indexWhere((stop) => stop.stopId == leg.fromStopId);
    final toIndex = stops.indexWhere((stop) => stop.stopId == leg.toStopId);
    if (fromIndex == -1 || toIndex == -1) return [];

    final legStops = fromIndex <= toIndex
        ? stops.sublist(fromIndex, toIndex + 1)
        : stops.sublist(toIndex, fromIndex + 1).reversed;
    return legStops
        .map((stop) => Position(stop.stopLon, stop.stopLat))
        .toList();
  }

  List<Position> _getTrainLegShapeCoordinates(TripsModel trip, Leg leg) {
    final shapes = List<ShapesModel>.from(trip.shapes ?? [])
      ..sort((a, b) => a.shapePtSequence.compareTo(b.shapePtSequence));
    if (shapes.isEmpty) return [];

    final allCoordinates = shapes
        .map((shape) => Position(shape.shapePtLon, shape.shapePtLat))
        .toList();
    final start = _positionForLegStop(leg.fromStopId);
    final end = _positionForLegStop(leg.toStopId);
    if (start == null || end == null) return allCoordinates;

    final startIndex = _nearestCoordinateIndex(allCoordinates, start);
    final endIndex = _nearestCoordinateIndex(allCoordinates, end);
    return startIndex <= endIndex
        ? allCoordinates.sublist(startIndex, endIndex + 1)
        : allCoordinates.sublist(endIndex, startIndex + 1).reversed.toList();
  }

  int _nearestCoordinateIndex(List<Position> coordinates, Position target) {
    var nearestIndex = 0;
    var nearestDistanceSquared = double.infinity;
    for (var index = 0; index < coordinates.length; index++) {
      final coordinate = coordinates[index];
      final latitudeDifference =
          coordinate.lat.toDouble() - target.lat.toDouble();
      final longitudeDifference =
          coordinate.lng.toDouble() - target.lng.toDouble();
      final distanceSquared =
          latitudeDifference * latitudeDifference +
          longitudeDifference * longitudeDifference;
      if (distanceSquared < nearestDistanceSquared) {
        nearestIndex = index;
        nearestDistanceSquared = distanceSquared;
      }
    }
    return nearestIndex;
  }

  Future<void> _drawSelectedJourneyPolylines(Journey journey) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    await _clearJourneyPolylines();

    for (var index = 0; index < journey.legs.length; index++) {
      final leg = journey.legs[index];
      final coordinates = leg.coordinates;
      if (coordinates == null || coordinates.length < 2) continue;

      await MapMatchingService.drawPolyline(
        mapboxMap,
        coordinates,
        sourceId: 'selected-journey-leg-source-$index',
        layerId: 'selected-journey-leg-layer-$index',
        dotted: leg.isWalking,
      );
    }
    _drawnJourneyPolylineCount = journey.legs.length;
  }

  Future<void> _clearJourneyPolylines() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final style = mapboxMap.style;
    for (var index = 0; index < _drawnJourneyPolylineCount; index++) {
      final layerId = 'selected-journey-leg-layer-$index';
      final sourceId = 'selected-journey-leg-source-$index';
      if (await style.styleLayerExists(layerId)) {
        await style.removeStyleLayer(layerId);
      }
      if (await style.styleSourceExists(sourceId)) {
        await style.removeStyleSource(sourceId);
      }
    }
    _drawnJourneyPolylineCount = 0;
  }

  Future<void> _clearJourneyMapOverlays() async {
    await _clearJourneyPolylines();
    final intermediateStopsManager = _intermediateStopsAnnotationManager;
    if (intermediateStopsManager != null) {
      await intermediateStopsManager.deleteAll();
    }
  }

  Future<void> _drawIntermediateStops(Journey journey) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final intermediatePositions = <Position>[];
    final seenStopIds = <String>{};
    for (final leg in journey.legs) {
      for (final stopId in [leg.fromStopId, leg.toStopId]) {
        if (stopId == '__ORIGIN__' ||
            stopId == '__DESTINATION__' ||
            !seenStopIds.add(stopId)) {
          continue;
        }
        final position = _positionForLegStop(stopId);
        if (position != null) intermediatePositions.add(position);
      }
    }

    final manager = _intermediateStopsAnnotationManager ??= await mapboxMap
        .annotations
        .createCircleAnnotationManager(
          id: 'journey-intermediate-stops',
        );
    await manager.deleteAll();
    if (intermediatePositions.isEmpty) return;

    await manager.createMulti(
      intermediatePositions
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

  Future<void> _focusLegOnMap(Leg leg) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    final coordinates =
        leg.coordinates ??
        [
          _positionForLegStop(leg.fromStopId),
          _positionForLegStop(leg.toStopId),
        ].whereType<Position>().toList();
    if (coordinates.length < 2) return;

    final camera = await mapboxMap.cameraForCoordinatesPadding(
      coordinates.map((position) => Point(coordinates: position)).toList(),
      CameraOptions(),
      MbxEdgeInsets(top: 120, left: 40, bottom: 300, right: 40),
      null,
      null,
    );
    await mapboxMap.flyTo(camera, MapAnimationOptions(duration: 500));
  }

  Future<void> _startCommute(Journey journey) async {
    if (journey.legs.isEmpty) return;
    setState(() {
      _sheetView = _CommuteSheetView.activeLeg;
      _activeLegIndex = 0;
    });
    await _focusLegOnMap(journey.legs.first);
  }

  Future<void> _showLegAtIndex(Journey journey, int index) async {
    setState(() => _activeLegIndex = index);
    await _focusLegOnMap(journey.legs[index]);
  }

  Future<void> _showOriginDestinationMarkersAndFit() async {
    final mapboxMap = _mapboxMap;
    final origin = _originPosition;
    final destination = _destinationPosition;
    if (mapboxMap == null || origin == null || destination == null) return;

    final manager = _endpointAnnotationManager ??= await mapboxMap.annotations
        .createCircleAnnotationManager(
          id: 'commute-endpoints',
        );
    await manager.deleteAll();
    await manager.createMulti([
      CircleAnnotationOptions(
        geometry: Point(coordinates: origin),
        circleColor: 0xFF1565C0,
        circleRadius: 6,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 2,
      ),
      CircleAnnotationOptions(
        geometry: Point(coordinates: destination),
        circleColor: 0xFFC62828,
        circleRadius: 6,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 2,
      ),
    ]);

    final cameraOptions = await mapboxMap.cameraForCoordinatesPadding(
      [Point(coordinates: origin), Point(coordinates: destination)],
      CameraOptions(),
      MbxEdgeInsets(top: 180, left: 40, bottom: 280, right: 40),
      null,
      null,
    );
    await mapboxMap.flyTo(
      cameraOptions,
      MapAnimationOptions(duration: 700),
    );
  }

  Widget _buildJourneyCardOverview(Journey journey) {
    final totalDistance = journey.legs.fold<double>(
      0,
      (total, leg) => total + (leg.distance ?? 0),
    );
    final walkingDistance = journey.legs
        .where((leg) => leg.isWalking)
        .fold<double>(0, (total, leg) => total + (leg.distance ?? 0));

    final hasDuration = journey.legs.any((leg) => leg.durationSeconds != null);
    final totalDuration = journey.legs.fold<double>(
      0,
      (total, leg) => total + (leg.durationSeconds ?? 0),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          setState(() {
            _selectedJourney = journey;
            _sheetView = _CommuteSheetView.journeyDetails;
          });
          await _drawSelectedJourneyPolylines(journey);
          await _drawIntermediateStops(journey);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildOverviewValue(
                      'Total distance',
                      _formatDistance(totalDistance),
                    ),
                  ),
                  Expanded(
                    child: _buildOverviewValue(
                      'Walking distance',
                      _formatDistance(walkingDistance),
                    ),
                  ),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Fare'),
                        SizedBox(height: 2),
                        Text(
                          '—',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final leg in journey.legs)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(_vehicleTypeIcon(leg.vehicleType)),
                    ),
                  const Spacer(),
                  const Icon(Icons.schedule, size: 18),
                  const SizedBox(width: 4),
                  Text(_formatDuration(hasDuration ? totalDuration : null)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  IconData _vehicleTypeIcon(VehicleType vehicleType) {
    switch (vehicleType) {
      case VehicleType.walk:
        return Icons.directions_walk;
      case VehicleType.train:
        return Icons.train;
      case VehicleType.bus:
        return Icons.directions_bus;
      case VehicleType.jeep:
        return Icons.airport_shuttle;
      case VehicleType.tricycle:
        return Icons.moped;
      case VehicleType.uvExpress:
        return Icons.directions_car;
      case VehicleType.unknown:
        return Icons.directions_transit;
    }
  }

  String _formatDistance(double? distanceMeters) {
    if (distanceMeters == null) return 'Distance unavailable';
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.toStringAsFixed(0)} m';
  }

  String _formatDuration(double? durationSeconds) {
    if (durationSeconds == null) return 'Duration unavailable';
    if (durationSeconds >= 60) {
      return '${(durationSeconds / 60).round()} min';
    }
    return '${durationSeconds.toStringAsFixed(0)} sec';
  }

  Widget _oneLineText(String text, {TextStyle? style}) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  Widget _buildExpandedJourneyView(Journey selectedJourney) {
    final legs = selectedJourney.legs;

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() {
                _selectedJourney = null;
                _sheetView = _CommuteSheetView.journeyOverviews;
              }),
            ),
            Expanded(
              child: _oneLineText(
                'Journey details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Divider(height: 10),
        const SizedBox(height: 8),

        for (var index = 0; index < legs.length; index++)
          _buildExpandedLegRow(
            leg: legs[index],
            isOrigin: index == 0,
            stopName: index == 0 && _originController.text.isNotEmpty
                ? _originController.text
                : legs[index].fromStopName,
          ),
        if (legs.isNotEmpty)
          _buildExpandedDestinationRow(
            _destinationController.text.isNotEmpty
                ? _destinationController.text
                : legs.last.toStopName,
          ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _startCommute(selectedJourney),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start commute'),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveLegView(Journey journey) {
    final leg = journey.legs[_activeLegIndex];
    final isFirst = _activeLegIndex == 0;
    final isLast = _activeLegIndex == journey.legs.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Journey details',
              onPressed: () =>
                  setState(() => _sheetView = _CommuteSheetView.journeyDetails),
            ),
            Expanded(
              child: _oneLineText(
                'Part ${_activeLegIndex + 1} / ${journey.legs.length}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _oneLineText(
          leg.fromStopName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(_vehicleTypeIcon(leg.vehicleType)),
            const SizedBox(width: 8),
            Expanded(
              child: _oneLineText(
                leg.isWalking ? 'Walk' : (leg.routeLongName ?? 'Transit'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (leg.isWalking) ...[
          if (leg.steps?.isNotEmpty == true)
            for (var index = 0; index < leg.steps!.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index + 1}.',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _oneLineText(leg.steps![index].instruction),
                    ),
                  ],
                ),
              )
          else
            const Text('Walk to the next stop.'),
        ] else ...[
          _oneLineText('Board at: ${leg.fromStopName}'),
          const SizedBox(height: 6),
          _oneLineText('Get off at: ${leg.toStopName}'),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.schedule, size: 18),
            const SizedBox(width: 4),
            _oneLineText(_formatDuration(leg.durationSeconds)),
            const SizedBox(width: 16),
            const Icon(Icons.straighten, size: 18),
            const SizedBox(width: 4),
            Expanded(child: _oneLineText(_formatDistance(leg.distance))),
            const SizedBox(width: 8),
            const Text('Fare: -'),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isFirst
                    ? null
                    : () => _showLegAtIndex(journey, _activeLegIndex - 1),
                child: const Text('Previous'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: isLast
                    ? _finishCommute
                    : () => _showLegAtIndex(journey, _activeLegIndex + 1),
                child: Text(isLast ? 'Finish' : 'Next'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExpandedLegRow({
    required Leg leg,
    required bool isOrigin,
    required String stopName,
  }) {
    final markerColor = isOrigin ? Colors.blue : Colors.blue.shade700;
    final routeName = leg.isWalking ? 'Walk' : (leg.routeLongName ?? 'Transit');

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 48, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _oneLineText(
                stopName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(_vehicleTypeIcon(leg.vehicleType), size: 20),
                  const SizedBox(width: 6),
                  Expanded(child: _oneLineText(routeName)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 16),
                  const SizedBox(width: 4),
                  Flexible(
                    child: _oneLineText(_formatDuration(leg.durationSeconds)),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.straighten, size: 16),
                  const SizedBox(width: 4),
                  Flexible(child: _oneLineText(_formatDistance(leg.distance))),
                  const SizedBox(width: 12),
                  Flexible(child: _oneLineText('Fare: -')),
                ],
              ),
              const SizedBox(height: 4),
              const Divider(height: 10),
            ],
          ),
        ),
        Positioned(
          left: isOrigin ? 12 : 14,
          top: 2,
          child: Container(
            width: isOrigin ? 16 : 12,
            height: isOrigin ? 16 : 12,
            decoration: BoxDecoration(
              color: markerColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
        const Positioned(
          left: 18,
          top: 24,
          bottom: 0,
          width: 4,
          child: CustomPaint(painter: _DottedProgressPainter()),
        ),
      ],
    );
  }

  Widget _buildExpandedDestinationRow(String destinationName) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _oneLineText(
            destinationName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        UniversalMapTile(
          onShareLocation: _shareCurrentLocation,
          onMapCreated: (mapboxMap) async {
            _mapboxMap = mapboxMap;
            _endpointAnnotationManager = null;
            _intermediateStopsAnnotationManager = null;
            await _showOriginDestinationMarkersAndFit();
          },
        ),
        // TODO: Make this invisible on enums journeyDetails, activeLeg
        if (_sheetView == _CommuteSheetView.journeyOverviews)
          Positioned(
            top: 25,
            left: 8,
            right: 8,
            child: LocationTextfield(
              originController: _originController,
              destinationController: _destinationController,
              readOnly: true,
              onOriginTap: () => _openInputPage(CommuteInputField.origin),
              onDestinationTap: () =>
                  _openInputPage(CommuteInputField.destination),
            ),
          ),
        if (_isPlanning)
          const Positioned(
            top: 132,
            left: 24,
            right: 24,
            child: LinearProgressIndicator(),
          )
        else if (_hasSearched && _journeys.isEmpty)
          Positioned(
            top: 132,
            left: 16,
            right: 16,
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.route_outlined),
                title: Text(
                  _datasetUnavailable
                      ? 'Route data is still loading. Please try again.'
                      : 'No journey is available for this trip.',
                ),
              ),
            ),
          ),
        if (_journeys.isNotEmpty && !_isCommuting)
          DragScrollSheet(
            children: [
              if (_sheetView == _CommuteSheetView.journeyOverviews) ...[
                Text('${_journeys.length} journeys found'),
                const SizedBox(height: 8),
                for (var index = 0; index < _journeys.length; index++)
                  _buildJourneyCardOverview(_journeys[index]),
              ],
              if (_sheetView == _CommuteSheetView.journeyDetails)
                _buildExpandedJourneyView(_selectedJourney!),
            ],
          )
        else if (_journeys.isNotEmpty && _isCommuting)
          DragScrollSheet(
            key: const ValueKey('active-commute-sheet'),
            initialChildSize: 0.22,
            minChildSize: 0.1,
            maxChildSize: 0.22,
            snapSizes: const [0.1, 0.22],
            children: [
              _buildActiveLegView(_selectedJourney!),
            ],
          ),
      ],
    );
  }
}

class _DottedProgressPainter extends CustomPainter {
  const _DottedProgressPainter();

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final paint = ui.Paint()..color = Colors.grey;
    const radius = 2.0;
    const gap = 8.0;
    final centerX = size.width / 2;

    for (var y = radius; y < size.height; y += radius * 2 + gap) {
      canvas.drawCircle(ui.Offset(centerX, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedProgressPainter oldDelegate) => false;
}
