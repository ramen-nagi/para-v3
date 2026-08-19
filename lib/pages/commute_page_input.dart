import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/location_textfield.dart';
import 'package:para_v3/pages/saved_place_page.dart';
import 'package:para_v3/services/autocomplete_geocoding_service.dart';
import 'package:para_v3/services/recents_service.dart';

enum CommuteInputField { origin, destination }

class CommuteInputResult {
  final Position? originPosition;
  final Position? destinationPosition;

  const CommuteInputResult({
    required this.originPosition,
    required this.destinationPosition,
  });
}

class CommutePageInput extends StatefulWidget {
  final TextEditingController originController;
  final TextEditingController destinationController;
  final CommuteInputField initialField;
  final Position? originPosition;
  final Position? destinationPosition;

  const CommutePageInput({
    super.key,
    required this.originController,
    required this.destinationController,
    required this.initialField,
    this.originPosition,
    this.destinationPosition,
  });

  @override
  State<CommutePageInput> createState() => _CommutePageInputState();
}

class _CommutePageInputState extends State<CommutePageInput> {
  final _originFocusNode = FocusNode();
  final _destinationFocusNode = FocusNode();
  final _autocomplete = AutocompleteGeocodingService();
  List<PlaceSuggestion> _suggestions = [];
  bool _showingRecents = false;
  int _suggestionRequestId = 0;
  Position? _originPosition;
  Position? _destinationPosition;
  List<SavedPlace> _savedPlaces = [];

  @override
  void initState() {
    super.initState();
    _originPosition = widget.originPosition;
    _destinationPosition = widget.destinationPosition;
    _originFocusNode.addListener(_onOriginFocusChanged);
    _destinationFocusNode.addListener(_onDestinationFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecentSuggestions();
      _loadSavedPlaces();
      final focusNode = widget.initialField == CommuteInputField.origin
          ? _originFocusNode
          : _destinationFocusNode;
      focusNode.requestFocus();
    });
  }

  Future<void> _loadSavedPlaces() async {
    final places = await RecentsService.instance.getSavedPlaces();
    if (mounted) setState(() => _savedPlaces = places);
  }

  SavedPlace? _savedPlace(String key) {
    for (final place in _savedPlaces) {
      if (place.key == key) return place;
    }
    return null;
  }

  Future<void> _openSavePlace(String key, String label) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SavedPlacePage(saveKey: key, initialLabel: label),
      ),
    );
    await _loadSavedPlaces();
  }

  Future<void> _handleSavedPlace(String key, String label) async {
    final place = _savedPlace(key);
    if (place == null) {
      await _openSavePlace(key, label);
      return;
    }
    final isDestination = _destinationFocusNode.hasFocus;
    final controller = isDestination
        ? widget.destinationController
        : widget.originController;
    controller.text = place.suggestion.fullText;
    setState(() {
      if (isDestination) {
        _destinationPosition = place.position;
      } else {
        _originPosition = place.position;
      }
    });
    FocusScope.of(context).unfocus();
    if (_originPosition != null && _destinationPosition != null && mounted) {
      Navigator.of(context).pop(CommuteInputResult(
        originPosition: _originPosition,
        destinationPosition: _destinationPosition,
      ));
    }
  }

  Future<void> _addCustomPlace() async {
    await _openSavePlace(
      'custom_${DateTime.now().microsecondsSinceEpoch}',
      '',
    );
  }

  @override
  void dispose() {
    _autocomplete.dispose();
    _originFocusNode.removeListener(_onOriginFocusChanged);
    _destinationFocusNode.removeListener(_onDestinationFocusChanged);
    _originFocusNode.dispose();
    _destinationFocusNode.dispose();
    super.dispose();
  }

  Future<void> _onQueryChanged(String query) async {
    if (query.trim().isEmpty) {
      if (_originFocusNode.hasFocus) {
        _originPosition = null;
      } else if (_destinationFocusNode.hasFocus) {
        _destinationPosition = null;
      }
    }

    final requestId = ++_suggestionRequestId;
    final isShowingRecents = query.trim().isEmpty;
    final List<PlaceSuggestion> suggestions;
    if (isShowingRecents) {
      _autocomplete.cancelPendingSuggestions();
      suggestions = await RecentsService.instance.getRecentSuggestions();
    } else {
      suggestions = await _autocomplete.getDebouncedSuggestions(query);
    }
    if (!mounted || requestId != _suggestionRequestId) return;
    setState(() {
      _suggestions = suggestions;
      _showingRecents = isShowingRecents;
    });
  }

  Future<void> _loadRecentSuggestions() async {
    final requestId = ++_suggestionRequestId;
    _autocomplete.cancelPendingSuggestions();

    final hasEmptyInput =
        widget.originController.text.trim().isEmpty ||
        widget.destinationController.text.trim().isEmpty;
    if (!hasEmptyInput) {
      if (!mounted || requestId != _suggestionRequestId) return;
      setState(() {
        _suggestions = [];
        _showingRecents = false;
      });
      return;
    }

    final suggestions = await RecentsService.instance.getRecentSuggestions();
    if (!mounted || requestId != _suggestionRequestId) return;
    setState(() {
      _suggestions = suggestions;
      _showingRecents = true;
    });
  }

  void _onOriginFocusChanged() {
    if (_originFocusNode.hasFocus) {
      _onQueryChanged(widget.originController.text);
    }
  }

  void _onDestinationFocusChanged() {
    if (_destinationFocusNode.hasFocus) {
      _onQueryChanged(widget.destinationController.text);
    }
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    final isDestination = _destinationFocusNode.hasFocus;
    final controller = isDestination
        ? widget.destinationController
        : widget.originController;
    controller.text = suggestion.fullText;
    setState(() => _suggestions = []);
    FocusScope.of(context).unfocus();
    await RecentsService.instance.saveSuggestion(suggestion);

    final position = await _autocomplete.geocode(suggestion);
    if (!mounted || position == null) return;

    setState(() {
      if (isDestination) {
        _destinationPosition = position;
      } else {
        _originPosition = position;
      }
    });

    final origin = _originPosition;
    final destination = _destinationPosition;
    if (origin == null || destination == null) {
      await _loadRecentSuggestions();
      return;
    }

    Navigator.of(context).pop(
      CommuteInputResult(
        originPosition: origin,
        destinationPosition: destination,
      ),
    );
  }

  Future<void> _useCurrentLocation() async {
    try {
      final isDestination = _destinationFocusNode.hasFocus;
      final permission = await geo.Geolocator.checkPermission();
      var resolvedPermission = permission;
      if (permission == geo.LocationPermission.denied) {
        resolvedPermission = await geo.Geolocator.requestPermission();
      }
      if (resolvedPermission == geo.LocationPermission.deniedForever ||
          resolvedPermission == geo.LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required.')),
        );
        return;
      }

      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services.')),
        );
        return;
      }

      final current = await geo.Geolocator.getCurrentPosition();
      final position = Position(current.longitude, current.latitude);
      final controller = isDestination
          ? widget.destinationController
          : widget.originController;
      controller.text =
          'Current location (${current.latitude.toStringAsFixed(5)}, '
          '${current.longitude.toStringAsFixed(5)})';

      setState(() {
        if (isDestination) {
          _destinationPosition = position;
        } else {
          _originPosition = position;
        }
        _suggestions = [];
      });
      FocusScope.of(context).unfocus();

      if (_originPosition != null && _destinationPosition != null && mounted) {
        Navigator.of(context).pop(
          CommuteInputResult(
            originPosition: _originPosition,
            destinationPosition: _destinationPosition,
          ),
        );
      }
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location is unavailable until the app is fully restarted.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(
          CommuteInputResult(
            originPosition: _originPosition,
            destinationPosition: _destinationPosition,
          ),
        );
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Commute',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
          LocationTextfield(
              originController: widget.originController,
              destinationController: widget.destinationController,
              originFocusNode: _originFocusNode,
              destinationFocusNode: _destinationFocusNode,
              onOriginChanged: _onQueryChanged,
              onDestinationChanged: _onQueryChanged,
            showTrailingActions: true,
          ),

          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _useCurrentLocation,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Use my current location'),
                ),
              ),
            ),

            SizedBox(
              height: 88,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final entry in const [
                    ('home', 'Home', Icons.home_outlined),
                    ('school', 'School', Icons.school_outlined),
                    ('work', 'Work', Icons.work_outline),
                  ])
                    _savedPlaceTab(entry.$1, entry.$2, entry.$3),
                  for (final place in _savedPlaces.where(
                    (place) => !const {'home', 'school', 'work'}.contains(place.key),
                  ))
                    _savedPlaceTab(place.key, place.label, Icons.bookmark_outline),
                  SizedBox(
                    height: 64,
                    child: ActionChip(
                      avatar: const Icon(Icons.add),
                      label: const Text('Add place'),
                      onPressed: _addCustomPlace,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 10),

            Expanded(
              child: _buildSuggestionsContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsContent() {
    if (_suggestions.isEmpty) {
      final message = _showingRecents
          ? 'Search and Select an Address to Start'
          : 'No results found';
      return Text(message);
    }

    return ListView.builder(
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return ListTile(
          leading: Icon(
            _showingRecents ? Icons.history : Icons.location_on_rounded,
          ),
          onTap: () => _selectSuggestion(suggestion),
          title: Text(
            suggestion.mainText,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            suggestion.secondaryText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  Widget _savedPlaceTab(String key, String label, IconData icon) {
    final place = _savedPlace(key);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 150,
        height: 64,
        child: Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _handleSavedPlace(key, label),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          place?.suggestion.mainText ?? 'Tap to Set Address',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
