import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'beacon_view_case_test_support.dart';

// Desloppify (client beacon_view): BeaconViewCase fetchers that fall back to
// empty data on a failure keep that fallback, and now leave a FINE record on
// the case's logger naming the fetcher (they used to swallow it silently).
void main() {
  group('BeaconViewCase.fetchFactCards fallback', () {
    late Level previousLevel;

    setUp(() {
      previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
    });

    tearDown(() {
      Logger.root.level = previousLevel;
    });

    test('a throwing fact-card port still yields an empty list', () async {
      final repo = FakeBeaconViewFactCardRepository(
        listError: StateError('boom'),
      );
      final viewCase = buildTestBeaconViewCase(factCardsRepo: repo);

      final cards = await viewCase.fetchFactCards('B1');

      expect(cards, isEmpty);
      expect(repo.listCalls, 1);
    });

    test('the swallowed failure is logged at FINE with the error', () async {
      final error = StateError('boom');
      final viewCase = buildTestBeaconViewCase(
        factCardsRepo: FakeBeaconViewFactCardRepository(listError: error),
      );
      final records = <LogRecord>[];
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(sub.cancel);

      final cards = await viewCase.fetchFactCards('B1');

      expect(cards, isEmpty);
      final fetcherRecords = records
          .where((r) => r.loggerName == 'test')
          .where((r) => r.message.contains('fetchFactCards'))
          .toList();
      expect(fetcherRecords, hasLength(1));
      expect(fetcherRecords.single.level, Level.FINE);
      expect(fetcherRecords.single.error, same(error));
      expect(fetcherRecords.single.stackTrace, isNotNull);
    });
  });
}
