@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';

/// U09a step 1 + the amended §0.1 — the two schema facts the sweep stands on.
///
/// Both halves are asserted the way U08 asserted its constraints: by naming
/// what must be permitted *and* what must still be refused. A test that only
/// proved "the dismissal succeeded" would keep passing if the guard were
/// loosened into admitting a forged stance transition.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U09A_OUTCOME_TEST_DB',
    defaultNamePrefix: 'tentura_test_u09a_outcome',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late Connection writer;

  setUpAll(() async {
    if (skipReason != false) return;
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
  });

  tearDownAll(() async {
    if (skipReason != false) return;
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    if (skipReason != false) return;
    await _resetFixtures(writer);
  });

  group('every outcome kind is dismissible', () {
    // Before m0183 the trigger admitted `tombstone_dismissed_at` only on
    // statuses 3 and 4, so three of the five outcome kinds could not be
    // dismissed at all. This is the whole point of the migration.
    for (final kind in const [
      (status: 0, name: 'helping / unanswered forward (0)'),
      (status: 1, name: 'watching (1)'),
      (status: 2, name: 'notInterested (2)'),
      (status: 3, name: 'closedBeforeResponse (3)'),
      (status: 4, name: 'deletedBeforeResponse (4)'),
    ]) {
      test('${kind.name} can be dismissed', () async {
        await _insertInboxItem(writer, status: kind.status);

        await writer.execute(
          Sql.named('''
UPDATE public.inbox_item SET tombstone_dismissed_at = now()
 WHERE user_id = @userId AND beacon_id = @beaconId
'''),
          parameters: {'userId': _viewerId, 'beaconId': _beaconId},
        );

        expect(await _dismissedAt(writer), isNotNull);
      });
    }

    test('a dismissal can be undone — U09c restores, it does not re-decide', () async {
      await _insertInboxItem(writer, status: 1);
      await writer.execute(
        "UPDATE public.inbox_item SET tombstone_dismissed_at = now() "
        "WHERE user_id = '$_viewerId'",
      );
      expect(await _dismissedAt(writer), isNotNull);

      await writer.execute(
        "UPDATE public.inbox_item SET tombstone_dismissed_at = NULL "
        "WHERE user_id = '$_viewerId'",
      );

      expect(await _dismissedAt(writer), isNull);
    });
  }, skip: skipReason);

  group('the guard still refuses what it should', () {
    test('a tombstone row cannot change its status', () async {
      await _insertInboxItem(writer, status: 3);

      // Even with the beacon trigger's flag borrowed, a tombstone row is
      // frozen: the guard refuses before it ever reaches the upgrade rule.
      await expectLater(
        _withTombstoneTransitionAllowed(
          writer,
          "UPDATE public.inbox_item SET status = 4 WHERE user_id = '$_viewerId'",
        ),
        throwsA(
          isA<ServerException>().having(
            (error) => error.message,
            'message',
            contains('cannot change status or rejection_message'),
          ),
        ),
      );
    });

    test('a tombstone row cannot change its rejection_message', () async {
      await _insertInboxItem(writer, status: 3);

      await expectLater(
        writer.execute(
          "UPDATE public.inbox_item SET rejection_message = 'forged' "
          "WHERE user_id = '$_viewerId'",
        ),
        throwsA(
          isA<ServerException>().having(
            (error) => error.message,
            'message',
            contains('cannot change status or rejection_message'),
          ),
        ),
      );
    });

    test('a client cannot forge a transition into a tombstone status', () async {
      await _insertInboxItem(writer, status: 1);

      await expectLater(
        writer.execute(
          "UPDATE public.inbox_item SET status = 3 WHERE user_id = '$_viewerId'",
        ),
        throwsA(
          isA<ServerException>().having(
            (error) => error.message,
            'message',
            contains('cannot transition to tombstone status without beacon trigger'),
          ),
        ),
      );
      final status = await writer.execute(
        "SELECT status FROM public.inbox_item WHERE user_id = '$_viewerId'",
      );
      expect(status.first.first, 1);
    });

    test('a client cannot insert a tombstone row directly', () async {
      await expectLater(
        writer.execute(
          Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@userId, @beaconId, 4, 0, now(), '', '')
'''),
          parameters: {'userId': _viewerId, 'beaconId': _otherBeaconId},
        ),
        throwsA(
          isA<ServerException>().having(
            (error) => error.message,
            'message',
            contains('cannot insert tombstone status without beacon trigger'),
          ),
        ),
      );
    });
  }, skip: skipReason);

  group('a sweep member is a receipt or an outcome, never both', () {
    // Manifest §0.1 as amended after the U09 scout: a tombstone is not a
    // receipt, so `receipt_id` had to become nullable — and the moment it did,
    // a member with neither target became representable. The CHECK is what
    // keeps U09b from recording a sweep of nothing.
    setUp(() async {
      if (skipReason != false) return;
      await _insertOperation(writer);
    });

    test('an outcome member needs no receipt', () async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.attention_clear_operation_member
  (operation_id, receipt_id, beacon_id, outcome_beacon_id, outcome_generation, state)
VALUES (@op, NULL, @beaconId, @beaconId, 0, 'applied')
'''),
        parameters: {'op': _operationId, 'beaconId': _beaconId},
      );

      final rows = await writer.execute(
        'SELECT receipt_id, outcome_beacon_id '
        'FROM public.attention_clear_operation_member '
        "WHERE operation_id = '$_operationId'",
      );
      expect(rows.first[0], isNull);
      expect(rows.first[1], _beaconId);
    });

    test(
      'a member with neither target is refused by '
      'attention_clear_operation_member__member_target_chk',
      () async {
        await expectLater(
          writer.execute(
            Sql.named('''
INSERT INTO public.attention_clear_operation_member
  (operation_id, receipt_id, beacon_id, outcome_beacon_id, outcome_generation, state)
VALUES (@op, NULL, @beaconId, NULL, 0, 'applied')
'''),
            parameters: {'op': _operationId, 'beaconId': _beaconId},
          ),
          throwsA(
            isA<ServerException>().having(
              (error) => error.constraintName,
              'constraintName',
              'attention_clear_operation_member__member_target_chk',
            ),
          ),
        );
      },
    );

    test(
      'a member with both targets is refused by '
      'attention_clear_operation_member__member_target_chk',
      () async {
        await _insertReceipt(writer, id: 'Nu09amixed');

        await expectLater(
          writer.execute(
            Sql.named('''
INSERT INTO public.attention_clear_operation_member
  (operation_id, receipt_id, beacon_id, outcome_beacon_id, outcome_generation, state)
VALUES (@op, 'Nu09amixed', @beaconId, @beaconId, 0, 'applied')
'''),
            parameters: {'op': _operationId, 'beaconId': _beaconId},
          ),
          throwsA(
            isA<ServerException>().having(
              (error) => error.constraintName,
              'constraintName',
              'attention_clear_operation_member__member_target_chk',
            ),
          ),
        );
      },
    );

    test('outcome membership is still captured once per operation', () async {
      Future<void> insert() => writer.execute(
        Sql.named('''
INSERT INTO public.attention_clear_operation_member
  (operation_id, receipt_id, beacon_id, outcome_beacon_id, outcome_generation, state)
VALUES (@op, NULL, @beaconId, @beaconId, 0, 'applied')
ON CONFLICT (operation_id, outcome_beacon_id)
  WHERE outcome_beacon_id IS NOT NULL DO NOTHING
'''),
        parameters: {'op': _operationId, 'beaconId': _beaconId},
      );

      await insert();
      await insert();

      final count = await writer.execute(
        'SELECT count(*)::int FROM public.attention_clear_operation_member '
        "WHERE operation_id = '$_operationId'",
      );
      expect(count.first.first, 1);
    });

    test('receipt membership is still captured once per operation', () async {
      await _insertReceipt(writer, id: 'Nu09aonce');
      Future<void> insert() => writer.execute(
        Sql.named('''
INSERT INTO public.attention_clear_operation_member
  (operation_id, receipt_id, beacon_id, outcome_generation, state)
VALUES (@op, 'Nu09aonce', @beaconId, 0, 'applied')
ON CONFLICT (operation_id, receipt_id)
  WHERE receipt_id IS NOT NULL DO NOTHING
'''),
        parameters: {'op': _operationId, 'beaconId': _beaconId},
      );

      await insert();
      await insert();

      final count = await writer.execute(
        'SELECT count(*)::int FROM public.attention_clear_operation_member '
        "WHERE operation_id = '$_operationId'",
      );
      expect(count.first.first, 1);
    });
  }, skip: skipReason);
}

const _viewerId = 'Uu09aout01';
const _authorId = 'Uu09aout02';
const _beaconId = 'Bu09aout01';
const _otherBeaconId = 'Bu09aout02';
const _operationId = 'OPu09aout';

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.inbox_item,
  public.attention_clear_operation,
  public.attention_request_state,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_viewerId, _authorId]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': '$id-key'},
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES
  (@beaconId, @authorId, 'Outcome', 'Outcome request', 0),
  (@otherBeaconId, @authorId, 'Other', 'Other request', 0)
'''),
    parameters: {
      'beaconId': _beaconId,
      'otherBeaconId': _otherBeaconId,
      'authorId': _authorId,
    },
  );
}

/// Statuses 3 and 4 may only be written with the beacon trigger's flag, so the
/// fixture borrows it for exactly one statement, inside one transaction.
Future<void> _insertInboxItem(
  Connection writer, {
  required int status,
  String beaconId = _beaconId,
}) => _withTombstoneTransitionAllowed(
  writer,
  '''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES ('$_viewerId', '$beaconId', $status, 1, now(), '', '')
''',
);

Future<void> _withTombstoneTransitionAllowed(
  Connection writer,
  String statement,
) => writer.runTx((tx) async {
  await tx.execute(
    "SELECT set_config('tentura.allow_inbox_tombstone_transition', '1', true)",
  );
  await tx.execute(statement);
});

Future<DateTime?> _dismissedAt(Connection writer) async {
  final rows = await writer.execute(
    'SELECT tombstone_dismissed_at FROM public.inbox_item '
    "WHERE user_id = '$_viewerId' AND beacon_id = '$_beaconId'",
  );
  return rows.first.first as DateTime?;
}

Future<void> _insertOperation(Connection writer) => writer.execute(
  Sql.named('''
INSERT INTO public.attention_clear_operation (id, account_id, surface, status)
VALUES (@id, @accountId, 'activity', 'pending')
'''),
  parameters: {'id': _operationId, 'accountId': _viewerId},
);

Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  String beaconId = _beaconId,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedupKey, now(),
  @beaconId, @sourceEventKey,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  false
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
  },
);
