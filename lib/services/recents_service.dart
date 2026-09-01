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
  static const _favoriteRouteTableName = 'favorite_route';

  Future<Set<String>> getFavoriteRouteIds() async {
    final db = await _openDatabase();
    try {
      final rows = db.select('SELECT route_id FROM $_favoriteRouteTableName');
      return rows.map((row) => row['route_id'] as String).toSet();
    } finally {
      db.dispose();
    }
  }

  Future<void> setFavoriteRoute(String routeId, bool favorite) async {
    final db = await _openDatabase();
    try {
      if (favorite) {
        db.execute(
          'INSERT OR IGNORE INTO $_favoriteRouteTableName (route_id) VALUES (?)',
          [routeId],
        );
      } else {
        db.execute(
          'DELETE FROM $_favoriteRouteTableName WHERE route_id = ?',
          [routeId],
        );
      }
    } finally {
      db.dispose();
    }
  }

  Future<List<SavedPlace>> getSavedPlaces() async {
    final db = await _openDatabase();
    try {
      final rows = db.select('SELECT * FROM $_savedTableName ORDER BY label');
      return rows.map(_savedPlaceFromRow).toList();
    } finally {
      db.dispose();
    }
  }

  Future<SavedPlace?> getSavedPlaceByKey(String key) async {
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

  Future<void> clearSavedPlaces() async {
    final db = await _openDatabase();
    try {
      db.execute('DELETE FROM $_savedTableName');
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

  Future<void> deleteRecentSuggestion(String placeId) async {
    final db = await _openDatabase();
    try {
      db.execute(
        'DELETE FROM $_tableName WHERE place_id = ?',
        [placeId],
      );
    } finally {
      db.dispose();
    }
  }

  Future<void> clearRecentSuggestions() async {
    final db = await _openDatabase();
    try {
      db.execute('DELETE FROM $_tableName');
    } finally {
      db.dispose();
    }
  }

  Future<Position?> getRecentPosition(String placeId) async {
    final db = await _openDatabase();
    try {
      final rows = db.select(
        'SELECT latitude, longitude FROM $_tableName WHERE place_id = ?',
        [placeId],
      );
      if (rows.isEmpty || rows.first['latitude'] == null || rows.first['longitude'] == null) {
        return null;
      }
      return Position(
        (rows.first['longitude'] as num).toDouble(),
        (rows.first['latitude'] as num).toDouble(),
      );
    } finally {
      db.dispose();
    }
  }

  Future<void> saveSuggestion(
    PlaceSuggestion suggestion,
    Position position,
  ) async {
    final db = await _openDatabase();
    try {
      db.execute('''
        INSERT OR REPLACE INTO $_tableName (
          place_id, main_text, secondary_text, full_text, latitude, longitude
        ) VALUES (?, ?, ?, ?, ?, ?)
      ''', [
        suggestion.placeId,
        suggestion.mainText,
        suggestion.secondaryText,
        suggestion.fullText,
        position.lat,
        position.lng,
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
        ,latitude REAL
        ,longitude REAL
      )
    ''');
    final columns = db.select('PRAGMA table_info($_tableName)');
    final columnNames = columns.map((row) => row['name'] as String).toSet();
    if (!columnNames.contains('latitude')) {
      db.execute('ALTER TABLE $_tableName ADD COLUMN latitude REAL');
    }
    if (!columnNames.contains('longitude')) {
      db.execute('ALTER TABLE $_tableName ADD COLUMN longitude REAL');
    }
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
    db.execute('''
      CREATE TABLE IF NOT EXISTS $_favoriteRouteTableName (
        route_id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    return db;
  }
}
