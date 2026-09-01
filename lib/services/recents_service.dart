import 'dart:convert';
import 'dart:io';
import 'package:para_v3/services/autocomplete_geocoding_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/raptor_pathfinding_service.dart';

class RecentCommute {
  final int id;
  final Journey journey;
  final DateTime startedAt;

  const RecentCommute({
    required this.id,
    required this.journey,
    required this.startedAt,
  });
}

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
  final String? _databasePath;

  RecentsService._({String? databasePath}) : _databasePath = databasePath;

  RecentsService.forTesting(String databasePath) : _databasePath = databasePath;

  static final RecentsService instance = RecentsService._();

  static const _maxRecents = 10;
  static const _databaseName = 'user_info.sqlite';
  static const _tableName = 'recent_address';
  static const _savedTableName = 'saved_place';
  static const _favoriteRouteTableName = 'favorite_route';
  static const _recentCommuteTableName = 'recent_commute';

  Future<List<RecentCommute>> getRecentCommutes() async {
    final db = await _openDatabase();
    try {
      final rows = db.select('''
        SELECT rowid AS commute_rowid, journey_json, started_at
        FROM $_recentCommuteTableName
        ORDER BY started_at DESC, rowid DESC
      ''');
      final commutes = <RecentCommute>[];
      for (final row in rows) {
        try {
          final decoded = jsonDecode(row['journey_json'] as String);
          final journey = Journey.fromJson(
            Map<String, dynamic>.from(decoded as Map),
          );
          if (journey.legs.isEmpty) continue;
          commutes.add(
            RecentCommute(
              id: row['commute_rowid'] as int,
              journey: journey,
              startedAt: DateTime.fromMillisecondsSinceEpoch(
                row['started_at'] as int,
              ),
            ),
          );
          if (commutes.length == _maxRecents) break;
        } catch (_) {
          // A corrupt history row should not prevent other commutes from loading.
        }
      }
      return commutes;
    } finally {
      db.dispose();
    }
  }

  Future<void> saveRecentCommute(Journey journey) async {
    if (journey.legs.isEmpty) return;
    final db = await _openDatabase();
    try {
      final signature = _journeySignature(journey);
      db.execute(
        '''
        INSERT INTO $_recentCommuteTableName
          (signature, journey_json, started_at)
        VALUES (?, ?, ?)
        ON CONFLICT(signature) DO UPDATE SET
          journey_json = excluded.journey_json,
          started_at = excluded.started_at
      ''',
        [
          signature,
          jsonEncode(journey.toJson()),
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      db.execute('''
        DELETE FROM $_recentCommuteTableName
        WHERE rowid NOT IN (
          SELECT rowid FROM $_recentCommuteTableName
          ORDER BY started_at DESC, rowid DESC
          LIMIT $_maxRecents
        )
      ''');
    } finally {
      db.dispose();
    }
  }

  String _journeySignature(Journey journey) => jsonEncode(
    journey.legs
        .map(
          (leg) => [
            leg.fromStopId,
            leg.toStopId,
            leg.vehicleType.rawValue,
            leg.routeId,
            leg.tripId,
          ],
        )
        .toList(),
  );

  void _migrateRecentCommuteTable(Database db) {
    final columns = db.select('PRAGMA table_info($_recentCommuteTableName)');
    final columnNames = columns.map((row) => row['name'] as String).toSet();
    const canonicalColumns = {
      'id',
      'signature',
      'journey_json',
      'started_at',
    };

    if (columnNames.difference(canonicalColumns).isNotEmpty ||
        !columnNames.contains('journey_json')) {
      _rebuildRecentCommuteTable(db, columnNames);
      return;
    }

    if (!columnNames.contains('signature')) {
      db.execute(
        'ALTER TABLE $_recentCommuteTableName ADD COLUMN signature TEXT',
      );
    }
    if (!columnNames.contains('started_at')) {
      db.execute(
        'ALTER TABLE $_recentCommuteTableName ADD COLUMN started_at INTEGER',
      );
      db.execute(
        'UPDATE $_recentCommuteTableName SET started_at = ? '
        'WHERE started_at IS NULL',
        [DateTime.now().millisecondsSinceEpoch],
      );
    }

    final rows = db.select('''
      SELECT rowid AS legacy_rowid, journey_json
      FROM $_recentCommuteTableName
      WHERE signature IS NULL OR signature = ''
    ''');
    for (final row in rows) {
      try {
        final decoded = jsonDecode(row['journey_json'] as String);
        final journey = Journey.fromJson(
          Map<String, dynamic>.from(decoded as Map),
        );
        if (journey.legs.isEmpty) continue;
        db.execute(
          'UPDATE $_recentCommuteTableName SET signature = ? WHERE rowid = ?',
          [_journeySignature(journey), row['legacy_rowid']],
        );
      } catch (_) {
        // Leave unreadable legacy rows untouched; the history loader skips them.
      }
    }

    db.execute('''
      DELETE FROM $_recentCommuteTableName
      WHERE signature IS NOT NULL
        AND signature != ''
        AND rowid NOT IN (
          SELECT MAX(rowid)
          FROM $_recentCommuteTableName
          WHERE signature IS NOT NULL AND signature != ''
          GROUP BY signature
        )
    ''');
    db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS recent_commute_signature_index
      ON $_recentCommuteTableName(signature)
    ''');
  }

  void _rebuildRecentCommuteTable(Database db, Set<String> legacyColumns) {
    final legacyTable =
        '${_recentCommuteTableName}_legacy_'
        '${DateTime.now().millisecondsSinceEpoch}';
    db.execute('BEGIN');
    try {
      db.execute(
        'ALTER TABLE $_recentCommuteTableName RENAME TO $legacyTable',
      );
      db.execute('''
        CREATE TABLE $_recentCommuteTableName (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          signature TEXT NOT NULL UNIQUE,
          journey_json TEXT NOT NULL,
          started_at INTEGER NOT NULL
        )
      ''');

      if (legacyColumns.contains('journey_json')) {
        final selectedColumns = legacyColumns.contains('started_at')
            ? 'journey_json, started_at'
            : 'journey_json';
        final rows = db.select('SELECT $selectedColumns FROM $legacyTable');
        for (final row in rows) {
          try {
            final journeyJson = row['journey_json'] as String;
            final decoded = jsonDecode(journeyJson);
            final journey = Journey.fromJson(
              Map<String, dynamic>.from(decoded as Map),
            );
            if (journey.legs.isEmpty) continue;
            final storedStartedAt = legacyColumns.contains('started_at')
                ? row['started_at'] as num?
                : null;
            db.execute(
              '''
              INSERT INTO $_recentCommuteTableName
                (signature, journey_json, started_at)
              VALUES (?, ?, ?)
              ON CONFLICT(signature) DO UPDATE SET
                journey_json = excluded.journey_json,
                started_at = MAX(started_at, excluded.started_at)
              ''',
              [
                _journeySignature(journey),
                journeyJson,
                storedStartedAt?.toInt() ??
                    DateTime.now().millisecondsSinceEpoch,
              ],
            );
          } catch (_) {
            // The renamed legacy table retains any row that cannot be migrated.
          }
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> deleteRecentCommute(int id) async {
    final db = await _openDatabase();
    try {
      db.execute(
        'DELETE FROM $_recentCommuteTableName WHERE rowid = ?',
        [id],
      );
    } finally {
      db.dispose();
    }
  }

  Future<void> clearRecentCommutes() async {
    final db = await _openDatabase();
    try {
      db.execute('DELETE FROM $_recentCommuteTableName');
    } finally {
      db.dispose();
    }
  }

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
      final rows = db.select(
        'SELECT * FROM $_savedTableName WHERE save_key = ?',
        [key],
      );
      return rows.isEmpty ? null : _savedPlaceFromRow(rows.first);
    } finally {
      db.dispose();
    }
  }

  Future<void> savePlace(SavedPlace place) async {
    final db = await _openDatabase();
    try {
      db.execute(
        '''
        INSERT OR REPLACE INTO $_savedTableName
        (save_key, label, place_id, main_text, secondary_text, full_text, latitude, longitude)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
        [
          place.key,
          place.label,
          place.suggestion.placeId,
          place.suggestion.mainText,
          place.suggestion.secondaryText,
          place.suggestion.fullText,
          place.position.lat,
          place.position.lng,
        ],
      );
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
    position: Position(
      (row['longitude'] as num).toDouble(),
      (row['latitude'] as num).toDouble(),
    ),
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
      return rows
          .map(
            (row) => PlaceSuggestion(
              placeId: row['place_id'] as String,
              mainText: row['main_text'] as String,
              secondaryText: row['secondary_text'] as String,
              fullText: row['full_text'] as String,
            ),
          )
          .toList();
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
      if (rows.isEmpty ||
          rows.first['latitude'] == null ||
          rows.first['longitude'] == null) {
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
      db.execute(
        '''
        INSERT OR REPLACE INTO $_tableName (
          place_id, main_text, secondary_text, full_text, latitude, longitude
        ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
        [
          suggestion.placeId,
          suggestion.mainText,
          suggestion.secondaryText,
          suggestion.fullText,
          position.lat,
          position.lng,
        ],
      );
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
    final databasePath = _databasePath;
    final databaseFile = databasePath == null
        ? File(
            p.join(
              (await getApplicationDocumentsDirectory()).path,
              _databaseName,
            ),
          )
        : File(databasePath);
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
    db.execute('''
      CREATE TABLE IF NOT EXISTS $_recentCommuteTableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        signature TEXT NOT NULL UNIQUE,
        journey_json TEXT NOT NULL,
        started_at INTEGER NOT NULL
      )
    ''');
    _migrateRecentCommuteTable(db);
    return db;
  }
}
