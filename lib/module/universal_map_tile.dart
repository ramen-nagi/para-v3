import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/drag_scroll_sheet.dart';
import 'package:para_v3/module/location_permission_card.dart';
import 'package:para_v3/services/location_permission_service.dart';

class UniversalMapTile extends StatefulWidget {
  final double initialZoom;
  final bool isStartingCommute;
  final void Function(MapboxMap mapboxMap)? onMapCreated;
  final void Function(CameraChangedEventData event)? onCameraChanged;

  const UniversalMapTile({
    super.key,
    this.initialZoom = 12.0,
    this.isStartingCommute = false,
    this.onMapCreated,
    this.onCameraChanged,
  });

  @override
  State<UniversalMapTile> createState() => _UniversalMapTileState();
}

class _UniversalMapTileState extends State<UniversalMapTile> {
  static const _maxVisibleSheetExtent = 0.221;
  static const _trafficSourceId = 'mapbox-traffic-source';
  static const _trafficLayerId = 'mapbox-traffic-layer';

  final _locationPermissionService = const LocationPermissionService();
  LocationPermissionState? _locationPermissionState;
  MapboxMap? _mapboxMap;
  bool _isTrafficVisible = false;
  ViewportState? _viewport;

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

  Future<void> _toggleTrafficLayer() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final style = mapboxMap.style;
    if (_isTrafficVisible) {
      if (await style.styleLayerExists(_trafficLayerId)) {
        await style.removeStyleLayer(_trafficLayerId);
      }
      if (await style.styleSourceExists(_trafficSourceId)) {
        await style.removeStyleSource(_trafficSourceId);
      }
    } else {
      await style.addSource(
        VectorSource(
          id: _trafficSourceId,
          url: 'mapbox://mapbox.mapbox-traffic-v1',
        ),
      );
      await style.addLayer(
        LineLayer(
          id: _trafficLayerId,
          sourceId: _trafficSourceId,
          sourceLayer: 'traffic',
          slot: 'middle',
          lineWidth: 3,
          lineColorExpression: [
            'match',
            ['get', 'congestion'],
            'low', '#4CAF50',
            'moderate', '#FF9800',
            'heavy', '#F44336',
            'severe', '#F44336',
            '#4CAF50',
          ],
        ),
      );
    }
    if (!mounted) return;
    setState(() => _isTrafficVisible = !_isTrafficVisible);
  }

  Future<void> _panCameraToUserLocation() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final permissionState = _locationPermissionState ??
        await _locationPermissionService.checkPermission();
    if (!mounted) return;
    if (permissionState != LocationPermissionState.granted) {
      setState(() => _locationPermissionState = permissionState);
      return;
    }

    await mapboxMap.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: true,
        pulsingEnabled: true,
        showAccuracyRing: true,
      ),
    );
    if (!mounted) return;
    setState(() {
      _locationPermissionState = LocationPermissionState.granted;
      _viewport = FollowPuckViewportState(
        zoom: 16,
        pitch: 0,
        bearing: const FollowPuckViewportStateBearingConstant(0),
      );
    });
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
          viewport: _viewport,
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
          onCameraChangeListener: widget.onCameraChanged,
        ),
        if (_locationPermissionState != null &&
            _locationPermissionState != LocationPermissionState.granted)
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
            final cappedSheetExtent = widget.isStartingCommute
                ? _maxVisibleSheetExtent
                : sheetExtent.clamp(0.0, _maxVisibleSheetExtent).toDouble();
            final bottom =
                MediaQuery.sizeOf(context).height * cappedSheetExtent + 8.0;
            return Positioned(
              right: 16,
              bottom: bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCircularMapButton(
                    Icons.traffic_rounded,
                    _toggleTrafficLayer,
                    isActive: _isTrafficVisible,
                  ),
                  const SizedBox(height: 8),
                  _buildCircularMapButton(
                    Icons.my_location_rounded,
                    _panCameraToUserLocation,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCircularMapButton(
    IconData icon,
    VoidCallback onPressed, {
    bool isActive = false,
  }) {
    return Material(
      color: isActive
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}
