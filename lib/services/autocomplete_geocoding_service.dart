import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

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

class AutocompleteGeocodingService {
  static const _maxResults = 5;
  static final _metroManilaRegex = RegExp('Metro Manila', caseSensitive: false);
  final apiKey = dotenv.env['MAPS_PLATFORM_KEY']!;

  Timer? _debounce;
  Completer<List<PlaceSuggestion>>? _pendingSuggestions;
  String? _sessionToken;

  Future<List<PlaceSuggestion>> getDebouncedSuggestions(String query) {
    cancelPendingSuggestions();
    if (query.trim().isEmpty) return Future.value(<PlaceSuggestion>[]);

    final completer = Completer<List<PlaceSuggestion>>();
    _pendingSuggestions = completer;
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final suggestions = await fetchAutocompleteSuggestions(query);
      if (!completer.isCompleted) completer.complete(suggestions);
    });
    return completer.future;
  }

  void cancelPendingSuggestions() {
    _debounce?.cancel();
    final pendingSuggestions = _pendingSuggestions;
    if (pendingSuggestions != null && !pendingSuggestions.isCompleted) {
      pendingSuggestions.complete(<PlaceSuggestion>[]);
    }
  }

  Future<List<PlaceSuggestion>> fetchAutocompleteSuggestions(
    String query,
  ) async {
    _sessionToken ??= _generateSessionToken();
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
              'low': {'latitude': 14.349036807202772, 'longitude': 120.89298105551104},
              'high': {'latitude': 14.788314817021137, 'longitude': 121.14086007810187},
            },
          },
          'sessionToken': _sessionToken,
        }),
      );
      if (response.statusCode != 200) {
        debugPrint('Places Autocomplete error: ${response.body}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ((data['suggestions'] as List?) ?? [])
          .map((suggestion) => PlaceSuggestion.fromJson(suggestion as Map<String, dynamic>))
          .where((suggestion) => _metroManilaRegex.hasMatch(suggestion.fullText))
          .take(_maxResults)
          .toList();
    } catch (error) {
      debugPrint('Places Autocomplete exception: $error');
      return [];
    }
  }

  Future<Position?> geocode(PlaceSuggestion suggestion) async {
    try {
      final response = await http.get(
        Uri.parse('https://places.googleapis.com/v1/places/${suggestion.placeId}'),
        headers: {'X-Goog-Api-Key': apiKey, 'X-Goog-FieldMask': 'location'},
      );
      if (response.statusCode != 200) {
        debugPrint('[Geocode] Error response: ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final location = data['location'] as Map<String, dynamic>?;
      if (location == null) return null;
      return Position(
        (location['longitude'] as num).toDouble(),
        (location['latitude'] as num).toDouble(),
      );
    } catch (error) {
      debugPrint('[Geocode] Exception while fetching place details: $error');
      return null;
    }
  }

  void dispose() {
    cancelPendingSuggestions();
  }

  String _generateSessionToken() {
    final random = Random.secure();
    String hex(int bytes) => List.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${hex(4)}-${hex(2)}-4${hex(1).substring(1)}-'
        '${(random.nextInt(4) + 8).toRadixString(16)}${hex(1).substring(1)}-${hex(6)}';
  }
}
