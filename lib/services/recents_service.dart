import 'dart:io';
import 'package:para_v3/services/autocomplete_geocoding_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class SavedPlace {
  final String key;
  final String label;
  final PlaceSuggestion suggestion;
  final Position position;

  const SavedPlace({
    required this.key,
    required this.label,
    required this.suggestion,
    required this.position,
  });
}

class RecentsService {
  RecentsService._();

  static final RecentsService instance = RecentsService._();

  static const _maxRecents = 10;
  static const _databaseName = 'user_info.sqlite';
  static const _tableName = 'recent_address';
  static const _savedTableName = 'saved_place';

  Future<List<SavedPlace>> getSavedPlaces() async {
    final db = await _openDatabase();
    try {
      final rows = db.select('SELECT * FROM $_savedTableName ORDER BY label');
      return rows.map(_savedPlaceFromRow).toList();
    } finally {
      db.dispose();
    }
  }

  Future<SavedPlace?> getSavedPlace(String key) async {
    final db = await _openDatabase();
    try {
      final rows = db.select('SELECT * FROM $_savedTableName WHERE save_key = ?', [key]);
      return rows.isEmpty ? null : _savedPlaceFromRow(rows.first);
    } finally {
      db.dispose();
    }
  }

  Future<void> savePlace(SavedPlace place) async {
    final db = await _openDatabase();
    try {
      db.execute('''
        INSERT OR REPLACE INTO $_savedTableName
        (save_key, label, place_id, main_text, secondary_text, full_text, latitude, longitude)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''', [place.key, place.label, place.suggestion.placeId, place.suggestion.mainText,
        place.suggestion.secondaryText, place.suggestion.fullText,
        place.position.lat, place.position.lng]);
    } finally {
      db.dispose();
    }
  }

  SavedPlace _savedPlaceFromRow(Row row) => SavedPlace(
    key: row['save_key'] as String,
    label: row['label'] as String,
    suggestion: PlaceSuggestion(
      placeId: row['place_id'] as String,
      mainText: row['main_text'] as String,
      secondaryText: row['secondary_text'] as String,
      fullText: row['full_text'] as String,
    ),
    position: Position((row['longitude'] as num).toDouble(), (row['latitude'] as num).toDouble()),
  );

  Future<List<PlaceSuggestion>> getRecentSuggestions() async {
    final db = await _openDatabase();
    try {
      final rows = db.select('''
        SELECT place_id, main_text, secondary_text, full_text
        FROM $_tableName
        ORDER BY rowid DESC
        LIMIT $_maxRecents
      ''');
      return rows.map((row) => PlaceSuggestion(
        placeId: row['place_id'] as String,
        mainText: row['main_text'] as String,
        secondaryText: row['secondary_text'] as String,
        fullText: row['full_text'] as String,
      )).toList();
    } finally {
      db.dispose();
    }
  }

  Future<void> saveSuggestion(PlaceSuggestion suggestion) async {
    final db = await _openDatabase();
    try {
      db.execute('''
        INSERT OR REPLACE INTO $_tableName (
          place_id, main_text, secondary_text, full_text
        ) VALUES (?, ?, ?, ?)
      ''', [
        suggestion.placeId,
        suggestion.mainText,
        suggestion.secondaryText,
        suggestion.fullText,
      ]);
      db.execute('''
        DELETE FROM $_tableName
        WHERE rowid NOT IN (
          SELECT rowid FROM $_tableName
          ORDER BY rowid DESC
          LIMIT $_maxRecents
        )
      ''');
    } finally {
      db.dispose();
    }
  }

  Future<Database> _openDatabase() async {
    final appDirectory = await getApplicationDocumentsDirectory();
    final databaseFile = File(p.join(appDirectory.path, _databaseName));
    final db = sqlite3.open(databaseFile.path);
    db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        place_id TEXT PRIMARY KEY,
        main_text TEXT NOT NULL,
        secondary_text TEXT NOT NULL,
        full_text TEXT NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS $_savedTableName (
        save_key TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        place_id TEXT NOT NULL,
        main_text TEXT NOT NULL,
        secondary_text TEXT NOT NULL,
        full_text TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    return db;
  }
}
