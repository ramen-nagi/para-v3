import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/location_textfield.dart';
import 'package:para_v3/services/autocomplete_geocoding_service.dart';
import 'package:para_v3/services/recents_service.dart';

enum CommuteInputField { origin, destination }

class CommuteInputResult {
  final Position originPosition;
  final Position destinationPosition;

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

  @override
  void initState() {
    super.initState();
    _originPosition = widget.originPosition;
    _destinationPosition = widget.destinationPosition;
    _originFocusNode.addListener(_onOriginFocusChanged);
    _destinationFocusNode.addListener(_onDestinationFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focusNode = widget.initialField == CommuteInputField.origin
          ? _originFocusNode
          : _destinationFocusNode;
      focusNode.requestFocus();
    });
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
    debugPrint(
      '${isDestination ? 'Destination' : 'Origin'} coordinates: '
      'lat=${position.lat}, lng=${position.lng}',
    );

    final origin = _originPosition;
    final destination = _destinationPosition;
    if (origin != null && destination != null) {
      Navigator.of(context).pop(
        CommuteInputResult(
          originPosition: origin,
          destinationPosition: destination,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Commute',
          style: TextStyle(
            color: Colors.white
          ),
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
          ),

          const Divider(height: 10),
          
          Expanded(
            child: ListView.builder(
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = _suggestions[index];
                return ListTile(
                  leading: Icon(
                    _showingRecents
                        ? Icons.history
                        : Icons.location_on_rounded,
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
            ),
          ),
        ],
      ),
    );
  }
}
