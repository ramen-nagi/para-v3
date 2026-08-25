import 'package:shared_preferences/shared_preferences.dart';
import 'gtfs_network_service.dart';

class CommutePreferencesService {
  static final CommutePreferencesService instance =
      CommutePreferencesService._();
  CommutePreferencesService._();

  static const _prefix = 'commute_mode_enabled_';
  final Map<VehicleType, bool> _enabled = {
    VehicleType.tricycle: true,
    VehicleType.train: true,
    VehicleType.jeep: true,
    VehicleType.bus: true,
    VehicleType.uvExpress: true,
  };
  Future<void>? _initialization;

  Future<void> initialize() => _initialization ??= _loadPreferences();

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    for (final type in _enabled.keys) {
      _enabled[type] = preferences.getBool(_key(type)) ?? true;
    }
  }

  bool isEnabled(VehicleType type) => _enabled[type] ?? true;

  Set<VehicleType> get excludedVehicleTypes => _enabled.entries
      .where((entry) => !entry.value)
      .map((entry) => entry.key)
      .toSet();

  Future<void> setEnabled(VehicleType type, bool enabled) async {
    if (!_enabled.containsKey(type)) return;
    _enabled[type] = enabled;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key(type), enabled);
  }

  String _key(VehicleType type) => '$_prefix${type.name}';
}
