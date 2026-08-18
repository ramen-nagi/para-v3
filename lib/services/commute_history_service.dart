import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CommuteHistoryEntry {
  final String origin;
  final String destination;
  final DateTime completedAt;

  const CommuteHistoryEntry({
    required this.origin,
    required this.destination,
    required this.completedAt,
  });

  Map<String, Object?> toJson() => {
    'origin': origin,
    'destination': destination,
    'completedAt': completedAt.toIso8601String(),
  };

  static CommuteHistoryEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final origin = value['origin'];
    final destination = value['destination'];
    final completedAt = DateTime.tryParse(
      value['completedAt']?.toString() ?? '',
    );
    if (origin is! String ||
        destination is! String ||
        origin.isEmpty ||
        destination.isEmpty ||
        completedAt == null) {
      return null;
    }
    return CommuteHistoryEntry(
      origin: origin,
      destination: destination,
      completedAt: completedAt,
    );
  }
}

class CommuteHistoryService {
  CommuteHistoryService._();

  static const storageKey = 'para.commuteHistory.v1';
  static const _maxEntries = 50;

  static Future<List<CommuteHistoryEntry>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map(CommuteHistoryEntry.fromJson)
          .whereType<CommuteHistoryEntry>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> add(CommuteHistoryEntry entry) async {
    final entries = await load();
    entries.insert(0, entry);
    if (entries.length > _maxEntries) {
      entries.removeRange(_maxEntries, entries.length);
    }
    final preferences = await SharedPreferences.getInstance();
    return preferences.setString(
      storageKey,
      jsonEncode(entries.map((item) => item.toJson()).toList()),
    );
  }

  static Future<bool> clear() async {
    final preferences = await SharedPreferences.getInstance();
    return !preferences.containsKey(storageKey) ||
        await preferences.remove(storageKey);
  }
}
