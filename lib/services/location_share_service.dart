import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationShareService {
  SupabaseClient get _client => Supabase.instance.client;

  String? _shareId;
  String? _publicToken;
  DateTime? _lastUpdate;
  bool _updateInProgress = false;

  bool get isSharing => _shareId != null;

  String? get shareUrl {
    final token = _publicToken;
    final baseUrl = dotenv.env['LOCATION_SHARE_BASE_URL']?.trim() ?? '';
    if (token == null || baseUrl.isEmpty) return null;

    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse(
      '$cleanBaseUrl/track.html',
    ).replace(queryParameters: {'token': token}).toString();
  }

  Future<void> start({
    required String displayName,
    required double latitude,
    required double longitude,
    required String destinationName,
    required double? destinationLatitude,
    required double? destinationLongitude,
    required String transportMode,
    required String routeName,
    required String legFrom,
    required String legTo,
    required int legNumber,
    required int legCount,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Please sign in before sharing your location.');
    }

    final baseUrl = dotenv.env['LOCATION_SHARE_BASE_URL']?.trim() ?? '';
    if (!baseUrl.startsWith('https://')) {
      throw StateError('The live-location website is not configured yet.');
    }

    if (isSharing) await stop();

    final row = await _client
        .from('live_location_shares')
        .insert({
          'user_id': user.id,
          'display_name': displayName.trim(),
          'lat': latitude,
          'lng': longitude,
          'destination_name': destinationName,
          'destination_lat': destinationLatitude,
          'destination_lng': destinationLongitude,
          'transport_mode': transportMode,
          'route_name': routeName,
          'leg_from': legFrom,
          'leg_to': legTo,
          'leg_number': legNumber,
          'leg_count': legCount,
        })
        .select('id, public_token')
        .single();

    _shareId = row['id'] as String;
    _publicToken = row['public_token'] as String;
    _lastUpdate = DateTime.now();
  }

  Future<void> update({
    required double latitude,
    required double longitude,
    required String transportMode,
    required String routeName,
    required String legFrom,
    required String legTo,
    required int legNumber,
    required int legCount,
    bool force = false,
  }) async {
    final shareId = _shareId;
    if (shareId == null || _updateInProgress) return;

    final now = DateTime.now();
    if (!force &&
        _lastUpdate != null &&
        now.difference(_lastUpdate!) < const Duration(seconds: 8)) {
      return;
    }

    _updateInProgress = true;
    try {
      await _client
          .from('live_location_shares')
          .update({
            'lat': latitude,
            'lng': longitude,
            'transport_mode': transportMode,
            'route_name': routeName,
            'leg_from': legFrom,
            'leg_to': legTo,
            'leg_number': legNumber,
            'leg_count': legCount,
          })
          .eq('id', shareId);
      _lastUpdate = now;
    } finally {
      _updateInProgress = false;
    }
  }

  Future<void> stop() async {
    final shareId = _shareId;
    _shareId = null;
    _publicToken = null;
    _lastUpdate = null;
    if (shareId == null) return;

    await _client.from('live_location_shares').delete().eq('id', shareId);
  }
}
