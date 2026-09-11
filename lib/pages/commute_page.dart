import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/drag_scroll_sheet.dart';
import 'package:para_v3/module/location_textfield.dart';
import 'package:para_v3/module/route_suggestion_button.dart';
import 'package:para_v3/module/report_button.dart';
import 'package:para_v3/module/universal_map_tile.dart';
import 'package:para_v3/pages/commute_page_input.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/mapbox_services.dart';
import 'package:para_v3/services/raptor_pathfinding_service.dart';
import 'package:para_v3/services/route_progress_service.dart';
import 'package:para_v3/services/fare_calculator_service.dart';
import 'package:para_v3/services/commute_preferences_service.dart';
import 'package:para_v3/services/recents_service.dart';

class CommutePageController {
  _CommutePageState? _state;
  Journey? _pendingJourney;

  Future<void> openRecentJourney(Journey journey) async {
    final state = _state;
    if (state == null) {
      _pendingJourney = journey;
      return;
    }
    await state._openRecentJourney(journey);
  }

  void _attach(_CommutePageState state) {
    _state = state;
    final pendingJourney = _pendingJourney;
    _pendingJourney = null;
    if (pendingJourney != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_state == state && state.mounted) {
          state._openRecentJourney(pendingJourney);
        }
      });
    }
  }

  void _detach(_CommutePageState state) {
    if (_state == state) _state = null;
  }
}

class CommutePage extends StatefulWidget {
  final CommutePageController? controller;

  const CommutePage({super.key, this.controller});

  @override
  State<CommutePage> createState() => _CommutePageState();
}

enum _CommuteSheetView {
  journeyOverviews,
  journeyDetails,
  activeLeg,
  commuteComplete,
}

class _CommutePageState extends State<CommutePage> {
  static const _offRouteDistanceMeters = 100.0;
  static const _nextLegDistanceMeters = 50.0;
  static const _legEndDistanceMeters = 35.0;
  static const _journeyPolylineColor = Color(0xFF0081FB);
  static const _journeyDestinationColor = Color(0xFFC62828);

  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  Position? _originPosition;
  Position? _destinationPosition;
  String? _originMainText;
  String? _destinationMainText;
  List<Journey> _journeys = [];
  Journey? _selectedJourney;
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _endpointAnnotationManager;
  CircleAnnotationManager? _intermediateStopsAnnotationManager;
  _CommuteSheetView _sheetView = _CommuteSheetView.journeyOverviews;
  int _activeLegIndex = 0;
  int _drawnJourneyPolylineCount = 0;
  StreamSubscription<geo.Position>? _gpsSubscription;
  double _activeLegProgressMeters = 0;
  int _nearLegEndUpdates = 0;
  bool _isOffRoute = false;
  bool _isUpdatingGpsProgress = false;
  bool _isBuildingJourneys = false;

  bool get _isCommuting => _sheetView == _CommuteSheetView.activeLeg;
  bool get _isCommuteComplete =>
      _sheetView == _CommuteSheetView.commuteComplete;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant CommutePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _gpsSubscription?.cancel();
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
          originMainText: _originMainText,
          destinationMainText: _destinationMainText,
        ),
      ),
    );
    if (!mounted || result == null) return;

    await _clearJourneyMapOverlays();
    setState(() {
      _originPosition = result.originPosition;
      _destinationPosition = result.destinationPosition;
      _originMainText = result.originMainText;
      _destinationMainText = result.destinationMainText;
    });
    final origin = _originPosition;
    final destination = _destinationPosition;
    if (origin == null || destination == null) return;
    await _showOriginDestinationMarkersAndFit();
    await _runRaptor(origin, destination);
  }

  Future<void> _runRaptor(Position origin, Position destination) async {
    if (mounted) {
      setState(() {
        _isBuildingJourneys = true;
        _journeys = [];
        _selectedJourney = null;
        _sheetView = _CommuteSheetView.journeyOverviews;
      });
    }
    final preferences = CommutePreferencesService.instance;
    await preferences.initialize();
    final journeys = await RaptorPathfindingService.instance.findJourneys(
      originLat: origin.lat.toDouble(),
      originLng: origin.lng.toDouble(),
      destLat: destination.lat.toDouble(),
      destLng: destination.lng.toDouble(),
      penalizedVehicleTypes: preferences.penalizedVehicleTypes,
      walkingDistanceResolver: MapMatchingService.fetchWalkingDistances,
    );

    for (final journey in journeys) {
      await _enrichJourneyLegs(journey);
    }
    if (!mounted) return;

    setState(() {
      _journeys = journeys;
      _selectedJourney = null;
      _sheetView = _CommuteSheetView.journeyOverviews;
      _isBuildingJourneys = false;
    });
  }

  Future<void> _enrichJourneyLegs(Journey journey) async {
    for (final leg in journey.legs) {
      RouteMetadataResult? metadata;

      if (leg.vehicleType == VehicleType.train) {
        final trip = _findTripById(leg.tripId);
        final shapeCoordinates = trip == null
            ? const <Position>[]
            : _getTrainLegShapeCoordinates(trip, leg);
        if (shapeCoordinates.length < 2) {
          leg.fare = await FareCalculatorService.instance.calculateLegFare(leg);
          continue;
        }
        metadata = await MapMatchingService.fetchRouteMetadataResultTrain(
          leg.vehicleType,
          shapeCoordinates,
          routeId: leg.routeId,
        );
      } else if (leg.isWalking) {
        final start = _positionForLegStop(leg.fromStopId);
        final end = _positionForLegStop(leg.toStopId);
        if (start == null || end == null) continue;
        metadata = await MapMatchingService.fetchWalkingDirections(start, end);
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

      // assigns fare to the leg model fare field
      if (leg.vehicleType == VehicleType.train ||
          leg.vehicleType == VehicleType.jeep ||
          leg.vehicleType == VehicleType.ejeep ||
          leg.vehicleType == VehicleType.bus ||
          leg.vehicleType == VehicleType.uvExpress) {
        leg.fare = await FareCalculatorService.instance.calculateLegFare(leg);
      }
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

  Future<void> _updateJourneyPolylineOpacity({int? activeLegIndex}) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final style = mapboxMap.style;
    for (var index = 0; index < _drawnJourneyPolylineCount; index++) {
      final layerId = 'selected-journey-leg-layer-$index';
      if (!await style.styleLayerExists(layerId)) continue;

      final opacity = activeLegIndex == null
          ? 1.0
          : index < activeLegIndex
          ? 0.0
          : index == activeLegIndex
          ? 1.0
          : 0.25;
      await style.setStyleLayerProperty(layerId, 'line-opacity', opacity);
    }
  }

  Future<void> _updateLegPolyline(
    int legIndex,
    List<Position> coordinates,
  ) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || coordinates.length < 2) return;

    final sourceId = 'selected-journey-leg-source-$legIndex';
    if (!await mapboxMap.style.styleSourceExists(sourceId)) return;
    await mapboxMap.style.setStyleSourceProperty(
      sourceId,
      'data',
      jsonEncode({
        'type': 'Feature',
        'properties': {},
        'geometry': {
          'type': 'LineString',
          'coordinates': coordinates
              .map((position) => [position.lng, position.lat])
              .toList(),
        },
      }),
    );
  }

  Future<void> _startGpsTracking() async {
    await _gpsSubscription?.cancel();
    if (!await geo.Geolocator.isLocationServiceEnabled()) {
      _showGpsMessage('Please enable location services to track your commute.');
      return;
    }

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      _showGpsMessage('Location permission is required for GPS progress.');
      return;
    }

    _gpsSubscription = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(_handleGpsPosition, onError: _handleGpsError);
  }

  Future<void> _stopGpsTracking() async {
    await _gpsSubscription?.cancel();
    _gpsSubscription = null;
  }

  Future<void> _handleGpsPosition(geo.Position gpsPosition) async {
    final journey = _selectedJourney;
    if (!_isCommuting ||
        journey == null ||
        _isUpdatingGpsProgress ||
        gpsPosition.accuracy > 60) {
      return;
    }

    final coordinates = journey.legs[_activeLegIndex].coordinates;
    if (coordinates == null || coordinates.length < 2) return;

    _isUpdatingGpsProgress = true;
    try {
      final currentPosition = Position(
        gpsPosition.longitude,
        gpsPosition.latitude,
      );
      final progress = RouteProgressService.calculate(
        currentPosition,
        coordinates,
      );
      if (progress == null) return;

      if (progress.distanceFromRouteMeters > _offRouteDistanceMeters) {
        if (_isNearNextLeg(journey, currentPosition)) {
          await _advanceToLeg(journey, _activeLegIndex + 1);
        } else if (mounted && !_isOffRoute) {
          setState(() => _isOffRoute = true);
        }
        return;
      }

      if (progress.traveledMeters < _activeLegProgressMeters) return;
      _activeLegProgressMeters = progress.traveledMeters;
      if (mounted && _isOffRoute) setState(() => _isOffRoute = false);
      await _updateLegPolyline(
        _activeLegIndex,
        progress.remainingCoordinates,
      );

      _nearLegEndUpdates = progress.remainingMeters <= _legEndDistanceMeters
          ? _nearLegEndUpdates + 1
          : 0;
      if (_nearLegEndUpdates < 2) return;

      if (_activeLegIndex == journey.legs.length - 1) {
        await _completeCommute(journey);
      } else {
        await _advanceToLeg(journey, _activeLegIndex + 1);
      }
    } finally {
      _isUpdatingGpsProgress = false;
    }
  }

  bool _isNearNextLeg(Journey journey, Position currentPosition) {
    final nextIndex = _activeLegIndex + 1;
    if (nextIndex >= journey.legs.length) return false;
    final nextCoordinates = journey.legs[nextIndex].coordinates;
    if (nextCoordinates == null || nextCoordinates.length < 2) return false;
    final nextProgress = RouteProgressService.calculate(
      currentPosition,
      nextCoordinates,
    );
    return nextProgress != null &&
        nextProgress.distanceFromRouteMeters <= _nextLegDistanceMeters;
  }

  void _handleGpsError(Object error) {
    _showGpsMessage(
      'GPS tracking stopped. You can still change legs manually.',
    );
  }

  void _showGpsMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

    final camera = await mapboxMap.cameraForCoordinates(
      coordinates.map((position) => Point(coordinates: position)).toList(),
      MbxEdgeInsets(top: 120, left: 40, bottom: 300, right: 40),
      null,
      null,
    );
    await mapboxMap.flyTo(camera, MapAnimationOptions(duration: 500));
  }

  Future<void> _startCommute(Journey journey) {
    final originMainText = _originMainText ?? _originController.text.trim();
    final destinationMainText =
        _destinationMainText ?? _destinationController.text.trim();
    final labeledJourney = Journey(
      journey.legs,
      originMainText: originMainText.isEmpty ? null : originMainText,
      destinationMainText: destinationMainText.isEmpty
          ? null
          : destinationMainText,
    );
    return _activateJourney(labeledJourney, saveToHistory: true);
  }

  Future<void> _activateJourney(
    Journey journey, {
    required bool saveToHistory,
  }) async {
    if (journey.legs.isEmpty) return;
    setState(() {
      _selectedJourney = journey;
      _sheetView = _CommuteSheetView.activeLeg;
      _activeLegIndex = 0;
      _activeLegProgressMeters = 0;
      _nearLegEndUpdates = 0;
      _isOffRoute = false;
    });
    if (saveToHistory) {
      try {
        await RecentsService.instance.saveRecentCommute(journey);
      } catch (error) {
        debugPrint('Failed to save recent commute: $error');
        _showGpsMessage(
          'Your commute started, but it could not be added to recents.',
        );
      }
    }
    await _updateJourneyPolylineOpacity(activeLegIndex: 0);
    await _focusLegOnMap(journey.legs.first);
    await _startGpsTracking();
  }

  Future<void> _openRecentJourney(Journey journey) async {
    if (!mounted || journey.legs.isEmpty) return;
    await _stopGpsTracking();
    await _clearJourneyMapOverlays();
    await _endpointAnnotationManager?.deleteAll();

    final firstCoordinates = journey.legs.first.coordinates;
    final lastCoordinates = journey.legs.last.coordinates;
    _originController.text =
        journey.originMainText ?? journey.legs.first.fromStopName;
    _destinationController.text =
        journey.destinationMainText ?? journey.legs.last.toStopName;
    setState(() {
      _originPosition = firstCoordinates?.isNotEmpty == true
          ? firstCoordinates!.first
          : null;
      _destinationPosition = lastCoordinates?.isNotEmpty == true
          ? lastCoordinates!.last
          : null;
      _originMainText = journey.originMainText;
      _destinationMainText = journey.destinationMainText;
      _journeys = [journey];
      _selectedJourney = journey;
      _isBuildingJourneys = false;
    });

    await _showOriginDestinationMarkersAndFit();
    await _drawSelectedJourneyPolylines(journey);
    await _drawIntermediateStops(journey);
    await _activateJourney(journey, saveToHistory: false);
  }

  Future<void> _showLegAtIndex(Journey journey, int index) async {
    setState(() {
      _activeLegIndex = index;
      _activeLegProgressMeters = 0;
      _nearLegEndUpdates = 0;
      _isOffRoute = false;
    });
    final coordinates = journey.legs[index].coordinates;
    if (coordinates != null) await _updateLegPolyline(index, coordinates);
    await _updateJourneyPolylineOpacity(activeLegIndex: index);
    await _focusLegOnMap(journey.legs[index]);
  }

  Future<void> _advanceToLeg(Journey journey, int index) async {
    if (index >= journey.legs.length) return;
    await _showLegAtIndex(journey, index);
  }

  Future<void> _showJourneyDetails(Journey journey) async {
    await _stopGpsTracking();
    if (!mounted) return;
    setState(() {
      _sheetView = _CommuteSheetView.journeyDetails;
      _isOffRoute = false;
    });
    await _drawSelectedJourneyPolylines(journey);
  }

  Future<void> _completeCommute(Journey journey) async {
    await _stopGpsTracking();
    if (!mounted) return;
    setState(() {
      _sheetView = _CommuteSheetView.commuteComplete;
      _isOffRoute = false;
    });
    await _drawSelectedJourneyPolylines(journey);
  }

  Future<void> _resetCommute() async {
    await _stopGpsTracking();
    await _clearJourneyMapOverlays();
    await _endpointAnnotationManager?.deleteAll();
    if (!mounted) return;

    _originController.clear();
    _destinationController.clear();
    setState(() {
      _originPosition = null;
      _destinationPosition = null;
      _originMainText = null;
      _destinationMainText = null;
      _journeys = [];
      _selectedJourney = null;
      _sheetView = _CommuteSheetView.journeyOverviews;
      _activeLegIndex = 0;
      _activeLegProgressMeters = 0;
      _nearLegEndUpdates = 0;
      _isOffRoute = false;
    });
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

    final cameraOptions = await mapboxMap.cameraForCoordinates(
      [Point(coordinates: origin), Point(coordinates: destination)],
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
    final colorScheme = Theme.of(context).colorScheme;
    final transitLegs = journey.legs.where((leg) => !leg.isWalking).toList();
    final totalDistance = journey.legs.fold<double>(
      0,
      (total, leg) => total + (leg.distance ?? 0),
    );
    final walkingDistance = journey.legs
        .where((leg) => leg.isWalking)
        .fold<double>(0, (total, leg) => total + (leg.distance ?? 0));

    final totalFare = journey.legs.fold<double>(
      0,
      (total, leg) => total + (leg.fare ?? 0),
    );
    final hasDuration = journey.legs.any((leg) => leg.durationSeconds != null);
    final totalDuration = journey.legs.fold<double>(
      0,
      (total, leg) => total + (leg.durationSeconds ?? 0),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: colorScheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.24),
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: () async {
          setState(() {
            _selectedJourney = journey;
            _sheetView = _CommuteSheetView.journeyDetails;
          });
          await _drawSelectedJourneyPolylines(journey);
          await _drawIntermediateStops(journey);
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (
                            var index = 0;
                            index < transitLegs.length;
                            index++
                          ) ...[
                            _buildVehicleTypeIndicator(
                              transitLegs[index].vehicleType,
                            ),
                            if (index < transitLegs.length - 1)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 1,
                                  right: 1,
                                  bottom: 15,
                                ),
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  size: 17,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.schedule_outlined,
                          size: 15,
                          color: _journeyPolylineColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(
                            hasDuration ? totalDuration : null,
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildOverviewValue(
                        'Total distance',
                        _formatDistance(totalDistance),
                      ),
                    ),
                    _buildOverviewDivider(),
                    Expanded(
                      child: _buildOverviewValue(
                        'Walking distance',
                        _formatDistance(walkingDistance),
                      ),
                    ),
                    _buildOverviewDivider(),
                    Expanded(
                      child: _buildOverviewValue(
                        'Fare',
                        _formatFare(totalFare),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewValue(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _oneLineText(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 1),
        _oneLineText(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewDivider() {
    return Container(
      width: 1,
      height: 27,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _buildVehicleTypeIndicator(VehicleType vehicleType) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _journeyPolylineColor.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              _vehicleTypeIcon(vehicleType),
              size: 25,
              color: _journeyPolylineColor,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            vehicleType.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
      case VehicleType.ejeep:
        return Icons.electric_rickshaw;
      case VehicleType.tricycle:
        return Icons.moped;
      case VehicleType.uvExpress:
        return Icons.directions_car;
      case VehicleType.unknown:
        return Icons.directions_transit;
    }
  }

  String _formatDistance(double? distanceMeters) {
    if (distanceMeters == null) return '--';
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.toStringAsFixed(0)} m';
  }

  String _formatDuration(double? durationSeconds) {
    if (durationSeconds == null) return '--';
    if (durationSeconds >= 60) {
      return '${(durationSeconds / 60).round()} min';
    }
    return '${durationSeconds.toStringAsFixed(0)} sec';
  }

  String _formatFare(double? fare) {
    if (fare == null) return '--';
    return '₱${fare.toStringAsFixed(2)}';
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
    final totalDistance = legs.fold<double>(
      0,
      (total, leg) => total + (leg.distance ?? 0),
    );
    final totalDuration = legs.fold<double>(
      0,
      (total, leg) => total + (leg.durationSeconds ?? 0),
    );
    final totalFare = legs.fold<double>(
      0,
      (total, leg) => total + (leg.fare ?? 0),
    );
    final hasDistance = legs.any((leg) => leg.distance != null);
    final hasDuration = legs.any((leg) => leg.durationSeconds != null);
    final hasFare = legs.any((leg) => leg.fare != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to journeys',
              onPressed: () => setState(() {
                _selectedJourney = null;
                _sheetView = _CommuteSheetView.journeyOverviews;
              }),
            ),
            Expanded(
              child: _oneLineText(
                'Journey details',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _buildJourneySummary(
          durationSeconds: hasDuration ? totalDuration : null,
          distanceMeters: hasDistance ? totalDistance : null,
          fare: hasFare ? totalFare : null,
        ),
        const SizedBox(height: 14),

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
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: legs.isEmpty
                ? null
                : () => _startCommute(selectedJourney),
            icon: const Icon(Icons.navigation_rounded, size: 19),
            label: const Text('Start commute'),
          ),
        ),
      ],
    );
  }

  Widget _buildJourneySummaryItem(IconData icon, String value) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: _journeyPolylineColor),
          const SizedBox(width: 5),
          Flexible(
            child: _oneLineText(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJourneySummary({
    required double? durationSeconds,
    required double? distanceMeters,
    required double? fare,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildJourneySummaryItem(
            Icons.schedule_outlined,
            _formatDuration(durationSeconds),
          ),
          _buildJourneySummaryDivider(),
          _buildJourneySummaryItem(
            Icons.straighten_outlined,
            _formatDistance(distanceMeters),
          ),
          _buildJourneySummaryDivider(),
          _buildJourneySummaryItem(
            Icons.payments_outlined,
            _formatFare(fare),
          ),
        ],
      ),
    );
  }

  Widget _buildJourneySummaryDivider() {
    return Container(
      width: 1,
      height: 22,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _buildActiveLegView(Journey journey) {
    final leg = journey.legs[_activeLegIndex];
    final isFirst = _activeLegIndex == 0;
    final isLast = _activeLegIndex == journey.legs.length - 1;
    final colorScheme = Theme.of(context).colorScheme;
    final fromName = isFirst && _originController.text.isNotEmpty
        ? _originController.text
        : leg.fromStopName;
    final toName = isLast && _destinationController.text.isNotEmpty
        ? _destinationController.text
        : leg.toStopName;
    final routeName = leg.isWalking
        ? 'Walk'
        : (leg.routeLongName ?? 'Transit');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Journey details',
              onPressed: () => _showJourneyDetails(journey),
            ),
            Expanded(
              child: _oneLineText(
                'Leg ${_activeLegIndex + 1} of ${journey.legs.length}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ReportButton(
              routeId: leg.routeId,
              tripId: leg.tripId,
              fromStopId: leg.fromStopId,
              toStopId: leg.toStopId,
              vehicleType: leg.vehicleType.displayName,
              expectedFare: leg.fare,
              routeLongName: leg.routeLongName,
              fromStopName: isFirst ? _originController.text : leg.fromStopName,
              toStopName: isLast ? _destinationController.text : leg.toStopName,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _journeyPolylineColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _vehicleTypeIcon(leg.vehicleType),
                size: 20,
                color: _journeyPolylineColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _oneLineText(
                    routeName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _oneLineText(
                    '${_formatDuration(leg.durationSeconds)}  •  '
                    '${_formatDistance(leg.distance)}  •  '
                    '${_formatFare(leg.fare)}',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!leg.isWalking) ...[
          const SizedBox(height: 10),
          _oneLineText(
            'From: $fromName',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _oneLineText(
            'To: $toName',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
        if (leg.isWalking) ...[
          const SizedBox(height: 10),
          if (leg.steps?.isNotEmpty == true)
            for (var index = 0; index < leg.steps!.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _oneLineText(
                        leg.steps![index].instruction,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )
          else
            const Text(
              'Walk to the next stop.',
              style: TextStyle(fontSize: 13),
            ),
        ],
        if (_isOffRoute) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 17,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'You are off the active route.',
                    style: TextStyle(
                      color: colorScheme.onErrorContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: isFirst
                    ? null
                    : () => _showLegAtIndex(journey, _activeLegIndex - 1),
                child: const Text('Previous'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: isLast
                    ? () => _completeCommute(journey)
                    : () => _showLegAtIndex(journey, _activeLegIndex + 1),
                child: Text(isLast ? "I've arrived" : 'Next'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCommuteCompleteView(Journey journey) {
    final destination = _destinationController.text.isNotEmpty
        ? _destinationController.text
        : journey.legs.last.toStopName;
    final totalDistance = journey.legs.fold<double>(
      0,
      (total, leg) => total + (leg.distance ?? 0),
    );
    final totalDuration = journey.legs.fold<double>(
      0,
      (total, leg) => total + (leg.durationSeconds ?? 0),
    );
    final totalFare = journey.legs.fold<double>(
      0,
      (total, leg) => total + (leg.fare ?? 0),
    );

    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: Color(0xFFE0F2E1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, color: Colors.green, size: 40),
        ),
        const SizedBox(height: 12),
        Text(
          "You've arrived!",
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        _oneLineText(
          destination,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildCompletionValue(
              Icons.straighten,
              _formatDistance(totalDistance),
            ),
            _buildCompletionValue(
              Icons.schedule,
              _formatDuration(totalDuration),
            ),
            _buildCompletionValue(
              Icons.payments_outlined,
              _formatFare(totalFare),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _resetCommute,
            icon: const Icon(Icons.route_outlined),
            label: const Text('Plan another commute'),
          ),
        ),
      ],
    );
  }

  Widget _buildCompletionValue(IconData icon, String value) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(child: _oneLineText(value)),
        ],
      ),
    );
  }

  Widget _buildExpandedLegRow({
    required Leg leg,
    required bool isOrigin,
    required String stopName,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    const legColor = _journeyPolylineColor;
    final routeName = leg.isWalking ? 'Walk' : (leg.routeLongName ?? 'Transit');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 15,
                  bottom: 0,
                  width: leg.isWalking ? 6 : 4,
                  child: leg.isWalking
                      ? CustomPaint(
                          painter: _DottedProgressPainter(color: legColor),
                        )
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            color: legColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                ),
                Positioned(
                  top: 2,
                  child: Container(
                    width: isOrigin ? 15 : 13,
                    height: isOrigin ? 15 : 13,
                    decoration: BoxDecoration(
                      color: isOrigin
                          ? _journeyPolylineColor
                          : Colors.white,
                      shape: BoxShape.circle,
                      border: isOrigin
                          ? null
                          : Border.all(
                              color: _journeyPolylineColor,
                              width: 2,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _oneLineText(
                    stopName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildVehicleTypeIndicator(leg.vehicleType),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _oneLineText(
                                routeName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 5),
                              _oneLineText(
                                '${_formatDuration(leg.durationSeconds)}  •  '
                                '${_formatDistance(leg.distance)}  •  '
                                '${_formatFare(leg.fare)}',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Divider(height: 1, color: colorScheme.outlineVariant),
                ],
              ),
            ),
          ),
        ],
      ),
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
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: _journeyDestinationColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _oneLineText(
            destinationName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
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
          isStartingCommute: _isCommuting,
          onMapCreated: (mapboxMap) async {
            _mapboxMap = mapboxMap;
            _endpointAnnotationManager = null;
            _intermediateStopsAnnotationManager = null;
            await _showOriginDestinationMarkersAndFit();
            final journey = _selectedJourney;
            if (journey != null && (_isCommuting || _isCommuteComplete)) {
              await _drawSelectedJourneyPolylines(journey);
              await _drawIntermediateStops(journey);
              await _updateJourneyPolylineOpacity(
                activeLegIndex: _isCommuting ? _activeLegIndex : null,
              );
              if (_isCommuting) {
                await _focusLegOnMap(journey.legs[_activeLegIndex]);
              }
            }
          },
        ),

        if (_sheetView == _CommuteSheetView.journeyOverviews)
          Positioned(
            top: 40,
            left: 8,
            right: 8,
            child: LocationTextfield(
              originController: _originController,
              destinationController: _destinationController,
              readOnly: true,
              showClearButton: false,
              onOriginTap: () => _openInputPage(CommuteInputField.origin),
              onDestinationTap: () =>
                  _openInputPage(CommuteInputField.destination),
            ),
          ),
        if (_journeys.isNotEmpty &&
            !_isCommuting &&
            !_isCommuteComplete &&
            !_isBuildingJourneys)
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

              if (_sheetView == _CommuteSheetView.journeyOverviews)
                const RouteSuggestionButton(),
            ],
          )
        else if (_journeys.isNotEmpty &&
            (_isCommuting || _isCommuteComplete) &&
            !_isBuildingJourneys)
          DragScrollSheet(
            key: ValueKey(
              _isCommuteComplete
                  ? 'complete-commute-sheet'
                  : 'active-commute-sheet',
            ),
            initialChildSize: _isCommuteComplete ? 0.36 : 0.22,
            minChildSize: _isCommuteComplete ? 0.25 : 0.1,
            maxChildSize: _isCommuteComplete ? 0.45 : 0.22,
            snapSizes: _isCommuteComplete
                ? const [0.25, 0.36, 0.45]
                : const [0.1, 0.22],
            children: [
              if (_isCommuteComplete)
                _buildCommuteCompleteView(_selectedJourney!)
              else
                _buildActiveLegView(_selectedJourney!),
            ],
          ),

        if (_isBuildingJourneys)
          Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}

class _DottedProgressPainter extends CustomPainter {
  final Color color;

  const _DottedProgressPainter({this.color = Colors.grey});

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final paint = ui.Paint()..color = color;
    const radius = 2.0;
    const gap = 8.0;
    final centerX = size.width / 2;

    for (var y = radius; y < size.height; y += radius * 2 + gap) {
      canvas.drawCircle(ui.Offset(centerX, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedProgressPainter oldDelegate) =>
      oldDelegate.color != color;
}
