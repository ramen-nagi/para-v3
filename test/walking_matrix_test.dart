import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:para_v3/services/mapbox_services.dart';

void main() {
  setUp(
    () => dotenv.loadFromString(envString: 'MAPBOX_ACCESS_TOKEN=test-token'),
  );
  tearDown(() => dotenv.clean());

  for (final response in [
    http.Response('unavailable', 503),
    http.Response('{"distances":[]}', 200),
  ]) {
    test(
      'advances batches after ${response.statusCode} / ${response.body}',
      () async {
        final requests = <Uri>[];
        final result = await http
            .runWithClient(
              () => MapMatchingService.fetchWalkingDistances(
                Position(121, 14.6),
                {
                  for (var i = 0; i < 49; i++)
                    'stop_$i': Position(121, 14.61 + i * 0.0001),
                },
              ),
              () => MockClient((request) async {
                requests.add(request.url);
                // Stop a regression immediately instead of allowing an endless retry.
                if (requests.length > 3) {
                  await Future<void>.delayed(const Duration(milliseconds: 10));
                  throw StateError('Repeated matrix batch');
                }
                return response;
              }),
            )
            .timeout(const Duration(seconds: 2));
        expect(result, isEmpty);
        expect(requests, hasLength(3));
        expect(requests.toSet(), hasLength(3));
      },
    );
  }
}
