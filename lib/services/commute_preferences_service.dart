import 'package:shared_preferences/shared_preferences.dart';
import 'gtfs_network_service.dart';

class CommutePreferencesService {
  static final CommutePreferencesService instance =
      CommutePreferencesService._();
  CommutePreferencesService._();

  static const _prefix = 'commute_mode_penalize_';
  final Map<VehicleType, bool> _penalized = {
    VehicleType.tricycle: false,
    VehicleType.train: false,
    VehicleType.jeep: false,
    VehicleType.ejeep: false,
    VehicleType.bus: false,
    VehicleType.uvExpress: false,
  };
  Future<void>? _initialization;

  Future<void> initialize() => _initialization ??= _loadPreferences();

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    for (final type in _penalized.keys) {
      _penalized[type] = preferences.getBool(_key(type)) ?? false;
    }
  }

  bool isPenalized(VehicleType type) => _penalized[type] ?? false;

  Set<VehicleType> get penalizedVehicleTypes => _penalized.entries
      .where((entry) => entry.value)
      .map((entry) => entry.key)
      .toSet();

  Future<void> setPenalized(VehicleType type, bool penalized) async {
    if (!_penalized.containsKey(type)) return;
    _penalized[type] = penalized;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key(type), penalized);
  }

  String _key(VehicleType type) => '$_prefix${type.name}';
}
