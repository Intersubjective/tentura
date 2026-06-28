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
    final staleAt = DateTime.utc(2026, 6, 10, 12);

    CoordinationItem activeAsk({DateTime? stale}) => CoordinationItem(
          id: '1',
          beaconId: 'b',
          kind: CoordinationItemKind.ask,
          status: CoordinationItemStatus.open,
          creatorId: 'c',
          targetPersonId: 't',
          createdAt: DateTime.utc(2026, 6),
          updatedAt: DateTime.utc(2026, 6),
          staleAt: stale ?? staleAt,
        );

    test('isStale when past deadline and active', () {
      expect(activeAsk().isStale, isTrue);
    });

    test('canRemind excludes responsible viewer', () {
      final item = activeAsk();
      expect(item.canRemind('observer'), isTrue);
      expect(item.canRemind('t'), isFalse);
    });

    test('staleOverdueDuration returns null before deadline', () {
      final item = activeAsk();
      expect(
        item.staleOverdueDuration(DateTime.utc(2026, 6, 10, 11)),
        isNull,
      );
    });

    test('staleOverdueLabelAmount uses minutes, hours, days buckets', () {
      final item = activeAsk();
      expect(
        item.staleOverdueLabelAmount(DateTime.utc(2026, 6, 10, 12, 30)),
        30,
      );
      expect(
        item.staleOverdueLabelAmount(DateTime.utc(2026, 6, 10, 14)),
        2,
      );
      expect(
        item.staleOverdueLabelAmount(DateTime.utc(2026, 6, 13, 12)),
        3,
      );
    });

    test('staleOverdueLabelAmount minimum is 1 minute', () {
      final item = activeAsk();
      expect(
        item.staleOverdueLabelAmount(DateTime.utc(2026, 6, 10, 12)),
        1,
      );
    });

    test('nextStaleOverdueLabelChangeAt before deadline is staleAt', () {
      final item = activeAsk();
      expect(
        item.nextStaleOverdueLabelChangeAt(DateTime.utc(2026, 6, 10, 11)),
        staleAt,
      );
    });

    test('nextStaleOverdueLabelChangeAt after deadline steps buckets', () {
      final item = activeAsk();
      expect(
        item.nextStaleOverdueLabelChangeAt(DateTime.utc(2026, 6, 10, 12, 30)),
        DateTime.utc(2026, 6, 10, 12, 31),
      );
      expect(
        item.nextStaleOverdueLabelChangeAt(DateTime.utc(2026, 6, 10, 14)),
        DateTime.utc(2026, 6, 10, 15),
      );
      expect(
        item.nextStaleOverdueLabelChangeAt(DateTime.utc(2026, 6, 13, 12)),
        DateTime.utc(2026, 6, 14, 12),
      );
    });
  });
}
