import 'package:test/test.dart';

import 'package:tentura/domain/entity/coordination_item.dart';

void main() {
  group('CoordinationItemEventKind.fromInt', () {
    test('returns null for unknown values', () {
      expect(CoordinationItemEventKind.fromInt(99), isNull);
    });

    test('parses known values', () {
      expect(
        CoordinationItemEventKind.fromInt(2),
        CoordinationItemEventKind.accepted,
      );
    });
  });

  group('CoordinationItem stale helpers', () {
    test('isStale when past deadline and active', () {
      final item = CoordinationItem(
        id: '1',
        beaconId: 'b',
        kind: CoordinationItemKind.ask,
        status: CoordinationItemStatus.open,
        creatorId: 'c',
        targetPersonId: 't',
        createdAt: DateTime.utc(2026, 6),
        updatedAt: DateTime.utc(2026, 6),
        staleAt: DateTime.utc(2026, 6, 10),
      );
      expect(
        item.isStale,
        isTrue,
      );
    });

    test('canRemind excludes responsible viewer', () {
      final item = CoordinationItem(
        id: '1',
        beaconId: 'b',
        kind: CoordinationItemKind.ask,
        status: CoordinationItemStatus.open,
        creatorId: 'c',
        targetPersonId: 't',
        createdAt: DateTime.utc(2026, 6),
        updatedAt: DateTime.utc(2026, 6),
        staleAt: DateTime.utc(2026, 6, 10),
      );
      expect(item.canRemind('observer'), isTrue);
      expect(item.canRemind('t'), isFalse);
    });
  });
}
