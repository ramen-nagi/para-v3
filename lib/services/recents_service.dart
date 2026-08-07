import 'dart:convert';
import 'package:para_v3/services/autocomplete_geocoding_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentsService {
  RecentsService._();

  static final RecentsService instance = RecentsService._();

  static const _storageKey = 'recent_place_suggestions';
  static const _maxRecents = 10;

  Future<List<PlaceSuggestion>> getRecentSuggestions() async {
    final preferences = await SharedPreferences.getInstance();
    final savedSuggestions = preferences.getStringList(_storageKey) ?? const [];

    return savedSuggestions
        .map(_decodeSuggestion)
        .whereType<PlaceSuggestion>()
        .toList();
  }

  Future<void> saveSuggestion(PlaceSuggestion suggestion) async {
    final recents = await getRecentSuggestions();
    recents.removeWhere((recent) => recent.placeId == suggestion.placeId);
    recents.insert(0, suggestion);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _storageKey,
      recents.take(_maxRecents).map(_encodeSuggestion).toList(),
    );
  }

  PlaceSuggestion? _decodeSuggestion(String value) {
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      return PlaceSuggestion(
        placeId: json['placeId'] as String,
        mainText: json['mainText'] as String,
        secondaryText: json['secondaryText'] as String,
        fullText: json['fullText'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  String _encodeSuggestion(PlaceSuggestion suggestion) => jsonEncode({
        'placeId': suggestion.placeId,
        'mainText': suggestion.mainText,
        'secondaryText': suggestion.secondaryText,
        'fullText': suggestion.fullText,
      });
}
