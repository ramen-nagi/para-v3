import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/location_textfield.dart';
import 'package:para_v3/module/appbar.dart';
import 'package:para_v3/module/auth_required_dialog.dart';
import 'package:para_v3/pages/saved_place_page.dart';
import 'package:para_v3/services/autocomplete_geocoding_service.dart';
import 'package:para_v3/services/recents_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CommuteInputField { origin, destination }

class CommuteInputResult {
  final Position? originPosition;
  final Position? destinationPosition;
  final String? originMainText;
  final String? destinationMainText;

  const CommuteInputResult({
    required this.originPosition,
    required this.destinationPosition,
    required this.originMainText,
    required this.destinationMainText,
  });
}

class CommutePageInput extends StatefulWidget {
  final TextEditingController originController;
  final TextEditingController destinationController;
  final CommuteInputField initialField;
  final Position? originPosition;
  final Position? destinationPosition;
  final String? originMainText;
  final String? destinationMainText;

  const CommutePageInput({
    super.key,
    required this.originController,
    required this.destinationController,
    required this.initialField,
    this.originPosition,
    this.destinationPosition,
    this.originMainText,
    this.destinationMainText,
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
  bool _quotaPromptShown = false;
  int _suggestionRequestId = 0;
  Position? _originPosition;
  Position? _destinationPosition;
  String? _originMainText;
  String? _destinationMainText;
  List<SavedPlace> _savedPlaces = [];
  late final String _initialOriginText;
  late final String _initialDestinationText;
  late final Position? _initialOriginPosition;
  late final Position? _initialDestinationPosition;

  @override
  void initState() {
    super.initState();
    _originPosition = widget.originPosition;
    _destinationPosition = widget.destinationPosition;
    _originMainText = widget.originMainText;
    _destinationMainText = widget.destinationMainText;
    _initialOriginText = widget.originController.text;
    _initialDestinationText = widget.destinationController.text;
    _initialOriginPosition = widget.originPosition;
    _initialDestinationPosition = widget.destinationPosition;
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
    if (Supabase.instance.client.auth.currentUser == null) {
      if (mounted) setState(() => _savedPlaces = []);
      return;
    }
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
    if (!await _requireAuthentication()) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SavedPlacePage(saveKey: key, initialLabel: label),
      ),
    );
    await _loadSavedPlaces();
  }

  Future<void> _handleSavedPlace(String key, String label) async {
    if (!await _requireAuthentication()) return;
    final place = _savedPlace(key);
    if (place == null) {
      await _openSavePlace(key, label);
      return;
    }
    final isDestination = _destinationFocusNode.hasFocus;
    final controller = isDestination
        ? widget.destinationController
        : widget.originController;
    if (_rejectDuplicateLocation(
      place.position,
      isDestination,
      candidateText: place.suggestion.fullText,
    )) {
      return;
    }
    controller.text = place.suggestion.fullText;
    setState(() {
      if (isDestination) {
        _destinationPosition = place.position;
        _destinationMainText = place.suggestion.mainText;
      } else {
        _originPosition = place.position;
        _originMainText = place.suggestion.mainText;
      }
    });
    FocusScope.of(context).unfocus();
    if (_originPosition != null && _destinationPosition != null && mounted) {
      Navigator.of(context).pop(
        CommuteInputResult(
          originPosition: _originPosition,
          destinationPosition: _destinationPosition,
          originMainText: _originMainText,
          destinationMainText: _destinationMainText,
        ),
      );
    }
  }

  Future<void> _addCustomPlace() async {
    await _openSavePlace(
      'custom_${DateTime.now().microsecondsSinceEpoch}',
      '',
    );
  }

  Future<bool> _requireAuthentication() async {
    if (Supabase.instance.client.auth.currentUser != null) return true;

    await AuthRequiredDialog.show(
      context: context,
      title: 'Sign in to save places',
      content:
          'Create an account or sign in to save Home, School, Work, and custom places.',
    );
    return false;
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
      _quotaPromptShown = false;
      if (_originFocusNode.hasFocus) {
        _originPosition = null;
        _originMainText = null;
      } else if (_destinationFocusNode.hasFocus) {
        _destinationPosition = null;
        _destinationMainText = null;
      }
    }

    final requestId = ++_suggestionRequestId;
    final isShowingRecents = query.trim().isEmpty;
    final List<PlaceSuggestion> suggestions;
    if (isShowingRecents) {
      _autocomplete.cancelPendingSuggestions();
      suggestions = await RecentsService.instance.getRecentSuggestions();
    } else {
      suggestions = await _autocomplete.getDebouncedSuggestions(
        query,
        isAuthenticated: Supabase.instance.client.auth.currentUser != null,
      );
      if (_autocomplete.quotaExceeded && !_quotaPromptShown && mounted) {
        _quotaPromptShown = true;
        await _showAutocompleteQuotaPrompt();
      }
    }
    if (!mounted || requestId != _suggestionRequestId) return;
    setState(() {
      _suggestions = suggestions;
      _showingRecents = isShowingRecents;
    });
  }

  Future<void> _showAutocompleteQuotaPrompt() {
    return AuthRequiredDialog.show(
      context: context,
      title: 'Daily guest search limit reached',
      content:
          'Guests can make 25 autocomplete searches per day. Sign in or create an account to continue searching.',
    );
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

  void _swapOriginAndDestination() {
    final originText = widget.originController.text;
    final destinationText = widget.destinationController.text;
    final originPosition = _originPosition;
    final originMainText = _originMainText;

    setState(() {
      widget.originController.text = destinationText;
      widget.destinationController.text = originText;
      _originPosition = _destinationPosition;
      _destinationPosition = originPosition;
      _originMainText = _destinationMainText;
      _destinationMainText = originMainText;
      _suggestions = [];
      _showingRecents = false;
    });

    if (_originPosition != null && _destinationPosition != null && mounted) {
      FocusScope.of(context).unfocus();
      Navigator.of(context).pop(
        CommuteInputResult(
          originPosition: _originPosition,
          destinationPosition: _destinationPosition,
          originMainText: _originMainText,
          destinationMainText: _destinationMainText,
        ),
      );
    }
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    final isDestination = _destinationFocusNode.hasFocus;
    final controller = isDestination
        ? widget.destinationController
        : widget.originController;
    setState(() => _suggestions = []);

    final position =
        await RecentsService.instance.getRecentPosition(
          suggestion.placeId,
        ) ??
        await _autocomplete.geocode(suggestion);
    if (!mounted || position == null) return;
    if (_rejectDuplicateLocation(
      position,
      isDestination,
      candidateText: suggestion.fullText,
    )) {
      await _loadRecentSuggestions();
      return;
    }
    FocusScope.of(context).unfocus();

    await RecentsService.instance.saveSuggestion(suggestion, position);
    controller.text = suggestion.fullText;

    setState(() {
      if (isDestination) {
        _destinationPosition = position;
        _destinationMainText = suggestion.mainText;
      } else {
        _originPosition = position;
        _originMainText = suggestion.mainText;
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
        originMainText: _originMainText,
        destinationMainText: _destinationMainText,
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
      if (_rejectDuplicateLocation(
        position,
        isDestination,
        candidateText: 'Current location',
      )) {
        return;
      }
      final controller = isDestination
          ? widget.destinationController
          : widget.originController;
      controller.text =
          'Current location (${current.latitude.toStringAsFixed(5)}, '
          '${current.longitude.toStringAsFixed(5)})';

      setState(() {
        if (isDestination) {
          _destinationPosition = position;
          _destinationMainText = 'Current location';
        } else {
          _originPosition = position;
          _originMainText = 'Current location';
        }
        _suggestions = [];
      });
      FocusScope.of(context).unfocus();

      if (_originPosition != null && _destinationPosition != null && mounted) {
        Navigator.of(context).pop(
          CommuteInputResult(
            originPosition: _originPosition,
            destinationPosition: _destinationPosition,
            originMainText: _originMainText,
            destinationMainText: _destinationMainText,
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

  bool _samePosition(Position? first, Position? second) {
    if (first == null || second == null) return first == null && second == null;
    return first.lat == second.lat && first.lng == second.lng;
  }

  bool _rejectDuplicateLocation(
    Position candidate,
    bool isDestination, {
    String? candidateText,
  }) {
    final other = isDestination ? _originPosition : _destinationPosition;
    final otherText =
        (isDestination
                ? widget.originController.text
                : widget.destinationController.text)
            .trim()
            .toLowerCase();
    final otherMainText =
        (isDestination ? _originMainText : _destinationMainText)
            ?.trim()
            .toLowerCase();
    final normalizedCandidateText = candidateText?.trim().toLowerCase();
    final hasSameAddress =
        normalizedCandidateText?.isNotEmpty == true &&
        (normalizedCandidateText == otherText ||
            normalizedCandidateText == otherMainText);
    final hasSamePosition =
        other != null &&
        candidate.lat == other.lat &&
        candidate.lng == other.lng;
    if (!hasSameAddress && !hasSamePosition) return false;

    setState(() {
      if (isDestination) {
        widget.destinationController.clear();
        _destinationPosition = null;
        _destinationMainText = null;
      } else {
        widget.originController.clear();
        _originPosition = null;
        _originMainText = null;
      }
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Origin and destination must be different.'),
        ),
      );
    final focusNode = isDestination ? _destinationFocusNode : _originFocusNode;
    focusNode.requestFocus();
    return true;
  }

  bool _hasInputChanged() {
    return widget.originController.text != _initialOriginText ||
        widget.destinationController.text != _initialDestinationText ||
        !_samePosition(_originPosition, _initialOriginPosition) ||
        !_samePosition(_destinationPosition, _initialDestinationPosition);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (!_hasInputChanged()) {
          Navigator.of(context).pop();
          return false;
        }
        Navigator.of(context).pop(
          CommuteInputResult(
            originPosition: _originPosition,
            destinationPosition: _destinationPosition,
            originMainText: _originMainText,
            destinationMainText: _destinationMainText,
          ),
        );
        return false;
      },
      child: Scaffold(
        appBar: const ParaAppBar(title: 'Commute'),
        body: Column(
          children: [
            LocationTextfield(
              originController: widget.originController,
              destinationController: widget.destinationController,
              originFocusNode: _originFocusNode,
              destinationFocusNode: _destinationFocusNode,
              onOriginChanged: _onQueryChanged,
              onDestinationChanged: _onQueryChanged,
              onSwap: _swapOriginAndDestination,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                children: [
                  for (final entry in const [
                    ('home', 'Home', Icons.home_outlined),
                    ('school', 'School', Icons.school_outlined),
                    ('work', 'Work', Icons.work_outline),
                  ])
                    _savedPlaceTab(entry.$1, entry.$2, entry.$3),
                  for (final place in _savedPlaces.where(
                    (place) =>
                        !const {'home', 'school', 'work'}.contains(place.key),
                  ))
                    _savedPlaceTab(
                      place.key,
                      place.label,
                      Icons.bookmark_outline,
                    ),
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
            _showingRecents ? Icons.history : Icons.location_on_outlined,
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
