import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/universal_map_tile.dart';
import 'package:para_v3/module/drag_scroll_sheet.dart';
import 'package:para_v3/services/autocomplete_geocoding.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/map_matching_service.dart';
import 'package:para_v3/services/raptor_pathfinding_service.dart';

class CommutePage extends StatefulWidget {
  const CommutePage({super.key});

  @override
  State<CommutePage> createState() => _CommutePageState();
}

class _CommutePageState extends State<CommutePage> {
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _circleAnnotationManager;
  CircleAnnotationManager? _stopCircleAnnotationManager;
  final SearchController _originSearchController = SearchController();
  final SearchController _destinationSearchController = SearchController();

  PlaceSuggestion? _originSelected;
  PlaceSuggestion? _destinationSelected;
  Position? _originLatLng;
  Position? _destinationLatLng;

  List<Journey> _journeys = [];
  Journey? _selectedJourney;
  int _drawnJourneyLegCount = 0;
  int _polylineRenderRequestId = 0;

  bool _isRaptorLoading = false;
  int _raptorRequestId = 0;
  int _originGeocodeRequestId = 0;
  int _destinationGeocodeRequestId = 0;
  bool _isShowingSheet = false;
  bool _isStartingCommute = false;
  int _currentLegIndex = 0;

  final _autocompleteGeocoding = AutocompleteGeocodingService();

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    await _addOriginDestMarker(_originLatLng, _destinationLatLng);
    await _fitCoordinatesInCamera(_originLatLng, _destinationLatLng);
  }

  Future<void> _addOriginDestMarker(
    Position? originLatLng,
    Position? destinationLatLng,
  ) async {
    final map = _mapboxMap;
    if (map == null) return;

    _circleAnnotationManager ??= await map.annotations
        .createCircleAnnotationManager();
    await _circleAnnotationManager!.deleteAll();

    final annotations = <CircleAnnotationOptions>[];
    if (originLatLng != null) {
      annotations.add(
        CircleAnnotationOptions(
          geometry: Point(coordinates: originLatLng),
          circleRadius: 8.0,
          circleColor: 0xFF0700ff,
          circleStrokeWidth: 2.0,
          circleStrokeColor: 0xFFFFFFFF,
        ),
      );
    }
    if (destinationLatLng != null) {
      annotations.add(
        CircleAnnotationOptions(
          geometry: Point(coordinates: destinationLatLng),
          circleRadius: 8.0,
          circleColor: 0xFFF44336,
          circleStrokeWidth: 2.0,
          circleStrokeColor: 0xFFFFFFFF,
        ),
      );
    }

    if (annotations.isNotEmpty) {
      await _circleAnnotationManager!.createMulti(annotations);
    }
  }

  Future<void> _addStopsBetweenOriginDest() async {
    final map = _mapboxMap;
    final journey = _selectedJourney;
    if (map == null || journey == null) return;

    _stopCircleAnnotationManager ??= await map.annotations
        .createCircleAnnotationManager();
    await _stopCircleAnnotationManager!.deleteAll();

    final stopPositions = <String, Position>{};
    for (final leg in journey.legs) {
      if (leg is! TransitLeg) continue;

      final trip = MapMatchingService.getTripById(leg.tripId);
      if (trip == null) continue;

      for (final stop in MapMatchingService.getStopsAndStopTimes(trip)) {
        if (stop.stopId == leg.fromStopId || stop.stopId == leg.toStopId) {
          stopPositions.putIfAbsent(
            stop.stopId,
            () => Position(stop.stopLon, stop.stopLat),
          );
        }
      }
    }

    if (stopPositions.isEmpty) return;
    await _stopCircleAnnotationManager!.createMulti(
      stopPositions.values
          .map(
            (position) => CircleAnnotationOptions(
              geometry: Point(coordinates: position),
              circleRadius: 5.0,
              circleColor: 0xFF2196F3,
              circleStrokeWidth: 2.0,
              circleStrokeColor: 0xFFFFFBFE,
            ),
          )
          .toList(),
    );
  }

  Future<void> _fitCoordinatesInCamera(
    Position? firstPosition,
    Position? secondPosition,
  ) async {
    final map = _mapboxMap;
    if (map == null || firstPosition == null || secondPosition == null) {
      return;
    }

    final cameraOptions = await map.cameraForCoordinates(
      [
        Point(coordinates: firstPosition),
        Point(coordinates: secondPosition),
      ],
      MbxEdgeInsets(top: 200, left: 60, bottom: 200, right: 60),
      null,
      null,
    );
    await map.easeTo(
      cameraOptions,
      MapAnimationOptions(duration: 750),
    );
  }

  Future<void> _geocodeSelected(
    PlaceSuggestion suggestion, {
    required bool isOrigin,
    required int requestId,
  }) async {
    final position = await _autocompleteGeocoding.geocode(suggestion);
    if (!mounted || position == null) return;
    if (isOrigin && requestId != _originGeocodeRequestId) return;
    if (!isOrigin && requestId != _destinationGeocodeRequestId) return;

    setState(() {
      if (isOrigin) {
        _originLatLng = position;
      } else {
        _destinationLatLng = position;
      }
    });

    await _addOriginDestMarker(_originLatLng, _destinationLatLng);
    await _fitCoordinatesInCamera(_originLatLng, _destinationLatLng);

    if (_originLatLng != null && _destinationLatLng != null) {
      final raptorRequestId = ++_raptorRequestId;
      setState(() => _isRaptorLoading = true);
      final journeys = await _runRaptorPathfinding();
      if (!mounted || raptorRequestId != _raptorRequestId) return;
      setState(() {
        _journeys = journeys;
        _selectedJourney = null;
        _isStartingCommute = false;
        _currentLegIndex = 0;
        _isRaptorLoading = false;
      });
    }
  }

  Future<List<Journey>> _runRaptorPathfinding() async {
    final origin = _originLatLng;
    final destination = _destinationLatLng;

    if (origin == null || destination == null) {
      return [];
    }
    if (!GtfsNetworkService.instance.isLoaded) {
      return [];
    }

    await Future<void>.delayed(Duration.zero);

    return RaptorPathfindingService.instance.findJourneys(
      originLat: origin.lat.toDouble(),
      originLng: origin.lng.toDouble(),
      destLat: destination.lat.toDouble(),
      destLng: destination.lng.toDouble(),
    );
  }

  Future<void> _drawSelectedJourneyPolylines(Journey journey) async {
    final map = _mapboxMap;
    if (map == null) return;

    await _clearJourneyPolylines();
    final renderRequestId = _polylineRenderRequestId;

    for (var index = 0; index < journey.legs.length; index++) {
      final leg = journey.legs[index];

      final sourceId = 'commute-leg-source-$index';
      final layerId = 'commute-leg-layer-$index';
      if (leg is WalkLeg) {
        final start = _positionForLegStop(leg.fromStopId);
        final end = _positionForLegStop(leg.toStopId);
        if (start == null || end == null) continue;

        final positions = await MapMatchingService.fetchWalkingRoute(
          start,
          end,
        );
        if (renderRequestId != _polylineRenderRequestId) return;
        await MapMatchingService.drawWalkPolyline(
          map,
          positions,
          sourceId: sourceId,
          layerId: layerId,
        );
        continue;
      }
      if (leg is! TransitLeg) continue;

      if (leg.vehicleType == VehicleType.train) {
        final trip = MapMatchingService.getTripById(leg.tripId);
        if (trip != null) {
          await MapMatchingService.drawShapePolyline(
            map,
            trip,
            startStop: leg.fromStopName,
            endStop: leg.toStopName,
            sourceId: sourceId,
            layerId: layerId,
            fitCamera: false,
          );
          if (renderRequestId != _polylineRenderRequestId) return;
        }
        continue;
      }

      final positions = await MapMatchingService.fetchMapMatching(
        profile: 'driving-traffic',
        tripId: leg.tripId,
        startStop: leg.fromStopName,
        endStop: leg.toStopName,
      );
      if (renderRequestId != _polylineRenderRequestId) return;
      await MapMatchingService.drawRoutePolyline(
        map,
        positions,
        sourceId: sourceId,
        layerId: layerId,
        fitCamera: false,
      );
    }

    if (renderRequestId == _polylineRenderRequestId) {
      _drawnJourneyLegCount = journey.legs.length;
    }
  }

  Future<void> _clearJourneyPolylines() async {
    _polylineRenderRequestId++;
    final map = _mapboxMap;
    if (map == null) {
      _drawnJourneyLegCount = 0;
      return;
    }

    final style = map.style;
    for (var index = 0; index < _drawnJourneyLegCount; index++) {
      final sourceId = 'commute-leg-source-$index';
      final layerId = 'commute-leg-layer-$index';
      if (await style.styleLayerExists(layerId)) {
        await style.removeStyleLayer(layerId);
      }
      if (await style.styleSourceExists(sourceId)) {
        await style.removeStyleSource(sourceId);
      }
    }
    _drawnJourneyLegCount = 0;
  }

  Position? _positionForLegStop(String stopId) {
    if (stopId == '__ORIGIN__') return _originLatLng;
    if (stopId == '__DESTINATION__') return _destinationLatLng;

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

  Future<void> _fitLegInCamera() async {
    final journey = _selectedJourney;
    if (journey == null ||
        _currentLegIndex < 0 ||
        _currentLegIndex >= journey.legs.length) {
      return;
    }

    final leg = journey.legs[_currentLegIndex];
    await _fitCoordinatesInCamera(
      _positionForLegStop(leg.fromStopId),
      _positionForLegStop(leg.toStopId),
    );
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

  Widget _buildSearchAnchorBar(
    SearchController controller,
    Widget icon1,
    IconData icon2,
    String hintText,
    Future<void> Function(PlaceSuggestion) onSuggestionSelected,
  ) {
    return Row(
      children: [
        const SizedBox(width: 8),
        icon1,
        Expanded(
          child: SearchAnchor.bar(
            searchController: controller,
            barHintText: hintText,
            barElevation: const WidgetStatePropertyAll(0),
            suggestionsBuilder: (context, controller) async {
              final query = controller.text;
              final suggestions = await _autocompleteGeocoding
                  .getDebouncedSuggestions(query);
              if (controller.text != query) return const [];

              return suggestions
                  .map(
                    (suggestion) => ListTile(
                      onTap: () async {
                        controller.closeView(suggestion.mainText);
                        FocusScope.of(context).unfocus();
                        await onSuggestionSelected(suggestion);
                      },
                      title: Text(suggestion.mainText),
                      subtitle: Text(suggestion.secondaryText),
                    ),
                  )
                  .toList();
            },
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: Icon(icon2),
        ),
      ],
    );
  }

  List<Widget> _buildJourneySheetChildren() {
    return [
      Text('${_journeys.length} Journeys Found'),
      const SizedBox(height: 20),
      const Divider(height: 10),
      for (final journey in _journeys)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            setState(() {
              _selectedJourney = journey;
              _isStartingCommute = false;
              _currentLegIndex = 0;
            });
            await _addStopsBetweenOriginDest();
            await _drawSelectedJourneyPolylines(journey);
          },
          child: _buildJourneyCard(
            journey,
            isSelected: identical(_selectedJourney, journey),
          ),
        ),
    ];
  }

  Widget _buildJourneyCard(Journey journey, {required bool isSelected}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total distance'),
                Text('Walking distance'),
                Text('Total fare'),
              ],
            ),
            const SizedBox(height: 12),

            if (isSelected) ...[
              _buildJourneyDetails(journey),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startCommute,
                  icon: const Icon(Icons.directions_outlined),
                  label: const Text(
                    'Start Commute',
                    style: TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ] else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final leg in journey.legs)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          leg is TransitLeg
                              ? _getVehicleTypeString(leg.vehicleType)
                              : 'Walk',
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartCommuteCard(Journey journey) {
    final leg = journey.legs[_currentLegIndex];
    final vehicleType = leg is TransitLeg
        ? _getVehicleTypeString(leg.vehicleType)
        : 'Walk';
    final routeLongName = leg is TransitLeg ? leg.routeLongName : 'Walking';
    final legFromStop = leg is TransitLeg
        ? leg.fromStopName
        : (leg as WalkLeg).fromStopName;
    final legToStop = leg is TransitLeg
        ? leg.toStopName
        : (leg as WalkLeg).toStopName;
    final fromStop = _currentLegIndex == 0
        ? (_originSelected?.mainText ?? legFromStop)
        : legFromStop;
    final toStop = _currentLegIndex == journey.legs.length - 1
        ? (_destinationSelected?.mainText ?? legToStop)
        : legToStop;

    return Positioned(
      bottom: 10,
      right: 10,
      left: 10,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _currentLegIndex > 0
                        ? () async {
                            setState(() => _currentLegIndex--);
                            await _fitLegInCamera();
                          }
                        : null,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Previous'),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Leg ${_currentLegIndex + 1} of ${journey.legs.length}',
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _currentLegIndex < journey.legs.length - 1
                        ? () async {
                            setState(() => _currentLegIndex++);
                            await _fitLegInCamera();
                          }
                        : null,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('Distance'), Text('Fare')],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(vehicleType),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          routeLongName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'From: $fromStop',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'To: $toStop',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startCommute() async {
    setState(() {
      _isStartingCommute = true;
      _currentLegIndex = 0;
    });
    await _fitLegInCamera();
  }

  Widget _buildRaptorLoadingIndicator() {
    return const Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: ColoredBox(
            color: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJourneyDetails(Journey journey) {
    final destinationText = _destinationSelected?.mainText ?? 'Destination';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTimelineStopRow(
          _originSelected?.mainText ?? 'Origin',
          color: Colors.blue,
        ),
        for (var index = 0; index < journey.legs.length; index++) ...[
          _buildJourneyLegRow(journey.legs[index]),
          _buildTimelineStopRow(
            index == journey.legs.length - 1
                ? destinationText
                : _legToStopName(journey.legs[index]),
            color: index == journey.legs.length - 1 ? Colors.red : Colors.grey,
          ),
        ],
      ],
    );
  }

  Widget _buildTimelineStopRow(String stopName, {required Color color}) {
    return Row(
      children: [
        Icon(Icons.location_on, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            stopName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildJourneyLegRow(Leg leg) {
    final vehicleLabel = leg is TransitLeg
        ? _getVehicleTypeString(leg.vehicleType)
        : 'Walk';

    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
      child: Row(
        children: [
          const Column(
            children: [
              Icon(Icons.circle, size: 5, color: Colors.grey),
              SizedBox(height: 4),
              Icon(Icons.circle, size: 5, color: Colors.grey),
            ],
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(vehicleLabel),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Text('Distance')),
          const Text('Fare'),
        ],
      ),
    );
  }

  String _legToStopName(Leg leg) {
    if (leg is TransitLeg) return leg.toStopName;
    if (leg is WalkLeg) return leg.toStopName;
    return 'Stop';
  }

  @override
  void dispose() {
    _autocompleteGeocoding.dispose();
    _originSearchController.dispose();
    _destinationSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          UniversalMapTile(
            key: const PageStorageKey('CommutePageTestMapTile'),
            initialZoom: 12.0,
            onMapCreated: _onMapCreated,
          ),

          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Card(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 2),
                    _buildSearchAnchorBar(
                      _originSearchController,
                      const Icon(Icons.location_on, color: Colors.blue),
                      Icons.report_problem_outlined,
                      'Origin Location',
                      (suggestion) async {
                        final requestId = ++_originGeocodeRequestId;
                        setState(() {
                          _originSelected = suggestion;
                          _originLatLng = null;
                          _journeys = [];
                          _raptorRequestId++;
                          _isStartingCommute = false;
                          _currentLegIndex = 0;
                          _isShowingSheet =
                              _originSearchController.text.isNotEmpty &&
                              _destinationSearchController.text.isNotEmpty;
                          _isRaptorLoading = _isShowingSheet;
                        });
                        await _clearJourneyPolylines();
                        await _addOriginDestMarker(
                          _originLatLng,
                          _destinationLatLng,
                        );
                        await _geocodeSelected(
                          suggestion,
                          isOrigin: true,
                          requestId: requestId,
                        );
                      },
                    ),
                    const SizedBox(height: 5),
                    _buildSearchAnchorBar(
                      _destinationSearchController,
                      const Icon(Icons.location_on, color: Colors.red),
                      Icons.swap_vert,
                      'Destination',
                      (suggestion) async {
                        final requestId = ++_destinationGeocodeRequestId;
                        setState(() {
                          _destinationSelected = suggestion;
                          _destinationLatLng = null;
                          _journeys = [];
                          _raptorRequestId++;
                          _isStartingCommute = false;
                          _currentLegIndex = 0;
                          _isShowingSheet =
                              _originSearchController.text.isNotEmpty &&
                              _destinationSearchController.text.isNotEmpty;
                          _isRaptorLoading = _isShowingSheet;
                        });
                        await _clearJourneyPolylines();
                        await _addOriginDestMarker(
                          _originLatLng,
                          _destinationLatLng,
                        );
                        await _geocodeSelected(
                          suggestion,
                          isOrigin: false,
                          requestId: requestId,
                        );
                      },
                    ),
                    const SizedBox(height: 2),
                  ],
                ),
              ),
            ),
          ),

          if (_isStartingCommute && _selectedJourney != null)
            _buildStartCommuteCard(_selectedJourney!)
          else if (_isShowingSheet)
            DragScrollSheet(children: _buildJourneySheetChildren()),

          if (_isRaptorLoading) _buildRaptorLoadingIndicator(),
        ],
      ),
    );
  }
}
