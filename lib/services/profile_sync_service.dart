import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:para_v3/services/profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileSyncService {
  ProfileSyncService._();

  static final instance = ProfileSyncService._();
  static const _lastOwnerKey = 'para.profile.lastOwner.v1';

  final _store = ProfileStore();
  Future<void> _queue = Future.value();
  String? _userId;
  bool _started = false;
  bool _applyingRemote = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _store.addListener(_onLocalProfileChanged);
    Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) => _handleSession(data.session),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Profile sync auth error: $error');
      },
    );
    try {
      await _store.load();
      await _handleSession(Supabase.instance.client.auth.currentSession);
    } catch (error) {
      debugPrint('Could not start profile sync: $error');
    }
  }

  Future<void> _handleSession(Session? session) async {
    final nextUserId = session?.user.id;
    if (nextUserId == _userId) return;
    final previousUserId = _userId;
    _userId = nextUserId;
    if (nextUserId == null) {
      if (previousUserId != null) {
        await _serialize(_clearLocalProfile);
      }
      return;
    }
    await _serialize(
      () => _downloadOrCreate(
        nextUserId,
        session?.user.userMetadata?['profile'],
      ),
    );
  }

  void _onLocalProfileChanged() {
    final userId = _userId;
    if (_applyingRemote || userId == null) return;
    unawaited(_serialize(() => _upload(userId, _store.profile)));
  }

  Future<void> _clearLocalProfile() async {
    _applyingRemote = true;
    try {
      await _store.reset();
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> _downloadOrCreate(String userId, Object? remoteJson) async {
    try {
      if (_userId != userId) return;
      final preferences = await SharedPreferences.getInstance();
      final lastOwner = preferences.getString(_lastOwnerKey);

      if (remoteJson is Map) {
        _applyingRemote = true;
        try {
          await _store.replace(ProfileData.fromJson(remoteJson));
        } finally {
          _applyingRemote = false;
        }
      } else {
        final firstProfile = lastOwner == null || lastOwner == userId
            ? _store.profile
            : ProfileData.defaults();
        if (!identical(firstProfile, _store.profile)) {
          _applyingRemote = true;
          try {
            await _store.replace(firstProfile);
          } finally {
            _applyingRemote = false;
          }
        }
        await _upload(userId, firstProfile);
      }
      await preferences.setString(_lastOwnerKey, userId);
    } on AuthException catch (error) {
      debugPrint('Cloud profile is unavailable: ${error.message}');
    } catch (error) {
      debugPrint('Could not initialize profile sync: $error');
    }
  }

  Future<void> _upload(String userId, ProfileData profile) async {
    if (_userId != userId) return;
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'profile': profile.toJson()}),
      );
    } on AuthException catch (error) {
      debugPrint('Could not sync profile: ${error.message}');
    } catch (error) {
      debugPrint('Could not sync profile: $error');
    }
  }

  Future<void> _serialize(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}
