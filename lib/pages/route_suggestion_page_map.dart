import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/drag_scroll_sheet.dart';
import 'package:para_v3/module/universal_map_tile.dart';

class RouteSuggestionMapResult {
  final Position? startPosition;
  final Position? endPosition;

  const RouteSuggestionMapResult({
    required this.startPosition,
    required this.endPosition,
  });
}

class RouteSuggestionPageMap extends StatefulWidget {
  final Position? startPosition;
  final Position? endPosition;

  const RouteSuggestionPageMap({
    super.key,
    this.startPosition,
    this.endPosition,
  });

  @override
  State<RouteSuggestionPageMap> createState() => _RouteSuggestionPageMapState();
}

class _RouteSuggestionPageMapState extends State<RouteSuggestionPageMap> {
  Position? _startPosition;
  Position? _endPosition;
  Position? _centerPosition;

  @override
  void initState() {
    super.initState();
    _startPosition = widget.startPosition;
    _endPosition = widget.endPosition;
  }

  void _onCameraChanged(CameraChangedEventData event) {
    setState(() => _centerPosition = event.cameraState.center.coordinates);
  }

  void _setStartCoordinate() {
    final position = _centerPosition;
    if (position == null) return;
    setState(() {
      _startPosition = position;
    });
    _popWhenComplete();
  }

  void _setEndCoordinate() {
    final position = _centerPosition;
    if (position == null) return;
    setState(() {
      _endPosition = position;
    });
    _popWhenComplete();
  }

  String _formatPosition(Position? position) {
    if (position == null) return '';
    return '${position.lat.toStringAsFixed(6)}, ${position.lng.toStringAsFixed(6)}';
  }

  void _popWhenComplete() {
    if (_startPosition == null || _endPosition == null) return;
    Navigator.of(context).pop(RouteSuggestionMapResult(
      startPosition: _startPosition,
      endPosition: _endPosition,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set Route Endpoints')),
      body: Stack(
        children: [
          UniversalMapTile(onCameraChanged: _onCameraChanged),
          const Center(
            child: IgnorePointer(
              child: Icon(Icons.location_pin, size: 48, color: Colors.red),
            ),
          ),
          DragScrollSheet(
            initialChildSize: 0.22,
            minChildSize: 0.22,
            maxChildSize: 0.22,
            snapSizes: const [0.22],
            snap: false,
            children: [
              FilledButton(
                onPressed: _setStartCoordinate,
                child: Text(
                  _startPosition == null
                      ? 'Set Pin as Start Coordinates'
                      : _formatPosition(_startPosition),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _setEndCoordinate,
                child: Text(
                  _endPosition == null
                      ? 'Set Pin as End Coordinates'
                      : _formatPosition(_endPosition),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}
