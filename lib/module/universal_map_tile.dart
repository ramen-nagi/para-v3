import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class UniversalMapTile extends StatefulWidget {
  final double initialZoom;

  final void Function(MapboxMap mapboxMap)? onMapCreated;

  const UniversalMapTile({
    super.key,
    this.initialZoom = 12.0,
    this.onMapCreated,
  });

  @override
  State<UniversalMapTile> createState() => _UniversalMapTileState();
}

class _UniversalMapTileState extends State<UniversalMapTile> {
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

    return MapWidget(
      key: const ValueKey("UniversalMapWidget"),

      viewport: CameraViewportState(
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

        if (widget.onMapCreated != null) {
          widget.onMapCreated!(mapboxMap);
        }
      },
    );
  }
}
