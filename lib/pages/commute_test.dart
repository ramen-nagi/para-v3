import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/universal_map_tile.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/raptor_pathfinding_service.dart';

class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;
  final String fullText;

  PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.fullText,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    final placePrediction = json['placePrediction'];
    final structuredFormat = placePrediction['structuredFormat'];

    return PlaceSuggestion(
      placeId: placePrediction['placeId'] ?? '',
      mainText: structuredFormat?['mainText']?['text'] ?? '',
      secondaryText: structuredFormat?['secondaryText']?['text'] ?? '',
      fullText: placePrediction['text']?['text'] ?? '',
    );
  }
}

class Commute extends StatefulWidget {
  const Commute({super.key});

  @override
  State<Commute> createState() => _CommuteState();
}

class _CommuteState extends State<Commute> {
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _circleAnnotationManager;
  final SearchController _originSearchController = SearchController();
  final SearchController _destinationSearchController = SearchController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  PlaceSuggestion? _originSelected;
  PlaceSuggestion? _destinationSelected;
  Position? _originLatLng;
  Position? _destinationLatLng;

  int _journeyCount = 0;
  bool _isRaptorLoading = false;
  int _raptorRequestId = 0;
  int _originGeocodeRequestId = 0;
  int _destinationGeocodeRequestId = 0;
  bool _isSheetExpanded = false;
  bool _isShowingSheet = false;

  Timer? _debounce;
  Completer<List<PlaceSuggestion>>? _pendingSuggestions;
  String? _sessionToken;

  static const int _maxResults = 5;
  static final RegExp _metroManilaRegex = RegExp(
    r'Metro Manila',
    caseSensitive: false,
  );

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    await _addOriginDestMarker(_originLatLng, _destinationLatLng);
    await _fitOriginDestInCamera(_originLatLng, _destinationLatLng);
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
          circleColor: 0xFF2196F3,
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

  Future<void> _fitOriginDestInCamera(
    Position? originLatLng,
    Position? destinationLatLng,
  ) async {
    final map = _mapboxMap;
    if (map == null || originLatLng == null || destinationLatLng == null) {
      return;
    }

    final cameraOptions = await map.cameraForCoordinates(
      [
        Point(coordinates: originLatLng),
        Point(coordinates: destinationLatLng),
      ],
      MbxEdgeInsets(top: 300, left: 60, bottom: 300, right: 60),
      null,
      null,
    );
    await map.easeTo(
      cameraOptions,
      MapAnimationOptions(duration: 750),
    );
  }

  void _toggleDraggableScrollableSheetHeight() {
    final targetSize = _isSheetExpanded ? 0.1 : 0.8;
    _sheetController.animateTo(
      targetSize,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
    setState(() => _isSheetExpanded = !_isSheetExpanded);
  }

  String _generateSessionToken() {
    final rng = Random.secure();
    String hex(int bytes) => List.generate(
      bytes,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${hex(4)}-${hex(2)}-4${hex(1).substring(1)}-'
        '${(rng.nextInt(4) + 8).toRadixString(16)}${hex(1).substring(1)}-${hex(6)}';
  }

  Future<List<PlaceSuggestion>> _getDebouncedSuggestions(String query) {
    _debounce?.cancel();
    final pendingSuggestions = _pendingSuggestions;
    if (pendingSuggestions != null && !pendingSuggestions.isCompleted) {
      pendingSuggestions.complete(<PlaceSuggestion>[]);
    }

    if (query.trim().isEmpty) {
      return Future.value(<PlaceSuggestion>[]);
    }

    final completer = Completer<List<PlaceSuggestion>>();
    _pendingSuggestions = completer;
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final suggestions = await _fetchAutocompleteSuggestions(query);
      if (!completer.isCompleted) {
        completer.complete(suggestions);
      }
    });
    return completer.future;
  }

  Future<List<PlaceSuggestion>> _fetchAutocompleteSuggestions(
    String query,
  ) async {
    final apiKey = dotenv.env['MAPS_PLATFORM_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('MAPS_PLATFORM_KEY is missing from .env');
      return [];
    }

    _sessionToken ??= _generateSessionToken();

    try {
      final response = await http.post(
        Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask':
              'suggestions.placePrediction.placeId,'
              'suggestions.placePrediction.text,'
              'suggestions.placePrediction.structuredFormat',
        },
        body: jsonEncode({
          'input': query,
          'includedRegionCodes': ['ph'],
          'locationRestriction': {
            'rectangle': {
              'low': {
                'latitude': 14.349036807202772,
                'longitude': 120.89298105551104,
              },
              'high': {
                'latitude': 14.788314817021137,
                'longitude': 121.14086007810187,
              },
            },
          },
          'sessionToken': _sessionToken,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('Places Autocomplete error: ${response.body}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawSuggestions = (data['suggestions'] as List?) ?? [];
      final parsed = rawSuggestions
          .map(
            (suggestion) =>
                PlaceSuggestion.fromJson(suggestion as Map<String, dynamic>),
          )
          .where(
            (suggestion) => _metroManilaRegex.hasMatch(suggestion.fullText),
          )
          .take(_maxResults)
          .toList();

      return parsed;
    } catch (e) {
      debugPrint('Places Autocomplete exception: $e');
      return [];
    }
  }

  Future<void> _geocodeSelected(
    PlaceSuggestion suggestion, {
    required bool isOrigin,
    required int requestId,
  }) async {
    final apiKey = dotenv.env['MAPS_PLATFORM_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[Geocode] MAPS_PLATFORM_KEY is missing from .env');
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(
          'https://places.googleapis.com/v1/places/${suggestion.placeId}',
        ),
        headers: {
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': 'location',
        },
      );

      if (response.statusCode != 200) {
        debugPrint('[Geocode] Error response: ${response.body}');
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final location = data['location'] as Map<String, dynamic>?;
      if (location == null) {
        debugPrint(
          '[Geocode] No location in response for placeId: ${suggestion.placeId}',
        );
        return;
      }

      final lat = (location['latitude'] as num).toDouble();
      final lng = (location['longitude'] as num).toDouble();
      if (!mounted) return;
      if (isOrigin && requestId != _originGeocodeRequestId) return;
      if (!isOrigin && requestId != _destinationGeocodeRequestId) return;

      setState(() {
        if (isOrigin) {
          _originLatLng = Position(lng, lat);
        } else {
          _destinationLatLng = Position(lng, lat);
        }
      });

      await _addOriginDestMarker(_originLatLng, _destinationLatLng);
      await _fitOriginDestInCamera(_originLatLng, _destinationLatLng);

      if (_originLatLng != null && _destinationLatLng != null) {
        _runRaptorPathfinding();
      }
    } catch (e) {
      debugPrint('[Geocode] Exception while fetching place details: $e');
    }
  }

  Future<void> _runRaptorPathfinding() async {
    final origin = _originLatLng;
    final destination = _destinationLatLng;

    if (origin == null || destination == null) {
      print('Select and geocode both origin and destination first.');
      return;
    }
    if (!GtfsNetworkService.instance.isLoaded) {
      print('GTFS dataset has not loaded yet.');
      setState(() => _isRaptorLoading = false);
      return;
    }

    final requestId = ++_raptorRequestId;
    setState(() => _isRaptorLoading = true);
    await Future<void>.delayed(Duration.zero);
    if (!mounted || requestId != _raptorRequestId) return;

    final journeys = RaptorPathfindingService.instance.findJourneys(
      originLat: origin.lat.toDouble(),
      originLng: origin.lng.toDouble(),
      destLat: destination.lat.toDouble(),
      destLng: destination.lng.toDouble(),
    );

    if (!mounted || requestId != _raptorRequestId) return;
    setState(() {
      _journeyCount = journeys.length;
      _isRaptorLoading = false;
    });

    if (journeys.isEmpty) {
      print('No journeys found.');
      return;
    }

    for (var journeyIndex = 0; journeyIndex < journeys.length; journeyIndex++) {
      final journey = journeys[journeyIndex];
      print('Journey ${journeyIndex + 1}');
      for (var legIndex = 0; legIndex < journey.legs.length; legIndex++) {
        final leg = journey.legs[legIndex];
        if (leg is WalkLeg) {
          print('${legIndex + 1}. Walk');
          print('from ${leg.fromStopName}');
          print('to ${leg.toStopName}');
        } else if (leg is TransitLeg) {
          print(
            '${legIndex + 1}. '
            '${_getVehicleTypeString(leg.vehicleType)} (${leg.routeLongName})',
          );
          print('from ${leg.fromStopName}');
          print('to ${leg.toStopName}');
        }
      }
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
  void dispose() {
    _debounce?.cancel();
    final pendingSuggestions = _pendingSuggestions;
    if (pendingSuggestions != null && !pendingSuggestions.isCompleted) {
      pendingSuggestions.complete(<PlaceSuggestion>[]);
    }
    _originSearchController.dispose();
    _destinationSearchController.dispose();
    _sheetController.dispose();
    super.dispose();
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
              final suggestions = await _getDebouncedSuggestions(query);
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

  Widget _draggableSheet() {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.1,
      minChildSize: 0.1,
      maxChildSize: 0.8,
      snapSizes: const [0.1, 0.8],
      snap: true,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(10),
            ),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(8),
            children: [
              GestureDetector(
                onTap: _toggleDraggableScrollableSheetHeight,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              if (_isRaptorLoading)
                const Center(child: CircularProgressIndicator())
              else
                Text(
                  '$_journeyCount '
                  '${_journeyCount == 1 ? 'Journey' : 'Journeys'} Found',
                ),
              const SizedBox(height: 20),
              const Divider(height: 10),
              // TODO: Add journey cards
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          UniversalMapTile(
            key: const PageStorageKey('CommuteTestMapTile'),
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
                          _journeyCount = 0;
                          _raptorRequestId++;
                          _isShowingSheet =
                              _originSearchController.text.isNotEmpty &&
                              _destinationSearchController.text.isNotEmpty;
                          _isRaptorLoading = _isShowingSheet;
                        });
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
                          _journeyCount = 0;
                          _raptorRequestId++;
                          _isShowingSheet =
                              _originSearchController.text.isNotEmpty &&
                              _destinationSearchController.text.isNotEmpty;
                          _isRaptorLoading = _isShowingSheet;
                        });
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

          if (_isShowingSheet) _draggableSheet(),
        ],
      ),
    );
  }
}
