import 'package:flutter/material.dart';

class LocationPermissionCard extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const LocationPermissionCard({super.key, required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_outlined, size: 32),
            const SizedBox(height: 12),
            const Text(
              'Location permission is turned off',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enable location in Settings to show your live position on the map.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onOpenSettings,
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
