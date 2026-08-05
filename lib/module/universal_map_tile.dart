import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/location_permission_card.dart';
import 'package:para_v3/services/location_permission_service.dart';

class UniversalMapTile extends StatefulWidget {
  final double initialZoom;
  final void Function(MapboxMap mapboxMap)? onMapCreated;
  final void Function(Point point)? onLongTap;

  const UniversalMapTile({
    super.key,
    this.initialZoom = 12.0,
    this.onMapCreated,
    this.onLongTap,
  });

  @override
  State<UniversalMapTile> createState() => _UniversalMapTileState();
}

class _UniversalMapTileState extends State<UniversalMapTile> {
  final _locationPermissionService = const LocationPermissionService();
  LocationPermissionState? _locationPermissionState;

  @override
  void initState() {
    super.initState();

    final String? token = dotenv.env['MAPBOX_ACCESS_TOKEN'];
    MapboxOptions.setAccessToken(token!);
  }

  @override
  Widget build(BuildContext context) {
    final Point defaultPoint = Point(coordinates: Position(121.0403, 14.5895));

    final CoordinateBounds metroManilaBounds = CoordinateBounds(
      southwest: Point(coordinates: Position(120.8500, 14.3000)),
      northeast: Point(coordinates: Position(121.2000, 14.8000)),
      infiniteBounds: false,
    );

    return Stack(
      children: [
        MapWidget(
          key: const ValueKey("UniversalMapWidget"),
          cameraOptions: CameraOptions(
            center: defaultPoint,
            zoom: widget.initialZoom,
          ),
          onMapCreated: (MapboxMap mapboxMap) async {
            await mapboxMap.setBounds(
              CameraBoundsOptions(
                bounds: metroManilaBounds,
                minZoom: 10.0,
                maxZoom: 17.0,
              ),
            );

            await _enableLiveLocation(mapboxMap);

            if (widget.onMapCreated != null) {
              widget.onMapCreated!(mapboxMap);
            }
          },
        ),
        if (_locationPermissionState == LocationPermissionState.permanentlyDenied)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: LocationPermissionCard(
              onOpenSettings: _locationPermissionService.openSettings,
            ),
          ),
        Positioned(
          right: 16,
          bottom: 112,
          child: _buildCircularMapButton(Icons.traffic_rounded),
        ),
        Positioned(
          right: 16,
          bottom: 48,
          child: _buildCircularMapButton(Icons.my_location_rounded),
        ),
      ],
    );
  }

  Widget _buildCircularMapButton(IconData icon) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        onPressed: () {},
        icon: Icon(icon),
      ),
    );
  }

  Future<void> _enableLiveLocation(MapboxMap mapboxMap) async {
    final permissionState = await _locationPermissionService.requestPermission();
    if (!mounted) return;

    setState(() => _locationPermissionState = permissionState);
    if (permissionState != LocationPermissionState.granted) return;

    await mapboxMap.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: true,
        pulsingEnabled: true,
        showAccuracyRing: true,
      ),
    );
  }
}
