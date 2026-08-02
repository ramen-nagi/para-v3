import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/pages/commute_page_map.dart';

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

class CommutePage extends StatefulWidget {
  const CommutePage({
    super.key,
  });

  @override
  State<CommutePage> createState() => _CommutePageState();
}

class _CommutePageState extends State<CommutePage> {
  PlaceSuggestion? _originSuggestion;
  PlaceSuggestion? _destinationSuggestion;
  Position? _originLatLng;
  Position? _destinationLatLng;

  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  final FocusNode _originFocusNode = FocusNode();
  final FocusNode _destinationFocusNode = FocusNode();

  Timer? _debounce;
  String? _sessionToken;
  _ActiveField _activeField = _ActiveField.none;

  List<PlaceSuggestion> _suggestions = [];
  bool _isLoading = false;

  static const int _maxResults = 5;
  static final RegExp _metroManilaRegex = RegExp(
    r'Metro Manila',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();

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

  String _generateSessionToken() {
    final rng = Random.secure();
    String hex(int bytes) => List.generate(
      bytes,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${hex(4)}-${hex(2)}-4${hex(1).substring(1)}-'
        '${(rng.nextInt(4) + 8).toRadixString(16)}${hex(1).substring(1)}-${hex(6)}';
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

    _sessionToken ??= _generateSessionToken();

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
          'locationRestriction': {
            'rectangle': {
              'low': {
                'latitude': 14.349036807202772,
                'longitude': 120.89298105551104,
              },
              'high': {
                'latitude': 14.788314817021137,
                'longitude': 121.14086007810187,
              },
            },
          },
          'sessionToken': _sessionToken,
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

  Future<void> _onSuggestionSelected(PlaceSuggestion suggestion) async {
    final selectedField = _activeField;

    setState(() {
      if (selectedField == _ActiveField.origin) {
        _originSuggestion = suggestion;
        _originLatLng = null;
        _originController.text = suggestion.fullText;
      } else if (selectedField == _ActiveField.destination) {
        _destinationSuggestion = suggestion;
        _destinationLatLng = null;
        _destinationController.text = suggestion.fullText;
      }
      _suggestions = [];
    });

    _sessionToken = null;
    FocusScope.of(context).unfocus();
    await _geocodeSelected(suggestion, selectedField);
  }

  void _navigateToCommuteMap() {
    final originSuggestion = _originSuggestion;
    final destinationSuggestion = _destinationSuggestion;
    if (originSuggestion == null || destinationSuggestion == null) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CommutePageMap(
          originSuggestion: originSuggestion,
          destinationSuggestion: destinationSuggestion,
          originLatLng: _originLatLng,
          destinationLatLng: _destinationLatLng,
        ),
      ),
    );
  }

  Future<void> _geocodeSelected(
    PlaceSuggestion suggestion,
    _ActiveField selectedField,
  ) async {
    final apiKey = dotenv.env['MAPS_PLATFORM_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[Geocode] MAPS_PLATFORM_KEY is missing from .env');
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(
          'https://places.googleapis.com/v1/places/${suggestion.placeId}',
        ),
        headers: {
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': 'location',
        },
      );

      if (response.statusCode != 200) {
        debugPrint('[Geocode] Error response: ${response.body}');
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final location = data['location'] as Map<String, dynamic>?;

      if (location == null) {
        debugPrint(
          '[Geocode] No location in response for placeId: ${suggestion.placeId}',
        );
        return;
      }

      final lat = (location['latitude'] as num).toDouble();
      final lng = (location['longitude'] as num).toDouble();

      if (selectedField == _ActiveField.origin) {
        setState(() {
          _originLatLng = Position(lng, lat);
        });
      } else if (selectedField == _ActiveField.destination) {
        setState(() {
          _destinationLatLng = Position(lng, lat);
        });
      }
    } catch (e) {
      debugPrint('[Geocode] Exception while fetching place details: $e');
    }
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

            FilledButton(
              onPressed:
                  _originSuggestion != null &&
                      _destinationSuggestion != null &&
                      _originLatLng != null &&
                      _destinationLatLng != null
                  ? _navigateToCommuteMap
                  : null,
              child: const Text('Commute'),
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
