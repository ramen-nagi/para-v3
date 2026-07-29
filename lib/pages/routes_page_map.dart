import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/module/universal_map_tile.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

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
  // ignore: unused_field
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _circleAnnotationManager;

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

  String _getTripHeader(TripsModel trip) {
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

            _drawStopMarkersOnMap(trip);

            //TOOD: Modify card widget to display all intermediate stops in an ordered list

            if (widget.route.vehicleType == VehicleType.train) {
              _drawTripShapePolylineOnMap(trip);
            } else {
              _drawTripPolylineOnMap(trip);
            }
          },
        ),
      );
    }).toList();
  }

  List<StopsAndStopTimesModel> _getStopsAndStopTimes(TripsModel trip) {
    if (trip.stopTimes.isEmpty) return [];

    return List<StopsAndStopTimesModel>.from(trip.stopTimes)
      ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
  }

  Future<void> _drawStopMarkersOnMap(TripsModel trip) async {
    if (_mapboxMap == null) return;

    _circleAnnotationManager ??= await _mapboxMap!.annotations
        .createCircleAnnotationManager();

    await _circleAnnotationManager!.deleteAll();

    final stopTimes = _getStopsAndStopTimes(trip);
    if (stopTimes.isEmpty) return;

    final List<CircleAnnotationOptions> annotations = [];

    for (int i = 0; i < stopTimes.length; i++) {
      final stop = stopTimes[i];
      final bool isStart = i == 0;
      final bool isEnd = i == stopTimes.length - 1;

      int circleColor = 0xFF1976D2;

      if (isStart) {
        circleColor = 0xFF388E3C;
      } else if (isEnd) {
        circleColor = 0xFFD32F2F;
      }

      final options = CircleAnnotationOptions(
        geometry: Point(
          coordinates: Position(stop.stopLon, stop.stopLat),
        ),
        circleRadius: isStart || isEnd ? 8.0 : 5.0,
        circleColor: circleColor,
        circleStrokeWidth: 2.0,
        circleStrokeColor: 0xFFFFFFFF,
      );

      annotations.add(options);
    }

    await _circleAnnotationManager!.createMulti(annotations);
  }

  List<Position> _getSampleStopsCoordinates(TripsModel trip) {
    final stopTimes = _getStopsAndStopTimes(trip);
    if (stopTimes.isEmpty) return [];

    if (stopTimes.length <= 100) {
      return stopTimes.map((st) => Position(st.stopLon, st.stopLat)).toList();
    }

    final List<StopsAndStopTimesModel> selectedStops = [];

    final first5Stops = stopTimes.take(5).toList();
    selectedStops.addAll(first5Stops);

    final last5Stops = stopTimes.skip(stopTimes.length - 5).toList();
    selectedStops.addAll(last5Stops);

    final int minSeq = first5Stops.last.stopSequence;
    final int maxSeq = last5Stops.first.stopSequence;
    final int totalRange = maxSeq - minSeq;

    final double step = totalRange / 91.0;

    StopsAndStopTimesModel getClosestStop(int targetSeq) {
      return stopTimes.reduce((a, b) {
        final aDiff = (a.stopSequence - targetSeq).abs();
        final bDiff = (b.stopSequence - targetSeq).abs();
        return aDiff <= bDiff ? a : b;
      });
    }

    for (int i = 1; i <= 90; i++) {
      final int targetSeq = (minSeq + (i * step)).round();
      selectedStops.add(getClosestStop(targetSeq));
    }

    return selectedStops.map((st) => Position(st.stopLon, st.stopLat)).toList();
  }

  Future<void> _drawTripPolylineOnMap(TripsModel trip) async {
    if (_mapboxMap == null) return;

    final coordinates = _getSampleStopsCoordinates(trip);
    if (coordinates.isEmpty) return;

    final String formattedCoords = coordinates
        .map((pos) => '${pos.lng},${pos.lat}')
        .join(';');

    final String radiusesParam = List.filled(
      coordinates.length,
      '25',
    ).join(';');

    final String? accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('Error: MAPBOX_ACCESS_TOKEN is missing or null.');
      return;
    }

    final Uri uri = Uri.parse(
      'https://api.mapbox.com/matching/v5/mapbox/driving/$formattedCoords'
      '?steps=true'
      '&radiuses=$radiusesParam'
      '&geometries=geojson'
      '&overview=full'
      '&tidy=true'
      '&access_token=$accessToken',
    );

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final matchings = data['matchings'] as List?;

        if (matchings != null && matchings.isNotEmpty) {
          final List<Position> linePositions = [];

          for (final match in matchings) {
            final geometry = match['geometry'];
            final List<dynamic> matchedCoords = geometry['coordinates'];
            for (final c in matchedCoords) {
              linePositions.add(Position(c[0] as double, c[1] as double));
            }
          }

          if (linePositions.isEmpty) return;

          final style = _mapboxMap!.style;

          if (await style.styleLayerExists('route-line-layer')) {
            await style.removeStyleLayer('route-line-layer');
          }
          if (await style.styleSourceExists('route-line-source')) {
            await style.removeStyleSource('route-line-source');
          }

          await style.addSource(
            GeoJsonSource(
              id: 'route-line-source',
              data: jsonEncode({
                "type": "Feature",
                "properties": {},
                "geometry": {
                  "type": "LineString",
                  "coordinates": linePositions
                      .map((p) => [p.lng, p.lat])
                      .toList(),
                },
              }),
            ),
          );

          await style.addLayer(
            LineLayer(
              id: 'route-line-layer',
              sourceId: 'route-line-source',
              lineColor: 0xFF1976D2,
              lineWidth: 5.0,
              lineJoin: LineJoin.ROUND,
              lineCap: LineCap.ROUND,
            ),
          );

          final List<Point> points = linePositions
              .map((pos) => Point(coordinates: pos))
              .toList();

          final cameraOptions = await _mapboxMap!.cameraForCoordinatesPadding(
            points,
            CameraOptions(),
            MbxEdgeInsets(top: 50.0, left: 50.0, bottom: 250.0, right: 50.0),
            null,
            null,
          );

          await _mapboxMap!.easeTo(
            cameraOptions,
            MapAnimationOptions(duration: 1000),
          );
        }
      } else {
        debugPrint(
          'Mapbox Map Matching API Failed (${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error requesting map matching polyline: $e');
    }
  }

  List<Position> _getShapesPoints(TripsModel trip) {
    if (trip.shapes == null || trip.shapes!.isEmpty) {
      return [];
    }

    final sortedShapes = List<ShapesModel>.from(trip.shapes!)
      ..sort((a, b) => a.shapePtSequence.compareTo(b.shapePtSequence));

    return sortedShapes
        .map((shape) => Position(shape.shapePtLon, shape.shapePtLat))
        .toList();
  }

  Future<void> _drawTripShapePolylineOnMap(TripsModel trip) async {
    if (_mapboxMap == null) return;

    final shapePositions = _getShapesPoints(trip);

    if (shapePositions.isEmpty) {
      debugPrint(
        'No shapes found for train trip, falling back to stop coordinates.',
      );
      final stopTimes = _getStopsAndStopTimes(trip);
      shapePositions.addAll(
        stopTimes.map((st) => Position(st.stopLon, st.stopLat)),
      );
    }

    if (shapePositions.isEmpty) return;

    final style = _mapboxMap!.style;

    if (await style.styleLayerExists('route-line-layer')) {
      await style.removeStyleLayer('route-line-layer');
    }
    if (await style.styleSourceExists('route-line-source')) {
      await style.removeStyleSource('route-line-source');
    }

    await style.addSource(
      GeoJsonSource(
        id: 'route-line-source',
        data: jsonEncode({
          "type": "Feature",
          "properties": {},
          "geometry": {
            "type": "LineString",
            "coordinates": shapePositions.map((p) => [p.lng, p.lat]).toList(),
          },
        }),
      ),
    );

    await style.addLayer(
      LineLayer(
        id: 'route-line-layer',
        sourceId: 'route-line-source',
        lineColor: 0xFF1976D2,
        lineWidth: 5.0,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
      ),
    );

    final List<Point> points = shapePositions
        .map((pos) => Point(coordinates: pos))
        .toList();

    final cameraOptions = await _mapboxMap!.cameraForCoordinatesPadding(
      points,
      CameraOptions(),
      MbxEdgeInsets(top: 50.0, left: 50.0, bottom: 250.0, right: 50.0),
      null,
      null,
    );

    await _mapboxMap!.easeTo(
      cameraOptions,
      MapAnimationOptions(duration: 1000),
    );
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
}
