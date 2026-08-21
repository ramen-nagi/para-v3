import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/pages/route_suggestion_page_map.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RouteSuggestionPage extends StatefulWidget {
  const RouteSuggestionPage({super.key});

  @override
  State<RouteSuggestionPage> createState() => _RouteSuggestionPageState();
}

class _RouteSuggestionPageState extends State<RouteSuggestionPage> {
  final _formKey = GlobalKey<FormState>();
  final _routeNameController = TextEditingController();
  final _roadsController = TextEditingController();
  final _notesController = TextEditingController();
  Position? _startPosition;
  Position? _endPosition;
  bool _isSubmitting = false;
  String _vehicleType = 'bus';

  static const _vehicleTypes = <String, String>{
    'bus': 'Bus',
    'jeep': 'Jeep',
    'train': 'Train',
    'tricycle': 'Tricycle',
    'uv_express': 'UV Express',
    'modern_jeep': 'Modern Jeep',
    'unknown': 'Unknown',
  };

  @override
  void dispose() {
    _routeNameController.dispose();
    _roadsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _openEndpointMap() async {
    final result = await Navigator.of(context).push<RouteSuggestionMapResult>(
      MaterialPageRoute(
        builder: (_) => RouteSuggestionPageMap(
          startPosition: _startPosition,
          endPosition: _endPosition,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _startPosition = result.startPosition;
      _endPosition = result.endPosition;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final start = _startPosition;
    final end = _endPosition;
    if (start == null || end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set both route endpoints on the map.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.from('route_suggestions').insert({
        'reporter_id': Supabase.instance.client.auth.currentUser?.id,
        'route_name': _routeNameController.text.trim(),
        'vehicle_type': _vehicleType,
        'roads_traversed': _nullable(_roadsController.text),
        'notes': _nullable(_notesController.text),
        'start_latitude': start.lat,
        'start_longitude': start.lng,
        'end_latitude': end.lat,
        'end_longitude': end.lng,
        'status': 'pending',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route suggestion submitted.')),
      );
      Navigator.of(context).pop();
    } on PostgrestException catch (error) {
      if (mounted) _showError(error.message);
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not submit route suggestion: $message')),
    );
  }

  String? _nullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suggest a Route')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _routeNameController,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Route name',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a route name'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _vehicleType,
              decoration: const InputDecoration(
                labelText: 'Vehicle type',
                border: OutlineInputBorder(),
              ),
              items: _vehicleTypes.entries
                  .map((entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _vehicleType = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _roadsController,
              maxLines: 3,
              maxLength: 5000,
              decoration: const InputDecoration(
                labelText: 'Roads traversed (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Additional notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Set route endpoints',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _startPosition != null && _endPosition != null
                    ? Icons.check_circle
                    : Icons.location_searching,
              ),
              title: Text(
                _startPosition != null && _endPosition != null
                    ? 'Start and end points selected'
                    : 'Start and end points not selected',
              ),
              subtitle: const Text('Open the map to set both endpoints'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openEndpointMap,
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openEndpointMap,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open map to set endpoints'),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_isSubmitting ? 'Submitting...' : 'Submit suggestion'),
            ),
          ],
        ),
      ),
    );
  }

}
