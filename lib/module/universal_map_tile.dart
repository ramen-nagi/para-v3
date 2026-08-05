import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/drag_scroll_sheet.dart';
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
  static const _maxVisibleSheetExtent = 0.221;

  final _locationPermissionService = const LocationPermissionService();
  LocationPermissionState? _locationPermissionState;
  MapboxMap? _mapboxMap;

  Future<void> _enableLiveLocation(MapboxMap mapboxMap) async {
    final permissionState = await _locationPermissionService
        .requestPermission();
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

  void _onSheetExtentChanged() {
    if (!mounted) return;
    _updateMapOrnamentMargins();
  }

  Future<void> _updateMapOrnamentMargins() async {
    final map = _mapboxMap;
    final sheetExtent = DragScrollSheet.sheetExtent.value;
    if (map == null || sheetExtent > _maxVisibleSheetExtent || !mounted) {
      return;
    }

    final bottomMargin = MediaQuery.sizeOf(context).height * sheetExtent + 8.0;
    await map.logo.updateSettings(LogoSettings(marginBottom: bottomMargin));
    await map.attribution.updateSettings(
      AttributionSettings(marginBottom: bottomMargin),
    );
  }

  @override
  void initState() {
    super.initState();

    final String? token = dotenv.env['MAPBOX_ACCESS_TOKEN'];
    MapboxOptions.setAccessToken(token!);
    DragScrollSheet.sheetExtent.addListener(_onSheetExtentChanged);
  }

  @override
  void dispose() {
    DragScrollSheet.sheetExtent.removeListener(_onSheetExtentChanged);
    super.dispose();
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
            _mapboxMap = mapboxMap;
            await mapboxMap.setBounds(
              CameraBoundsOptions(
                bounds: metroManilaBounds,
                minZoom: 10.0,
                maxZoom: 17.0,
              ),
            );

            await _updateMapOrnamentMargins();

            await _enableLiveLocation(mapboxMap);

            if (widget.onMapCreated != null) {
              widget.onMapCreated!(mapboxMap);
            }
          },
        ),
        if (_locationPermissionState ==
            LocationPermissionState.permanentlyDenied)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: LocationPermissionCard(
              onOpenSettings: _locationPermissionService.openSettings,
            ),
          ),
        ValueListenableBuilder<double>(
          valueListenable: DragScrollSheet.sheetExtent,
          builder: (context, sheetExtent, _) {
            final cappedSheetExtent = sheetExtent
                .clamp(0.0, _maxVisibleSheetExtent)
                .toDouble();
            final bottom =
                MediaQuery.sizeOf(context).height * cappedSheetExtent + 8.0;
            return Positioned(
              right: 16,
              bottom: bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCircularMapButton(Icons.traffic_rounded),
                  const SizedBox(height: 8),
                  _buildCircularMapButton(Icons.my_location_rounded),
                ],
              ),
            );
          },
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
}
