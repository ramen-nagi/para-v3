import 'package:supabase_flutter/supabase_flutter.dart';
import 'gtfs_network_service.dart';
import 'raptor_pathfinding_service.dart';

class FareCalculatorService {
  static final FareCalculatorService instance = FareCalculatorService._();
  FareCalculatorService._();

  final SupabaseClient _client = Supabase.instance.client;
  final Map<String, Map<String, dynamic>> _distanceFareCache = {};
  final Map<String, double> _trainFareCache = {};

  Future<double?> calculateLegFare(
    Leg leg, {
    String fareType = 'STANDARD',
  }) async {
    switch (leg.vehicleType) {
      case VehicleType.train:
        return _calculateTrainFare(leg, fareType);
      case VehicleType.jeep:
      case VehicleType.bus:
      case VehicleType.uvExpress:
        return _calculateDistanceFare(leg, fareType);
      case VehicleType.walk:
      case VehicleType.tricycle:
      case VehicleType.unknown:
        return null;
    }
  }

  Future<double?> _calculateTrainFare(Leg leg, String fareType) async {
    final key = '${leg.fromStopId}|${leg.toStopId}|$fareType';
    final cachedFare = _trainFareCache[key];
    if (cachedFare != null) return cachedFare;

    final row = await _client
        .from('train_fares')
        .select('fare')
        .eq('origin_stop_id', leg.fromStopId)
        .eq('destination_stop_id', leg.toStopId)
        .eq('fare_type', fareType)
        .maybeSingle();

    if (row == null) return null;
    final fare = (row['fare'] as num).toDouble();
    _trainFareCache[key] = fare;
    return fare;
  }

  Future<double?> _calculateDistanceFare(Leg leg, String fareType) async {
    final distance = leg.distance;
    if (distance == null) return null;

    final key = '${leg.vehicleType.rawValue}|$fareType';
    var row = _distanceFareCache[key];
    if (row == null) {
      row = await _client
          .from('distance_fares')
          .select(
            'minimum_distance_meters, minimum_fare, '
            'increment_distance_meters, increment_fare',
          )
          .eq('vehicle_type', leg.vehicleType.rawValue)
          .eq('fare_type', fareType)
          .maybeSingle();
      if (row == null) return null;
      _distanceFareCache[key] = row;
    }

    final minimumDistance = (row['minimum_distance_meters'] as num).toDouble();
    final minimumFare = (row['minimum_fare'] as num).toDouble();
    final incrementDistance = (row['increment_distance_meters'] as num)
        .toDouble();
    final incrementFare = (row['increment_fare'] as num).toDouble();

    if (distance <= minimumDistance) return minimumFare;

    final increments = ((distance - minimumDistance) / incrementDistance)
        .ceil();

    return minimumFare + increments * incrementFare;
  }

  void clearCache() {
    _distanceFareCache.clear();
    _trainFareCache.clear();
  }
}
