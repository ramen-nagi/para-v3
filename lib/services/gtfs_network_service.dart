import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- Simple Dart In-Memory Models ---
class RouteModel {
  final String routeId;
  final String routeLongName;
  final List<TripModel> trips;

  RouteModel({
    required this.routeId,
    required this.routeLongName,
    required this.trips,
  });
}

class TripModel {
  final String tripId;
  final String routeId;
  final String? shapeId;
  final List<StopTimeModel> stopTimes;

  TripModel({
    required this.tripId,
    required this.routeId,
    this.shapeId,
    required this.stopTimes,
  });
}

class StopTimeModel {
  final String tripId;
  final int stopSequence;
  final String stopId;
  final String stopName;

  StopTimeModel({
    required this.tripId,
    required this.stopSequence,
    required this.stopId,
    required this.stopName,
  });
}

// --- Global Service Instance ---
class GtfsNetworkService extends ChangeNotifier {
  static final GtfsNetworkService instance = GtfsNetworkService._();
  GtfsNetworkService._();

  bool isLoaded = false;
  bool isDownloading = false;
  String? errorMessage;

  // In-memory dataset maps
  final Map<String, RouteModel> routesMap = {}; // route_id -> RouteModel

  /// Step 1: Download & sync background task
  Future<void> initializeAndSync() async {
    try {
      isDownloading = true;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      final localVersion = prefs.getInt('cached_gtfs_version') ?? 0;

      final client = Supabase.instance.client;

      // Check remote metadata table
      final metadata = await client
          .from('dataset_metadata')
          .select('version, file_path')
          .eq('id', 1)
          .single();

      final remoteVersion = metadata['version'] as int;
      final filePath = metadata['file_path'] as String;

      final appDir = await getApplicationDocumentsDirectory();
      final localDbFile = File(p.join(appDir.path, 'gtfs_active.sqlite'));

      if (!await localDbFile.exists() || remoteVersion > localVersion) {
        debugPrint('Downloading new dataset version ($remoteVersion)...');
        final response = await client.storage
            .from('gtfs_bundles')
            .download(filePath);

        final decompressedBytes = GZipDecoder().decodeBytes(response);
        await localDbFile.writeAsBytes(decompressedBytes, flush: true);
        await prefs.setInt('cached_gtfs_version', remoteVersion);
      }

      // Step 2: Load into memory
      await _loadDatabaseIntoMemory(localDbFile.path);

      isLoaded = true;
      isDownloading = false;
      notifyListeners();
      debugPrint('GTFS Dataset successfully loaded into memory!');
    } catch (e) {
      errorMessage = e.toString();
      isDownloading = false;
      notifyListeners();
      debugPrint('Error loading dataset: $e');
    }
  }

  /// Step 2: Parse raw SQLite tables into Dart Memory Objects
  Future<void> _loadDatabaseIntoMemory(String dbPath) async {
    final db = sqlite3.open(dbPath);

    // 1. Fetch stops to create quick stop_id -> stop_name map
    final stopsRows = db.select('SELECT stop_id, stop_name FROM stops');
    final Map<String, String> stopNames = {
      for (final row in stopsRows)
        row['stop_id'] as String: row['stop_name'] as String,
    };

    // 2. Fetch routes
    final routeRows = db.select('SELECT route_id, route_long_name FROM routes');
    for (final row in routeRows) {
      final routeId = row['route_id'] as String;
      final routeLongName = row['route_long_name'] as String;
      routesMap[routeId] = RouteModel(
        routeId: routeId,
        routeLongName: routeLongName,
        trips: [],
      );
    }

    // 3. Fetch trips
    final tripRows = db.select('SELECT trip_id, route_id, shape_id FROM trips');
    final Map<String, TripModel> tripMap = {};

    for (final row in tripRows) {
      final tripId = row['trip_id'] as String;
      final routeId = row['route_id'] as String;
      final shapeId = row['shape_id'] as String?;

      final trip = TripModel(
        tripId: tripId,
        routeId: routeId,
        shapeId: shapeId,
        stopTimes: [],
      );

      tripMap[tripId] = trip;
      routesMap[routeId]?.trips.add(trip);
    }

    // 4. Fetch stop_times and link to trips
    final stopTimeRows = db.select('''
      SELECT trip_id, stop_sequence, stop_id 
      FROM stop_times 
      ORDER BY trip_id, stop_sequence ASC
    ''');

    for (final row in stopTimeRows) {
      final tripId = row['trip_id'] as String;
      final stopId = row['stop_id'] as String;
      final stopSeq = row['stop_sequence'] as int;

      final stopTime = StopTimeModel(
        tripId: tripId,
        stopSequence: stopSeq,
        stopId: stopId,
        stopName: stopNames[stopId] ?? 'Unknown Stop',
      );

      tripMap[tripId]?.stopTimes.add(stopTime);
    }

    db.dispose();
  }

  /// Search helper for RoutesPage
  List<RouteModel> searchRoutesByLongName(String query) {
    if (query.isEmpty) return routesMap.values.toList();
    final lowerQuery = query.toLowerCase();
    return routesMap.values
        .where((r) => r.routeLongName.toLowerCase().contains(lowerQuery))
        .toList();
  }
}
