import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/drag_scroll_sheet.dart';
import 'package:para_v3/module/universal_map_tile.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/mapbox_services.dart';
import 'routes_page.dart';

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
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _stopAnnotationManager;
  String? _selectedTripId;
  RouteMetadataResult? _selectedTripMetadata;

  List<Position> _getStopTimesStopsCoord(String tripId) {
    final trip = widget.route.trips.where((trip) => trip.tripId == tripId);
    if (trip.isEmpty) return [];

    final stopTimes = List<StopsAndStopTimesModel>.from(
      trip.first.stopTimes,
    )..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));

    return stopTimes
        .map((stopTime) => Position(stopTime.stopLon, stopTime.stopLat))
        .toList();
  }

  List<Position> _getShapeCoordinates(TripsModel trip) {
    final shapes = List<ShapesModel>.from(trip.shapes ?? [])
      ..sort((a, b) => a.shapePtSequence.compareTo(b.shapePtSequence));

    return shapes
        .map((shape) => Position(shape.shapePtLon, shape.shapePtLat))
        .toList();
  }

  Future<void> _drawRouteStops(String tripId) async {
    final map = _mapboxMap;
    if (map == null) return;

    final positions = _getStopTimesStopsCoord(tripId);
    final manager = _stopAnnotationManager ??= await map.annotations
        .createCircleAnnotationManager(id: 'route-stop-markers');
    await manager.deleteAll();
    if (positions.isEmpty) return;

    await manager.createMulti(
      positions.asMap().entries
          .map(
            (entry) => CircleAnnotationOptions(
              geometry: Point(coordinates: entry.value),
              circleColor: _stopMarkerColor(entry.key, positions.length),
              circleRadius: 4,
              circleStrokeColor: 0xFFFFFFFF,
              circleStrokeWidth: 1.5,
            ),
          )
          .toList(),
    );
  }

  int _stopMarkerColor(int index, int totalStops) {
    if (index == 0) return 0xFF1877F2;
    if (index == totalStops - 1) return 0xFFF44336;
    return 0xFF1976D2;
  }

  Future<void> _panCameraToFitTrip(TripsModel trip) async {
    final map = _mapboxMap;

    final stops = _getStopTimesStopsCoord(trip.tripId);
    final coordinates = stops.length >= 2 ? stops : _getShapeCoordinates(trip);
    if (coordinates.length < 2) return;

    final camera = await map!.cameraForCoordinates(
      coordinates.map((position) => Point(coordinates: position)).toList(),
      MbxEdgeInsets(top: 100, left: 40, bottom: 300, right: 40),
      null,
      null,
    );
    await map.flyTo(camera, MapAnimationOptions(duration: 500));
  }

  Widget _buildTripButton(TripsModel trip) {
    final stops = List<StopsAndStopTimesModel>.from(trip.stopTimes)
      ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    final firstStop = stops.isNotEmpty ? stops.first : null;
    final lastStop = stops.length > 1 ? stops.last : firstStop;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: _selectedTripId == trip.tripId
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _selectedTripId == trip.tripId
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
        final map = _mapboxMap;

        final isTrain = widget.route.vehicleType == VehicleType.train;
        final result = isTrain
            ? await MapMatchingService.fetchRouteMetadataResultTrain(
                widget.route.vehicleType,
                _getShapeCoordinates(trip),
              )
            : await MapMatchingService.fetchMapMatching(
                'driving-traffic',
                _getStopTimesStopsCoord(trip.tripId),
              );
        if (result == null) return;

        if (!mounted) return;
        setState(() {
          _selectedTripId = trip.tripId;
          _selectedTripMetadata = result;
        });

        await MapMatchingService.drawPolyline(map!, result.coordinates);
        await _drawRouteStops(trip.tripId);
        await _panCameraToFitTrip(trip);
        },
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(getIconForType(widget.route.vehicleType)),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  firstStop?.stopName ?? 'Unknown stop',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.navigate_next),
              ),
              Expanded(
                child: Text(
                  lastStop?.stopName ?? 'Unknown stop',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          subtitle: _buildTripMetadataSubtitle(stops.length, trip.tripId),
        ),
      ),
    );
  }

  Widget _buildTripMetadataSubtitle(int stopCount, String tripId) {
    final metadata = _selectedTripId == tripId ? _selectedTripMetadata : null;
    if (metadata == null) return Text('$stopCount stops');

    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _metadataItem(Icons.place_outlined, '$stopCount stops'),
        _metadataItem(Icons.straighten, _formatDistance(metadata.distanceMeters)),
        _metadataItem(Icons.schedule, _formatDuration(metadata.durationSeconds)),
      ],
    );
  }

  Widget _metadataItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(text),
      ],
    );
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  String _formatDuration(double? seconds) {
    if (seconds == null) return '--';
    return '${(seconds / 60).round()} min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.route.routeLongName),
      ),
      body: Stack(
        children: [
          UniversalMapTile(
            onMapCreated: (mapboxMap) {
              _mapboxMap = mapboxMap;
              _stopAnnotationManager = null;
            },
          ),
          DragScrollSheet(
            initialChildSize: 0.22,
            children: [
              for (final trip in widget.route.trips)
                _buildTripButton(trip),
            ],
          ),
        ],
      ),
    );
  }
}
