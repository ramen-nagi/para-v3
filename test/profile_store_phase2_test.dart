import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:para_v3/services/profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _home = SavedPlace(
  id: 'home',
  kind: SavedPlaceKind.home,
  label: 'Home',
  address: 'Home address',
  latitude: 14.61,
  longitude: 121.03,
);
const _work = SavedPlace(
  id: 'work',
  kind: SavedPlaceKind.work,
  label: 'Work',
  address: 'Work address',
  latitude: 14.56,
  longitude: 121.01,
);
const _favorite = FavoriteRoute(
  routeId: 'stable-route',
  displayName: 'Route One',
  vehicleType: TransportMode.uvExpress,
);

Future<ProfileStore> _store([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return ProfileStore.testing(await SharedPreferences.getInstance());
}

void main() {
  test('legacy profile fields and wire values round-trip exactly', () async {
    final legacy = {
      'savedPlaces': [_home.toJson(), _work.toJson()],
      'routePriority': 'lessWalking',
      'maxWalkingDistance': 1200,
      'enabledModes': ['train', 'uvExpress'],
    };
    final store = await _store({
      ProfileStore.storageKey: jsonEncode(legacy),
    });
    final profile = await store.load();

    expect(profile.routePriority, RoutePriority.lessWalking);
    expect(profile.enabledModes, {
      TransportMode.train,
      TransportMode.uvExpress,
    });
    expect(profile.savedPlaces.first.id, 'home');
    expect(profile.savedPlaces.first.longitude, 121.03);
    expect(profile.favoriteRoutes, isEmpty);
    expect(profile.toJson()['routePriority'], 'lessWalking');
    expect(profile.toJson()['enabledModes'], ['train', 'uvExpress']);
  });

  test('malformed favorite routes safely load as empty', () async {
    final profile = ProfileData.fromJson({
      'favoriteRoutes': 'bad',
    });
    expect(profile.favoriteRoutes, isEmpty);
  });

  test('walking-only modes and every typed wire value round-trip', () {
    expect(
      ProfileData.fromJson({'enabledModes': const []}).enabledModes,
      isEmpty,
    );
    expect(
      RoutePriority.values.map((value) => value.name),
      ['fastest', 'fewerTransfers', 'lessWalking'],
    );
    expect(
      TransportMode.values.map((value) => value.name).toSet(),
      {'train', 'bus', 'jeep', 'uvExpress', 'tricycle'},
    );
  });

  test('queued tab updates merge and notify after persistence', () async {
    final store = await _store();
    var profileNotifications = 0, routesNotifications = 0;
    store
      ..addListener(() => profileNotifications++)
      ..addListener(() => routesNotifications++);

    await store.update(
      (profile) => profile.copyWith(savedPlaces: [_home, _work]),
    );
    await Future.wait([
      store.update(
        (profile) => profile.copyWith(favoriteRoutes: [_favorite]),
      ),
      store.update(
        (profile) => profile.copyWith(routePriority: RoutePriority.lessWalking),
      ),
    ]);

    expect(store.profile.favoriteRoutes.single.routeId, 'stable-route');
    expect(store.profile.routePriority, RoutePriority.lessWalking);
    expect((await store.load()).favoriteRoutes.single.routeId, 'stable-route');
    expect(profileNotifications, 3);
    expect(routesNotifications, 3);
    final saved =
        jsonDecode(
              (await SharedPreferences.getInstance()).getString(
                ProfileStore.storageKey,
              )!,
            )
            as Map<String, dynamic>;
    expect(saved['favoriteRoutes'], hasLength(1));
    expect(saved.containsKey('recurringCommutes'), isFalse);
  });

  test('legacy recurring commute data is discarded', () {
    final profile = ProfileData.fromJson({
      'savedPlaces': [_home.toJson(), _work.toJson()],
      'recurringCommutes': const [
        {'id': 'old-template'},
      ],
    });
    expect(profile.toJson().containsKey('recurringCommutes'), isFalse);
  });

  test('reset clears saved places and favorites', () async {
    final store = await _store();
    await store.update(
      (profile) => profile.copyWith(
        savedPlaces: [_home, _work],
        favoriteRoutes: [_favorite],
      ),
    );
    expect(await store.reset(), isTrue);
    expect(store.profile.savedPlaces, isEmpty);
    expect(store.profile.favoriteRoutes, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        ProfileStore.storageKey,
      ),
      isFalse,
    );
  });

  test('resetting an empty profile is successful and idempotent', () async {
    final store = await _store();
    expect(await store.reset(), isTrue);
    expect(store.profile.savedPlaces, isEmpty);
    expect(await store.reset(), isTrue);
  });

  test('application store references share one authoritative instance', () {
    expect(identical(ProfileStore(), ProfileStore()), isTrue);
  });
}
