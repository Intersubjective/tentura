import 'package:test/test.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/coordination_stale_rules.dart';

void main() {
  group('validateStaleAfterDays', () {
    test('null defaults to 3', () {
      expect(validateStaleAfterDays(null), 3);
    });

    test('0 means no deadline', () {
      expect(validateStaleAfterDays(0), 0);
    });

    test('rejects out of range', () {
      expect(() => validateStaleAfterDays(-1), throwsArgumentError);
      expect(() => validateStaleAfterDays(91), throwsArgumentError);
    });
  });

  group('computeStaleAt', () {
    test('zero days returns null', () {
      expect(
        computeStaleAt(DateTime.utc(2026, 1, 1), 0),
        isNull,
      );
    });

    test('adds days', () {
      expect(
        computeStaleAt(DateTime.utc(2026, 1, 1), 3),
        DateTime.utc(2026, 1, 4),
      );
    });
  });

  group('resolveResponsibleUserId', () {
    test('open ask targets recipient', () {
      expect(
        resolveResponsibleUserId(
          const CoordinationStaleItemView(
            kind: coordinationItemKindAsk,
            status: coordinationItemStatusOpen,
            creatorId: 'c1',
            targetPersonId: 't1',
          ),
        ),
        't1',
      );
    });

    test('accepted ask uses acceptedById', () {
      expect(
        resolveResponsibleUserId(
          const CoordinationStaleItemView(
            kind: coordinationItemKindAsk,
            status: coordinationItemStatusAccepted,
            creatorId: 'c1',
            targetPersonId: 't1',
            acceptedById: 'a1',
          ),
        ),
        'a1',
      );
    });

    test('open promise targets recipient', () {
      expect(
        resolveResponsibleUserId(
          const CoordinationStaleItemView(
            kind: coordinationItemKindPromise,
            status: coordinationItemStatusOpen,
            creatorId: 'c1',
            targetPersonId: 't1',
          ),
        ),
        't1',
      );
    });

    test('accepted promise targets creator', () {
      expect(
        resolveResponsibleUserId(
          const CoordinationStaleItemView(
            kind: coordinationItemKindPromise,
            status: coordinationItemStatusAccepted,
            creatorId: 'c1',
            targetPersonId: 't1',
          ),
        ),
        'c1',
      );
    });

    test('blocker without target uses creator', () {
      expect(
        resolveResponsibleUserId(
          const CoordinationStaleItemView(
            kind: coordinationItemKindBlocker,
            status: coordinationItemStatusOpen,
            creatorId: 'c1',
          ),
        ),
        'c1',
      );
    });
  });

  group('isItemStale', () {
    test('active item past staleAt is stale', () {
      final now = DateTime.utc(2026, 6, 12);
      expect(
        isItemStale(
          CoordinationStaleItemView(
            kind: coordinationItemKindAsk,
            status: coordinationItemStatusOpen,
            creatorId: 'c1',
            staleAt: DateTime.utc(2026, 6, 10),
          ),
          now,
        ),
        isTrue,
      );
    });

    test('resolved item is never stale', () {
      expect(
        isItemStale(
          CoordinationStaleItemView(
            kind: coordinationItemKindAsk,
            status: coordinationItemStatusResolved,
            creatorId: 'c1',
            staleAt: DateTime.utc(2026, 6, 10),
          ),
          DateTime.utc(2026, 6, 12),
        ),
        isFalse,
      );
    });
  });

  group('computeStaleAtAfterAccept', () {
    test('null staleAfterDays defaults to 3 days', () {
      final now = DateTime.utc(2026, 6, 12, 12);
      expect(
        computeStaleAtAfterAccept(nowUtc: now, staleAfterDays: null),
        DateTime.utc(2026, 6, 15, 12),
      );
    });

    test('explicit 0 stays null', () {
      expect(
        computeStaleAtAfterAccept(
          nowUtc: DateTime.utc(2026, 6, 12),
          staleAfterDays: 0,
        ),
        isNull,
      );
    });

    test('honors stored window', () {
      expect(
        computeStaleAtAfterAccept(
          nowUtc: DateTime.utc(2026, 6, 12),
          staleAfterDays: 7,
        ),
        DateTime.utc(2026, 6, 19),
      );
    });
  });
}
