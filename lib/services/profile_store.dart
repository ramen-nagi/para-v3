import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SavedPlaceKind { home, work, custom }

enum RoutePriority { fastest, fewerTransfers, lessWalking }

enum TransportMode { train, bus, jeep, uvExpress, tricycle }

class SavedPlace {
  final String id;
  final SavedPlaceKind kind;
  final String label;
  final String address;
  final double latitude;
  final double longitude;

  const SavedPlace({
    required this.id,
    required this.kind,
    required this.label,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'label': label,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
  };

  static SavedPlace? fromJson(Object? value) {
    if (value is! Map) return null;
    try {
      return SavedPlace(
        id: value['id'] as String,
        kind: SavedPlaceKind.values.firstWhere(
          (kind) => kind.name == value['kind'],
        ),
        label: value['label'] as String,
        address: value['address'] as String,
        latitude: (value['latitude'] as num).toDouble(),
        longitude: (value['longitude'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  SavedPlace copyWith({
    SavedPlaceKind? kind,
    String? label,
    String? address,
    double? latitude,
    double? longitude,
  }) => SavedPlace(
    id: id,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    address: address ?? this.address,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
  );
}

class FavoriteRoute {
  final String routeId;
  final String displayName;
  final TransportMode vehicleType;

  const FavoriteRoute({
    required this.routeId,
    required this.displayName,
    required this.vehicleType,
  });

  Map<String, Object?> toJson() => {
    'routeId': routeId,
    'displayName': displayName,
    'vehicleType': vehicleType.name,
  };

  static FavoriteRoute? fromJson(Object? value) {
    if (value is! Map) return null;
    try {
      final route = FavoriteRoute(
        routeId: value['routeId'] as String,
        displayName: value['displayName'] as String,
        vehicleType: TransportMode.values.firstWhere(
          (mode) => mode.name == value['vehicleType'],
        ),
      );
      return route.routeId.isEmpty || route.displayName.isEmpty ? null : route;
    } catch (_) {
      return null;
    }
  }
}

class ProfileData {
  static const defaultModes = {
    TransportMode.train,
    TransportMode.bus,
    TransportMode.jeep,
    TransportMode.uvExpress,
    TransportMode.tricycle,
  };
  static const _walkingDistances = {400, 800, 1200, 1600};

  final List<SavedPlace> savedPlaces;
  final RoutePriority routePriority;
  final int maxWalkingDistance;
  final Set<TransportMode> enabledModes;
  final List<FavoriteRoute> favoriteRoutes;

  ProfileData({
    required List<SavedPlace> savedPlaces,
    required this.routePriority,
    required this.maxWalkingDistance,
    required Set<TransportMode> enabledModes,
    List<FavoriteRoute> favoriteRoutes = const [],
  }) : savedPlaces = List.unmodifiable(savedPlaces),
       enabledModes = Set.unmodifiable(enabledModes),
       favoriteRoutes = List.unmodifiable(favoriteRoutes);

  factory ProfileData.defaults() => ProfileData(
    savedPlaces: const [],
    routePriority: RoutePriority.fastest,
    maxWalkingDistance: 800,
    enabledModes: defaultModes,
  );

  factory ProfileData.fromJson(Object? value) {
    if (value is! Map) return ProfileData.defaults();
    final places = value['savedPlaces'] is List
        ? (value['savedPlaces'] as List)
              .map(SavedPlace.fromJson)
              .whereType<SavedPlace>()
              .toList()
        : <SavedPlace>[];
    final rawModes = value['enabledModes'];
    final modes = rawModes is List
        ? rawModes
              .whereType<String>()
              .map(_modeFromWire)
              .whereType<TransportMode>()
              .toSet()
        : defaultModes;
    final rawDistance = value['maxWalkingDistance'];
    return ProfileData(
      savedPlaces: places,
      routePriority: _priorityFromWire(value['routePriority']),
      maxWalkingDistance:
          rawDistance is num && _walkingDistances.contains(rawDistance.toInt())
          ? rawDistance.toInt()
          : 800,
      enabledModes: rawModes is List && (rawModes.isEmpty || modes.isNotEmpty)
          ? modes
          : defaultModes,
      favoriteRoutes: value['favoriteRoutes'] is List
          ? (value['favoriteRoutes'] as List)
                .map(FavoriteRoute.fromJson)
                .whereType<FavoriteRoute>()
                .toList()
          : const [],
    );
  }

  ProfileData copyWith({
    List<SavedPlace>? savedPlaces,
    RoutePriority? routePriority,
    int? maxWalkingDistance,
    Set<TransportMode>? enabledModes,
    List<FavoriteRoute>? favoriteRoutes,
  }) => ProfileData(
    savedPlaces: savedPlaces ?? this.savedPlaces,
    routePriority: routePriority ?? this.routePriority,
    maxWalkingDistance: maxWalkingDistance ?? this.maxWalkingDistance,
    enabledModes: enabledModes ?? this.enabledModes,
    favoriteRoutes: favoriteRoutes ?? this.favoriteRoutes,
  );

  Map<String, Object?> toJson() => {
    'savedPlaces': savedPlaces.map((place) => place.toJson()).toList(),
    'routePriority': routePriority.name,
    'maxWalkingDistance': maxWalkingDistance,
    'enabledModes': enabledModes.map((mode) => mode.name).toList()..sort(),
    'favoriteRoutes': favoriteRoutes.map((route) => route.toJson()).toList(),
  };

  static RoutePriority _priorityFromWire(Object? value) {
    for (final priority in RoutePriority.values) {
      if (priority.name == value) return priority;
    }
    return RoutePriority.fastest;
  }

  static TransportMode? _modeFromWire(String value) {
    for (final mode in TransportMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }
}

class ProfileStore extends ChangeNotifier {
  static const storageKey = 'para.profile.v1';
  static final instance = ProfileStore._();

  SharedPreferences? _preferences;
  ProfileData _profile = ProfileData.defaults();
  Future<ProfileData>? _loading;
  Future<void> _queue = Future.value();

  ProfileStore._();
  factory ProfileStore() => instance;
  @visibleForTesting
  ProfileStore.testing(SharedPreferences preferences)
    : _preferences = preferences;

  ProfileData get profile => _profile;

  Future<ProfileData> load() async {
    final loading = _loading ??= _read();
    try {
      await loading;
    } catch (_) {
      if (identical(_loading, loading)) _loading = null;
      rethrow;
    }
    return _profile;
  }

  Future<ProfileData> _read() async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    if (raw != null) {
      try {
        _profile = ProfileData.fromJson(jsonDecode(raw));
      } catch (_) {
        _profile = ProfileData.defaults();
      }
    }
    return _profile;
  }

  Future<bool> update(ProfileData Function(ProfileData current) change) =>
      _serialize(() async {
        await load();
        final next = change(_profile);
        final preferences = _preferences ??=
            await SharedPreferences.getInstance();
        final saved = await preferences.setString(
          storageKey,
          jsonEncode(next.toJson()),
        );
        if (saved) {
          _profile = next;
          notifyListeners();
        }
        return saved;
      });

  Future<bool> replace(ProfileData profile) => _serialize(() async {
    await load();
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      storageKey,
      jsonEncode(profile.toJson()),
    );
    if (saved) {
      _profile = profile;
      notifyListeners();
    }
    return saved;
  });

  Future<bool> reset() => _serialize(() async {
    await load();
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    final reset =
        !preferences.containsKey(storageKey) ||
        await preferences.remove(storageKey);
    if (reset) {
      _profile = ProfileData.defaults();
      notifyListeners();
    }
    return reset;
  });

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}
