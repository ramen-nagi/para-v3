import 'package:flutter_test/flutter_test.dart';
import 'package:para_v3/services/commute_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'completed commutes are stored newest first and can be cleared',
    () async {
      final earlier = DateTime.utc(2026, 8, 15, 8);
      final later = DateTime.utc(2026, 8, 15, 18);

      await CommuteHistoryService.add(
        CommuteHistoryEntry(
          origin: 'Home',
          destination: 'Work',
          completedAt: earlier,
        ),
      );
      await CommuteHistoryService.add(
        CommuteHistoryEntry(
          origin: 'Work',
          destination: 'Home',
          completedAt: later,
        ),
      );

      final entries = await CommuteHistoryService.load();
      expect(entries, hasLength(2));
      expect(entries.first.origin, 'Work');
      expect(entries.first.completedAt, later);

      expect(await CommuteHistoryService.clear(), isTrue);
      expect(await CommuteHistoryService.clear(), isTrue);
      expect(await CommuteHistoryService.load(), isEmpty);
    },
  );
}
