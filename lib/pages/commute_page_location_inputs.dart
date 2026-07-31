import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

enum _ActiveField { origin, destination, none }

class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;
  final String fullText;

  PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.fullText,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    final placePrediction = json['placePrediction'];
    final structuredFormat = placePrediction['structuredFormat'];

    return PlaceSuggestion(
      placeId: placePrediction['placeId'] ?? '',
      mainText: structuredFormat?['mainText']?['text'] ?? '',
      secondaryText: structuredFormat?['secondaryText']?['text'] ?? '',
      fullText: placePrediction['text']?['text'] ?? '',
    );
  }
}

class CommutePageLocationInput extends StatefulWidget {
  final bool isOrigin;

  const CommutePageLocationInput({
    super.key,
    required this.isOrigin,
  });

  @override
  State<CommutePageLocationInput> createState() =>
      _CommutePageLocationInputState();
}

class _CommutePageLocationInputState extends State<CommutePageLocationInput> {
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  final FocusNode _originFocusNode = FocusNode();
  final FocusNode _destinationFocusNode = FocusNode();

  Timer? _debounce;
  _ActiveField _activeField = _ActiveField.none;

  List<PlaceSuggestion> _suggestions = [];
  bool _isLoading = false;

  static const int _maxResults = 7;
  static final RegExp _metroManilaRegex = RegExp(
    r'Metro Manila',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isOrigin) {
        _originFocusNode.requestFocus();
        _activeField = _ActiveField.origin;
      } else {
        _destinationFocusNode.requestFocus();
        _activeField = _ActiveField.destination;
      }
    });

    _originFocusNode.addListener(() {
      if (_originFocusNode.hasFocus) {
        setState(() => _activeField = _ActiveField.origin);
      }
    });

    _destinationFocusNode.addListener(() {
      if (_destinationFocusNode.hasFocus) {
        setState(() => _activeField = _ActiveField.destination);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _originController.dispose();
    _destinationController.dispose();
    _originFocusNode.dispose();
    _destinationFocusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchAutocompleteSuggestions(query);
    });
  }

  Future<void> _fetchAutocompleteSuggestions(String query) async {
    final apiKey = dotenv.env['MAPS_PLATFORM_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('MAPS_PLATFORM_KEY is missing from .env');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask':
              'suggestions.placePrediction.placeId,'
              'suggestions.placePrediction.text,'
              'suggestions.placePrediction.structuredFormat',
        },
        body: jsonEncode({
          'input': query,
          'includedRegionCodes': ['ph'],
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('Places Autocomplete error: ${response.body}');
        setState(() {
          _suggestions = [];
          _isLoading = false;
        });
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawSuggestions = (data['suggestions'] as List?) ?? [];

      final parsed = rawSuggestions
          .map((s) => PlaceSuggestion.fromJson(s as Map<String, dynamic>))
          .where((s) => _metroManilaRegex.hasMatch(s.fullText))
          .take(_maxResults)
          .toList();

      setState(() {
        _suggestions = parsed;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Places Autocomplete exception: $e');
      setState(() {
        _suggestions = [];
        _isLoading = false;
      });
    }
  }

  void _onSuggestionSelected(PlaceSuggestion suggestion) {
    // TODO: geocode suggestion.placeId into lat/lng down the line.
    setState(() {
      if (_activeField == _ActiveField.origin) {
        _originController.text = suggestion.fullText;
      } else if (_activeField == _ActiveField.destination) {
        _destinationController.text = suggestion.fullText;
      }
      _suggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  Widget _buildLocationTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required IconData icon,
    required Color iconColor,
    required String hintText,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: iconColor),
        hintText: hintText,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: _onQueryChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Locations'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          children: [
            _buildLocationTextField(
              controller: _originController,
              focusNode: _originFocusNode,
              icon: Icons.location_on,
              iconColor: Colors.blue,
              hintText: 'Origin Location',
            ),
            const SizedBox(height: 12),
            _buildLocationTextField(
              controller: _destinationController,
              focusNode: _destinationFocusNode,
              icon: Icons.location_on,
              iconColor: Colors.red,
              hintText: 'Target Destination',
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: CircularProgressIndicator(),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(suggestion.mainText),
                      subtitle: Text(suggestion.secondaryText),
                      onTap: () => _onSuggestionSelected(suggestion),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
