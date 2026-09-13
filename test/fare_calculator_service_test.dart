import 'package:flutter_test/flutter_test.dart';
import 'package:para_v3/services/fare_calculator_service.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Beep Card Fare applies discounted fares to trains only', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FareCalculatorService.instance;

    await service.initialize();

    expect(service.useBeepCardFare, isFalse);
    expect(service.fareTypeFor(VehicleType.train), 'STANDARD');
    expect(service.fareTypeFor(VehicleType.bus), 'STANDARD');

    await service.setBeepCardFare(true);

    expect(service.fareTypeFor(VehicleType.train), 'DISCOUNTED');
    expect(service.fareTypeFor(VehicleType.bus), 'STANDARD');
    expect(service.fareTypeFor(VehicleType.jeep), 'STANDARD');
    expect(service.fareTypeFor(VehicleType.ejeep), 'STANDARD');
    expect(service.fareTypeFor(VehicleType.uvExpress), 'STANDARD');
    expect(
      service.fareTypeFor(VehicleType.train, fareType: 'STANDARD'),
      'STANDARD',
    );

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('beep_card_fare_estimate'), isTrue);

    await service.setBeepCardFare(false);
    expect(service.fareTypeFor(VehicleType.train), 'STANDARD');

    await service.setDiscountedFare(true);
    expect(service.fareTypeFor(VehicleType.train), 'DISCOUNTED');
    expect(service.fareTypeFor(VehicleType.bus), 'DISCOUNTED');
  });
}
