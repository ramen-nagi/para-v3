import 'package:flutter_test/flutter_test.dart';
import 'package:para_v3/pages/commute_page.dart';
import 'package:para_v3/services/profile_store.dart';

void main() {
  const home = SavedPlace(
    id: 'home',
    kind: SavedPlaceKind.home,
    label: 'Home',
    address: 'Home address',
    latitude: 14.61,
    longitude: 121.03,
  );
  const work = SavedPlace(
    id: 'work',
    kind: SavedPlaceKind.work,
    label: 'Work',
    address: 'Work address',
    latitude: 14.56,
    longitude: 121.01,
  );

  test('saved places use Mapbox longitude-latitude order', () {
    final endpoint = CommuteEndpoint.fromSavedPlace(home);
    expect(endpoint.position.lng, 121.03);
    expect(endpoint.position.lat, 14.61);
  });

  test('reverse Work to Home preserves endpoint direction and coordinates', () {
    final origin = CommuteEndpoint.fromSavedPlace(work);
    final destination = CommuteEndpoint.fromSavedPlace(home);
    expect(origin.label, 'Work address');
    expect(origin.position.lng, 121.01);
    expect(destination.label, 'Home address');
    expect(destination.position.lng, 121.03);
  });

  test('main compatibility keeps the no-argument page const', () {
    const page = CommutePage();
    expect(page.initialOrigin, isNull);
    expect(page.initialDestination, isNull);
  });
}
