import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/service_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    if (placePrediction is! Map<String, dynamic>) {
      throw const FormatException('Missing place prediction');
    }
    final structuredFormat = placePrediction['structuredFormat'];
    if (structuredFormat is! Map<String, dynamic>) {
      throw const FormatException('Missing structured place format');
    }
    final mainTextData = structuredFormat['mainText'];
    final secondaryTextData = structuredFormat['secondaryText'];
    final fullTextData = placePrediction['text'];
    if (mainTextData is! Map<String, dynamic> ||
        fullTextData is! Map<String, dynamic>) {
      throw const FormatException('Missing place text');
    }
    final placeId = placePrediction['placeId'];
    final mainText = mainTextData['text'];
    final secondaryText = secondaryTextData is Map<String, dynamic>
        ? secondaryTextData['text']
        : null;
    final fullText = fullTextData['text'];
    if (placeId is! String || mainText is! String || fullText is! String) {
      throw const FormatException('Invalid place text');
    }
    return PlaceSuggestion(
      placeId: placeId,
      mainText: mainText,
      secondaryText: secondaryText is String ? secondaryText : '',
      fullText: fullText,
    );
  }
}

class AutocompleteGeocodingService {
  static const _appIdentityChannel = MethodChannel(
    'com.parametromanila/app_identity',
  );
  static const _maxResults = 5;
  static const _guestDailyLimit = 25;
  static const _guestRequestCountKey = 'guest_autocomplete_request_count';
  static const _guestRequestDateKey = 'guest_autocomplete_request_date';
  static final _metroManilaRegex = RegExp('Metro Manila', caseSensitive: false);
  String get _apiKey {
    final value = dotenv.env['MAPS_PLATFORM_KEY'];
    if (value == null || value.isEmpty) {
      throw const ServiceException(ServiceFailureKind.configuration);
    }
    return value;
  }

  Timer? _debounce;
  Completer<List<PlaceSuggestion>>? _pendingSuggestions;
  Future<Map<String, String>>? _androidIdentityHeaders;
  String? _sessionToken;
  bool _quotaExceeded = false;

  bool get quotaExceeded => _quotaExceeded;

  Future<List<PlaceSuggestion>> getDebouncedSuggestions(
    String query, {
    required bool isAuthenticated,
  }) {
    cancelPendingSuggestions();
    if (query.trim().isEmpty) return Future.value(<PlaceSuggestion>[]);

    final completer = Completer<List<PlaceSuggestion>>();
    _pendingSuggestions = completer;
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final canRequest = await _consumeGuestQuota(isAuthenticated);
        if (!canRequest) {
          if (!completer.isCompleted) completer.complete(<PlaceSuggestion>[]);
          return;
        }
        final suggestions = await fetchAutocompleteSuggestions(query);
        if (!completer.isCompleted) completer.complete(suggestions);
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }

  Future<bool> _consumeGuestQuota(bool isAuthenticated) async {
    _quotaExceeded = false;
    if (isAuthenticated) return true;

    try {
      final preferences = await SharedPreferences.getInstance();
      final today = _localDateKey(DateTime.now());
      final storedDate = preferences.getString(_guestRequestDateKey);
      var requestCount = preferences.getInt(_guestRequestCountKey) ?? 0;

      if (storedDate != today) {
        requestCount = 0;
        await preferences.setString(_guestRequestDateKey, today);
        await preferences.setInt(_guestRequestCountKey, 0);
      }

      if (requestCount >= _guestDailyLimit) {
        _quotaExceeded = true;
        return false;
      }

      await preferences.setInt(_guestRequestCountKey, requestCount + 1);
      return true;
    } on Exception {
      throw const ServiceException(ServiceFailureKind.storage);
    }
  }

  String _localDateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
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
      final headers = await _googleHeaders(
        fieldMask:
            'suggestions.placePrediction.placeId,'
            'suggestions.placePrediction.text,'
            'suggestions.placePrediction.structuredFormat',
      );
      final response = await http.post(
        Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
        headers: headers,
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
        throw ServiceException(
          response.statusCode == 401 || response.statusCode == 403
              ? ServiceFailureKind.unauthorized
              : ServiceFailureKind.unavailable,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid autocomplete response');
      }
      final data = decoded;
      final suggestions = data['suggestions'];
      if (suggestions == null) return [];
      if (suggestions is! List) {
        throw const FormatException('Invalid autocomplete suggestions');
      }
      return suggestions
          .map((suggestion) {
            if (suggestion is! Map<String, dynamic>) {
              throw const FormatException('Invalid place suggestion');
            }
            return PlaceSuggestion.fromJson(suggestion);
          })
          .where(
            (suggestion) => _metroManilaRegex.hasMatch(suggestion.fullText),
          )
          .take(_maxResults)
          .toList();
    } on ServiceException {
      rethrow;
    } on http.ClientException {
      throw const ServiceException(ServiceFailureKind.network);
    } on FormatException {
      throw const ServiceException(ServiceFailureKind.invalidData);
    }
  }

  Future<Position?> geocode(PlaceSuggestion suggestion) async {
    try {
      final headers = await _googleHeaders(fieldMask: 'location');
      final response = await http.get(
        Uri.parse(
          'https://places.googleapis.com/v1/places/${suggestion.placeId}',
        ),
        headers: headers,
      );
      if (response.statusCode != 200) {
        throw ServiceException(
          response.statusCode == 401 || response.statusCode == 403
              ? ServiceFailureKind.unauthorized
              : ServiceFailureKind.unavailable,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid geocoding response');
      }
      final data = decoded;
      final location = data['location'] as Map<String, dynamic>?;
      if (location == null) return null;
      final longitude = location['longitude'];
      final latitude = location['latitude'];
      if (longitude is! num || latitude is! num) {
        throw const FormatException('Invalid place coordinates');
      }
      return Position(
        longitude.toDouble(),
        latitude.toDouble(),
      );
    } on ServiceException {
      rethrow;
    } on http.ClientException {
      throw const ServiceException(ServiceFailureKind.network);
    } on FormatException {
      throw const ServiceException(ServiceFailureKind.invalidData);
    }
  }

  void dispose() {
    cancelPendingSuggestions();
  }

  Future<Map<String, String>> _googleHeaders({
    required String fieldMask,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': _apiKey,
      'X-Goog-FieldMask': fieldMask,
    };
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      headers.addAll(await _getAndroidIdentityHeaders());
    }
    return headers;
  }

  Future<Map<String, String>> _getAndroidIdentityHeaders() {
    return _androidIdentityHeaders ??= _loadAndroidIdentityHeaders();
  }

  Future<Map<String, String>> _loadAndroidIdentityHeaders() async {
    try {
      final identity = await _appIdentityChannel
          .invokeMapMethod<String, String>('getGoogleApiIdentity');
      final packageName = identity?['packageName'];
      final certificateSha1 = identity?['certificateSha1'];
      if (packageName == null ||
          packageName.isEmpty ||
          certificateSha1 == null ||
          certificateSha1.isEmpty) {
        throw const ServiceException(ServiceFailureKind.configuration);
      }
      return {
        'X-Android-Package': packageName,
        'X-Android-Cert': certificateSha1,
      };
    } on ServiceException {
      rethrow;
    } on PlatformException {
      throw const ServiceException(ServiceFailureKind.configuration);
    } on MissingPluginException {
      throw const ServiceException(ServiceFailureKind.configuration);
    }
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
