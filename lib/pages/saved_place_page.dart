import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/autocomplete_geocoding_service.dart';
import 'package:para_v3/services/recents_service.dart';

class SavedPlacePage extends StatefulWidget {
  final String saveKey;
  final String initialLabel;

  const SavedPlacePage({
    super.key,
    required this.saveKey,
    required this.initialLabel,
  });

  @override
  State<SavedPlacePage> createState() => _SavedPlacePageState();
}

class _SavedPlacePageState extends State<SavedPlacePage> {
  final _labelController = TextEditingController();
  final _searchController = TextEditingController();
  final _autocomplete = AutocompleteGeocodingService();
  List<PlaceSuggestion> _suggestions = [];
  PlaceSuggestion? _selectedSuggestion;
  Position? _selectedPosition;

  @override
  void initState() {
    super.initState();
    _labelController.text = widget.initialLabel;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _searchController.dispose();
    _autocomplete.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final suggestions = await _autocomplete.getDebouncedSuggestions(query);
    if (mounted) setState(() => _suggestions = suggestions);
  }

  Future<void> _select(PlaceSuggestion suggestion) async {
    final position = await _autocomplete.geocode(suggestion);
    if (!mounted || position == null) return;
    setState(() {
      _selectedSuggestion = suggestion;
      _selectedPosition = position;
      _searchController.text = suggestion.fullText;
      _suggestions = [];
    });
  }

  Future<void> _save() async {
    final suggestion = _selectedSuggestion;
    final position = _selectedPosition;
    final label = _labelController.text.trim();
    if (suggestion == null || position == null || label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a place and enter a label.')),
      );
      return;
    }
    await RecentsService.instance.savePlace(SavedPlace(
      key: widget.saveKey,
      label: label,
      suggestion: suggestion,
      position: position,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialLabel.isEmpty
              ? 'Add saved place'
              : 'Save ${widget.initialLabel}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: 'Save as',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: _search,
            decoration: const InputDecoration(
              labelText: 'Search for an address',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          ..._suggestions.map(
            (suggestion) => ListTile(
              leading: const Icon(Icons.location_on_rounded),
              title: Text(
                suggestion.mainText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                suggestion.secondaryText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _select(suggestion),
            ),
          ),
          if (_searchController.text.trim().isNotEmpty &&
              _suggestions.isEmpty &&
              _selectedSuggestion == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No results found')),
            ),
          if (_selectedSuggestion != null)
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(_selectedSuggestion!.fullText),
              subtitle: Text(
                '${_selectedPosition!.lat.toStringAsFixed(5)}, '
                '${_selectedPosition!.lng.toStringAsFixed(5)}',
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.bookmark_add),
            label: const Text('Save place'),
          ),
        ],
      ),
    );
  }
}
