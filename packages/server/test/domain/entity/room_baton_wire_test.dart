import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/room_baton.dart';

// Pins the batonData decode the room repository uses since
// «decode baton status/response via BatonStatus/BatonResponse»: the wire names
// are the ones the old inline switches produced, and a smallint outside the
// DB CHECK (status/response IN (0, 1, 2), m0219) now throws instead of
// falling back to 'collecting' / 'waiting'.
void main() {
  group('BatonStatus', () {
    test('wireName is the batonData status string', () {
      expect(
        {for (final s in BatonStatus.values) s.smallintValue: s.wireName},
        {0: 'collecting', 1: 'taken', 2: 'cancelled'},
      );
    });

    test('fromSmallint round-trips and rejects an unknown value', () {
      for (final s in BatonStatus.values) {
        expect(BatonStatus.fromSmallint(s.smallintValue), s);
      }
      expect(() => BatonStatus.fromSmallint(3), throwsArgumentError);
    });
  });

  group('BatonResponse', () {
    test('wireName is the batonData response string', () {
      expect(
        {for (final r in BatonResponse.values) r.smallintValue: r.wireName},
        {0: 'waiting', 1: 'can_help', 2: 'cant_help'},
      );
    });

    test('fromSmallint round-trips and rejects an unknown value', () {
      for (final r in BatonResponse.values) {
        expect(BatonResponse.fromSmallint(r.smallintValue), r);
      }
      expect(() => BatonResponse.fromSmallint(-1), throwsArgumentError);
    });
  });

  test('manual selection mode is smallint 2', () {
    expect(BatonSelectionMode.manual.smallintValue, 2);
  });
}
