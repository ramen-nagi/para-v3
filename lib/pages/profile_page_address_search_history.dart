import 'package:flutter/material.dart';
import 'package:para_v3/module/appbar.dart';
import 'package:para_v3/services/autocomplete_geocoding_service.dart';
import 'package:para_v3/services/recents_service.dart';

class ProfilePageAddressSearchHistory extends StatefulWidget {
  const ProfilePageAddressSearchHistory({super.key});

  @override
  State<ProfilePageAddressSearchHistory> createState() =>
      _ProfilePageAddressSearchHistoryState();
}

class _ProfilePageAddressSearchHistoryState
    extends State<ProfilePageAddressSearchHistory> {
  List<PlaceSuggestion> _suggestions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final suggestions = await RecentsService.instance.getRecentSuggestions();
    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
      _loading = false;
    });
  }

  Future<void> _deleteAddress(PlaceSuggestion suggestion) async {
    await RecentsService.instance.deleteRecentSuggestion(suggestion.placeId);
    if (!mounted) return;
    setState(() {
      _suggestions.removeWhere(
        (item) => item.placeId == suggestion.placeId,
      );
    });
  }

  Future<void> _clearHistory() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear address history?'),
        content: const Text(
          'This will remove all recent addresses from this device.',
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
    if (shouldClear != true) return;

    await RecentsService.instance.clearRecentSuggestions();
    if (!mounted) return;
    setState(_suggestions.clear);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ParaAppBar(
        title: 'Address Search History',
        actions: _suggestions.isEmpty
            ? null
            : [
                IconButton(
                  tooltip: 'Clear all history',
                  onPressed: _clearHistory,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _suggestions.isEmpty
              ? const Center(child: Text('No recent addresses yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(suggestion.mainText),
                      subtitle: Text(suggestion.secondaryText),
                      trailing: IconButton(
                        tooltip: 'Delete address',
                        onPressed: () => _deleteAddress(suggestion),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    );
                  },
                ),
    );
  }
}
