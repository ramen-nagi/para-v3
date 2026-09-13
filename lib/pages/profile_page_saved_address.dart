import 'package:flutter/material.dart';
import 'package:para_v3/module/profile_list_page.dart';
import 'package:para_v3/module/profile_list_tile.dart';
import 'package:para_v3/pages/saved_place_page.dart';
import 'package:para_v3/services/recents_service.dart';

class SavedAddressesPage extends StatefulWidget {
  const SavedAddressesPage({super.key});

  @override
  State<SavedAddressesPage> createState() => _SavedAddressesPageState();
}

class _SavedAddressesPageState extends State<SavedAddressesPage> {
  static const _defaultPlaces = <(String, String, IconData)>[
    ('home', 'Home', Icons.home_outlined),
    ('school', 'School', Icons.school_outlined),
    ('work', 'Work', Icons.work_outline),
  ];

  List<SavedPlace> _savedPlaces = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedPlaces();
  }

  Future<void> _loadSavedPlaces() async {
    final places = await RecentsService.instance.getSavedPlaces();
    if (!mounted) return;
    setState(() {
      _savedPlaces = places;
      _isLoading = false;
    });
  }

  SavedPlace? _findPlace(String key) {
    for (final place in _savedPlaces) {
      if (place.key == key) return place;
    }
    return null;
  }

  Future<void> _openPlace(String key, String label) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SavedPlacePage(saveKey: key, initialLabel: label),
      ),
    );
    await _loadSavedPlaces();
  }

  Future<void> _addCustomPlace() async {
    final key = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    await _openPlace(key, '');
  }

  Future<void> _deletePlace(SavedPlace place) async {
    await RecentsService.instance.deleteSavedPlace(place.key);
    if (!mounted) return;
    setState(() {
      _savedPlaces.removeWhere((savedPlace) => savedPlace.key == place.key);
    });
  }

  Widget _buildPlaceTile({
    required String key,
    required String label,
    required IconData icon,
  }) {
    final place = _findPlace(key);
    return ProfileListTile(
      leading: Icon(icon),
      title: label,
      subtitle: place?.suggestion.mainText ?? 'Tap to Set Address',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (place != null)
            IconButton(
              tooltip: label.isEmpty ? 'Delete saved address' : 'Delete $label',
              onPressed: () => _deletePlace(place),
              icon: const Icon(Icons.delete_outline),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => _openPlace(key, label),
    );
  }

  Future<void> _clearSavedPlaces() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear saved addresses?'),
        content: const Text(
          'This will remove all saved addresses from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await RecentsService.instance.clearSavedPlaces();
    await _loadSavedPlaces();
  }

  @override
  Widget build(BuildContext context) {
    final defaultKeys = _defaultPlaces.map((entry) => entry.$1).toSet();
    final customPlaces = _savedPlaces
        .where((place) => !defaultKeys.contains(place.key))
        .toList();

    return ProfileListPage(
      title: 'Saved Addresses',
      loading: _isLoading,
      actions: _savedPlaces.isEmpty
          ? null
          : [
              IconButton(
                tooltip: 'Clear saved addresses',
                onPressed: _clearSavedPlaces,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
      children: [
        for (final entry in _defaultPlaces)
          _buildPlaceTile(
            key: entry.$1,
            label: entry.$2,
            icon: entry.$3,
          ),
        for (final place in customPlaces)
          _buildPlaceTile(
            key: place.key,
            label: place.label,
            icon: Icons.bookmark_outline,
          ),
        ProfileListTile(
          leading: const Icon(Icons.add),
          title: 'Add place',
          onTap: _addCustomPlace,
        ),
      ],
    );
  }
}
