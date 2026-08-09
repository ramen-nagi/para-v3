import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/drag_scroll_sheet.dart';
import 'package:para_v3/module/location_textfield.dart';
import 'package:para_v3/module/universal_map_tile.dart';
import 'package:para_v3/pages/commute_page_input.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/map_matching_service.dart';
import 'package:para_v3/services/raptor_pathfinding_service.dart';

class CommutePage extends StatefulWidget {
  const CommutePage({super.key});

  @override
  State<CommutePage> createState() => _CommutePageState();
}

class _CommutePageState extends State<CommutePage> {
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  Position? _originPosition;
  Position? _destinationPosition;
  List<Journey> _journeys = [];

  @override
  void dispose() {
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

    setState(() {
      _originPosition = result.originPosition;
      _destinationPosition = result.destinationPosition;
    });
    await _runRaptor(result.originPosition, result.destinationPosition);
  }

  Future<void> _runRaptor(Position origin, Position destination) async {
    final journeys = RaptorPathfindingService.instance.findJourneys(
      originLat: origin.lat.toDouble(),
      originLng: origin.lng.toDouble(),
      destLat: destination.lat.toDouble(),
      destLng: destination.lng.toDouble(),
    );

    for (final journey in journeys) {
      await _enrichJourneyLegs(journey);
    }
    if (!mounted) return;

    setState(() => _journeys = journeys);

    debugPrint('RAPTOR returned ${journeys.length} journey(s).');
    for (var journeyIndex = 0; journeyIndex < journeys.length; journeyIndex++) {
      final journey = journeys[journeyIndex];
      debugPrint('Journey ${journeyIndex + 1}:');
      for (var legIndex = 0; legIndex < journey.legs.length; legIndex++) {
        final leg = journey.legs[legIndex];
        final mode = leg.isWalking ? 'Walk' : leg.vehicleType.name;
        final route = leg.routeLongName == null
            ? ''
            : ' — ${leg.routeLongName}';
        final distance = leg.distance == null
            ? 'unknown distance'
            : '${leg.distance!.toStringAsFixed(0)} m';
        final duration = leg.durationSeconds == null
            ? 'unknown duration'
            : '${leg.durationSeconds!.toStringAsFixed(0)} s';
        debugPrint(
          '  ${legIndex + 1}. $mode$route\n'
          '     ${leg.fromStopName} → ${leg.toStopName}\n'
          '     $distance; $duration',
        );
      }
    }
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
      final latitudeDifference = coordinate.lat.toDouble() - target.lat.toDouble();
      final longitudeDifference =
          coordinate.lng.toDouble() - target.lng.toDouble();
      final distanceSquared =
          latitudeDifference * latitudeDifference + longitudeDifference * longitudeDifference;
      if (distanceSquared < nearestDistanceSquared) {
        nearestIndex = index;
        nearestDistanceSquared = distanceSquared;
      }
    }
    return nearestIndex;
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
                      Text('—', style: TextStyle(fontWeight: FontWeight.bold)),
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

  // TODO: Add _buildExpandedJourneyView(journey)

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const UniversalMapTile(),
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
        if (_journeys.isNotEmpty)
          DragScrollSheet(
            children: [
              Text('${_journeys.length} journeys found'),
              const SizedBox(height: 8),
              for (var index = 0; index < _journeys.length; index++)
                _buildJourneyCardOverview(_journeys[index]),
            ],
          ),
      ],
    );
  }
}
