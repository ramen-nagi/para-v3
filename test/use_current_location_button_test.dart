import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/module/use_current_location_button.dart';
import 'package:para_v3/pages/saved_place_page.dart';

void main() {
  setUp(
    () => dotenv.loadFromString(envString: 'MAPS_PLATFORM_KEY=test-key'),
  );
  tearDown(dotenv.clean);

  testWidgets('returns the resolved position to its caller', (tester) async {
    Position? selectedPosition;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UseCurrentLocationButton(
            locationResolver: (_) async => Position(121.0, 14.6),
            onLocationSelected: (position) => selectedPosition = position,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();

    expect(selectedPosition?.lat, 14.6);
    expect(selectedPosition?.lng, 121.0);
  });

  test('formats selected locations as latitude and longitude only', () {
    expect(
      formatLocationCoordinates(Position(121.0123456, 14.6123456)),
      '14.61235, 121.01235',
    );
  });

  testWidgets('saved-place page includes the reusable location button', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SavedPlacePage(saveKey: 'home', initialLabel: 'Home'),
      ),
    );

    expect(find.byType(UseCurrentLocationButton), findsOneWidget);
    expect(find.text('Use my current location'), findsOneWidget);
  });
}
