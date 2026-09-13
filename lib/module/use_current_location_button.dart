import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

typedef CurrentLocationResolver =
    Future<Position?> Function(
      BuildContext context,
    );

String formatLocationCoordinates(Position position) =>
    '${position.lat.toStringAsFixed(5)}, ${position.lng.toStringAsFixed(5)}';

class UseCurrentLocationButton extends StatefulWidget {
  final FutureOr<void> Function(Position position) onLocationSelected;
  final CurrentLocationResolver? locationResolver;

  const UseCurrentLocationButton({
    super.key,
    required this.onLocationSelected,
    this.locationResolver,
  });

  @override
  State<UseCurrentLocationButton> createState() =>
      _UseCurrentLocationButtonState();
}

class _UseCurrentLocationButtonState extends State<UseCurrentLocationButton> {
  bool _isLoading = false;

  Future<void> _useCurrentLocation() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final resolver = widget.locationResolver ?? _resolveCurrentLocation;
      final position = await resolver(context);
      if (!mounted || position == null) return;
      await widget.onLocationSelected(position);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: _isLoading ? null : _useCurrentLocation,
      icon: _isLoading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.my_location),
      label: const Text('Use my current location'),
    ),
  );
}

Future<Position?> _resolveCurrentLocation(BuildContext context) async {
  try {
    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.deniedForever ||
        permission == geo.LocationPermission.denied) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required.')),
        );
      }
      return null;
    }

    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services.')),
        );
      }
      return null;
    }

    final current = await geo.Geolocator.getCurrentPosition();
    return Position(current.longitude, current.latitude);
  } on MissingPluginException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location is unavailable until the app is fully restarted.',
          ),
        ),
      );
    }
    return null;
  }
}
