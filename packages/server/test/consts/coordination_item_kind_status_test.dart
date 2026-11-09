import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/sql/questions_audience_sql.dart';
import 'package:tentura_server/data/database/sql/request_unread_sql.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/beacon_notification_copy_builder.dart';
import 'package:tentura_server/domain/policy/coordination_stale_rules.dart';

import '../support/coordination_item_record_fixtures.dart';

void main() {
  group('CoordinationItemKind', () {
    test('keeps the persisted smallint of every kind', () {
      expect(
        {
          for (final k in CoordinationItemKind.values) k: k.smallintValue,
        },
        {
          CoordinationItemKind.plan: 1,
          CoordinationItemKind.ask: 2,
          CoordinationItemKind.blocker: 3,
          CoordinationItemKind.promise: 5,
          CoordinationItemKind.planStep: 6,
          CoordinationItemKind.lobby: 7,
        },
      );
    });

    test('fromSmallint round-trips every kind', () {
      for (final k in CoordinationItemKind.values) {
        expect(CoordinationItemKind.fromSmallint(k.smallintValue), k);
      }
    });

    test('fromSmallint answers null for a value no kind carries', () {
      for (final v in [null, -1, 0, 4, 8, 100]) {
        expect(CoordinationItemKind.fromSmallint(v), isNull, reason: '$v');
      }
    });
  });

  group('CoordinationItemStatus', () {
    test('keeps the persisted smallint of every status', () {
      expect(
        {
          for (final s in CoordinationItemStatus.values) s: s.smallintValue,
        },
        {
          CoordinationItemStatus.open: 0,
          CoordinationItemStatus.accepted: 1,
          CoordinationItemStatus.resolved: 2,
          CoordinationItemStatus.cancelled: 3,
          CoordinationItemStatus.superseded: 4,
        },
      );
    });

    test('fromSmallint round-trips every status', () {
      for (final s in CoordinationItemStatus.values) {
        expect(CoordinationItemStatus.fromSmallint(s.smallintValue), s);
      }
    });

    test('fromSmallint answers null for a value no status carries', () {
      for (final v in [null, -1, 5, 9]) {
        expect(CoordinationItemStatus.fromSmallint(v), isNull, reason: '$v');
      }
    });
  });

  group('unknown stored values match no rule (as the int compares did)', () {
    final staleAt = DateTime.utc(2026, 6, 10);
    final now = DateTime.utc(2026, 6, 12);

    test('stale view of an unknown kind has no responsible user', () {
      final view = testCoordinationItem(
        id: 'i1',
        beaconId: 'b1',
        kind: 4,
        creatorId: 'c1',
        targetPersonId: 't1',
      ).staleView;
      expect(view.kind, isNull);
      expect(resolveResponsibleUserId(view), isNull);
      expect(isRemindableKind(view.kind), isFalse);
    });

    test('stale view of an unknown status is never stale', () {
      final view = testCoordinationItem(
        id: 'i1',
        beaconId: 'b1',
        kind: CoordinationItemKind.plan.smallintValue,
        status: 9,
        creatorId: 'c1',
        staleAt: staleAt,
      ).staleView;
      expect(view.status, isNull);
      expect(isItemStale(view, now), isFalse);
      expect(resolveResponsibleUserId(view), isNull);
    });

    test('notification copy names an unknown kind a commitment', () {
      const builder = BeaconNotificationCopyBuilder();
      String title(int? itemKind) => builder
          .build(
            intent: BeaconNotificationIntent(
              kind: NotificationKind.commitmentAccepted,
              priority: NotificationPriority.normal,
              beaconId: 'beacon-1',
              actorUserId: 'actor-1',
              coordinationItemKind: itemKind,
            ),
            actorDisplayName: 'Sam',
          )
          .title;
      expect(
        title(CoordinationItemKind.ask.smallintValue),
        'Sam accepted your ask',
      );
      for (final v in [null, 4, CoordinationItemKind.planStep.smallintValue]) {
        expect(title(v), 'Sam accepted your commitment', reason: '$v');
      }
    });
  });

  group('SQL built from the kinds keeps the literal smallint', () {
    test('Questions audience and unread scope the lobby as kind 7', () {
      expect(
        questionsAudienceCandidateIdsSql(r'$1'),
        contains(r'WHERE qa_ci.beacon_id = $1 AND qa_ci.kind = 7'),
      );
      expect(
        requestQuestionsUnreadCountSql(viewer: r'$1', beaconId: r'$2'),
        contains(r'WHERE ci.beacon_id = $2 AND ci.kind = 7'),
      );
    });
  });
}
