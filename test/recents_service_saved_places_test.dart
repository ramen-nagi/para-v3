import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/autocomplete_geocoding_service.dart';
import 'package:para_v3/services/recents_service.dart';

void main() {
  late Directory tempDirectory;
  late RecentsService service;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('para_recents_test_');
    service = RecentsService.forTesting(
      '${tempDirectory.path}${Platform.pathSeparator}user_info.sqlite',
    );
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test('deletes only the saved place matching the requested key', () async {
    SavedPlace place(String key, String label, double latitude) => SavedPlace(
      key: key,
      label: label,
      suggestion: PlaceSuggestion(
        placeId: '${key}_place',
        mainText: '$label address',
        secondaryText: 'Metro Manila',
        fullText: '$label address, Metro Manila',
      ),
      position: Position(121, latitude),
    );

    await service.savePlace(place('home', 'Home', 14.5));
    await service.savePlace(place('work', 'Work', 14.6));

    await service.deleteSavedPlace('home');

    expect(await service.getSavedPlaceByKey('home'), isNull);
    expect((await service.getSavedPlaces()).map((place) => place.key), [
      'work',
    ]);
  });
}
