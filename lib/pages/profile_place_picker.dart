import 'package:flutter/material.dart';
import 'package:para_v3/services/autocomplete_geocoding_service.dart';
import 'package:para_v3/services/profile_store.dart';
import 'package:para_v3/services/recents_service.dart';

class ProfilePlacePicker extends StatefulWidget {
  final String title;
  final SavedPlaceKind kind;
  final SavedPlace? existingPlace;

  const ProfilePlacePicker({
    super.key,
    required this.title,
    required this.kind,
    this.existingPlace,
  });

  @override
  State<ProfilePlacePicker> createState() => _ProfilePlacePickerState();
}

class _ProfilePlacePickerState extends State<ProfilePlacePicker> {
  final _query = TextEditingController();
  final _places = AutocompleteGeocodingService();
  List<PlaceSuggestion> _suggestions = const [];
  int _requestId = 0;
  bool _loading = true, _resolving = false;
  bool _showingRecents = true, _loadFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(''));
  }

  @override
  void dispose() {
    _requestId++;
    _query.dispose();
    _places.dispose();
    super.dispose();
  }

  Future<void> _load(String rawQuery) async {
    if (!mounted || _resolving) return;
    final requestId = ++_requestId;
    final showRecents = rawQuery.trim().isEmpty;
    setState(() {
      _loading = true;
      _showingRecents = showRecents;
      _loadFailed = false;
    });

    List<PlaceSuggestion> results;
    var failed = false;
    try {
      if (showRecents) {
        _places.cancelPendingSuggestions();
        results = await RecentsService.instance.getRecentSuggestions();
      } else {
        results = await _places.getDebouncedSuggestions(rawQuery);
      }
    } catch (_) {
      results = const [];
      failed = true;
    }
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _suggestions = results;
      _loading = false;
      _loadFailed = failed;
    });
  }

  Future<void> _select(PlaceSuggestion suggestion) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    final position = await _places.geocode(suggestion);
    if (!mounted) return;
    if (position == null) {
      setState(() => _resolving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not locate this place. Try again.'),
        ),
      );
      return;
    }

    try {
      await RecentsService.instance.saveSuggestion(suggestion);
    } catch (_) {
      // Recent history is optional; the selected place is still valid.
    }
    if (!mounted) return;
    final label = switch (widget.kind) {
      SavedPlaceKind.home => 'Home',
      SavedPlaceKind.work => 'Work',
      SavedPlaceKind.custom => suggestion.mainText,
    };
    Navigator.of(context).pop(
      widget.existingPlace?.copyWith(
            kind: widget.kind,
            label: label,
            address: suggestion.fullText,
            latitude: position.lat.toDouble(),
            longitude: position.lng.toDouble(),
          ) ??
          SavedPlace(
            id: _newId(),
            kind: widget.kind,
            label: label,
            address: suggestion.fullText,
            latitude: position.lat.toDouble(),
            longitude: position.lng.toDouble(),
          ),
    );
  }

  String _newId() => widget.kind == SavedPlaceKind.custom
      ? DateTime.now().microsecondsSinceEpoch.toString()
      : widget.kind.name;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _query,
          autofocus: true,
          enabled: !_resolving,
          textInputAction: TextInputAction.search,
          onChanged: _load,
          decoration: InputDecoration(
            hintText: 'Search for a place',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: _resolving
                        ? null
                        : () {
                            _query.clear();
                            _load('');
                          },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
          ),
        ),
        const SizedBox(height: 8),
        if (_loading || _resolving) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _results()),
      ],
    ),
  );

  Widget _results() {
    if (_loading) return const SizedBox.shrink();
    if (_suggestions.isEmpty) return _emptyState();
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final place = _suggestions[index];
        return ListTile(
          enabled: !_resolving,
          leading: Icon(
            _showingRecents
                ? Icons.history_rounded
                : Icons.location_on_outlined,
          ),
          title: Text(place.mainText, maxLines: 1),
          subtitle: Text(place.secondaryText, maxLines: 1),
          onTap: () => _select(place),
        );
      },
    );
  }

  Widget _emptyState() {
    final searching = !_showingRecents;
    final title = _loadFailed
        ? 'Places are temporarily unavailable'
        : searching
        ? 'No places found'
        : 'No recent places';
    final message = _loadFailed
        ? 'Please try again.'
        : searching
        ? 'Check the spelling, or try a nearby landmark.'
        : 'Search for a landmark, station, street, or neighborhood.';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (_loadFailed || searching) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _load(_query.text),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}
