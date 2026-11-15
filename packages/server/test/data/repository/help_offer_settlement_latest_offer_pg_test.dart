@Tags(['pg'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_reconciliation_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';

import '../../support/disposable_pg_target.dart';

/// A helper may offer help, withdraw, and offer again on the same Request:
/// the offer row is reused and a new `offered` commitment event (kind 0) and
/// a new «new help offer» obligation are recorded. The settle rule must judge
/// only the history after the latest offer, so the new obligation stays live
/// until the author answers it or the helper withdraws again.
///
/// Commitment event kinds: 0 offered, 1 acknowledged, 2 softened,
/// 3 withdrawn by helper, 4 released by author, 5 removed from chat,
/// 7 blocked cleanup.
void main() {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HELP_OFFER_LATEST_OFFER_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_offer_latest',
  );
  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = TenturaDb(target.databaseEnv);
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  AttentionReconciliationRepository reconcile() =>
      AttentionReconciliationRepository(database);

  group(
    'settling help-offer obligations looks only after the latest offer',
    () {
      test('offer, withdraw, offer again: the new obligation stays live after '
          'the settle', () async {
        final s = await _Scenario.seed(writer, 'rw', events: [0, 3, 0]);
        await s.obligation(writer);

        await reconcile().settleObsoleteHelpOfferObligations(
          accountId: s.author,
        );

        final row = await s.row(writer);
        expect(
          row.kind,
          isNull,
          reason: 'the re-offer is waiting for the author',
        );
        expect(row.settledAt, isNull);
      });

      test('admitted, withdrawn, then offered again: the new obligation stays '
          'live after the settle', () async {
        final s = await _Scenario.seed(writer, 'ra', events: [0, 1, 3, 0]);
        await s.obligation(writer);

        await reconcile().settleObsoleteHelpOfferObligations(
          accountId: s.author,
        );

        final row = await s.row(writer);
        expect(
          row.kind,
          isNull,
          reason: 'an earlier admission does not answer a later offer',
        );
        expect(row.settledAt, isNull);
      });

      for (final kind in [1, 2, 4]) {
        test('an answer (kind $kind) after the latest offer settles the '
            'obligation as resolved', () async {
          final s = await _Scenario.seed(
            writer,
            'an$kind',
            events: [0, 3, 0, kind],
          );
          await s.obligation(writer);

          await reconcile().settleObsoleteHelpOfferObligations(
            accountId: s.author,
          );

          final row = await s.row(writer);
          expect(row.kind, 'resolved');
          expect(row.settledAt, isNotNull);
          expect(row.settledBy, isNull);
        });
      }

      for (final kind in [3, 5, 7]) {
        test('a withdrawal (kind $kind) after the latest offer settles the '
            'obligation as superseded', () async {
          final s = await _Scenario.seed(
            writer,
            'wd$kind',
            events: [0, 1, 0, kind],
          );
          await s.obligation(writer);

          await reconcile().settleObsoleteHelpOfferObligations(
            accountId: s.author,
          );

          final row = await s.row(writer);
          expect(row.kind, 'superseded');
          expect(row.settledAt, isNotNull);
        });
      }
    },
  );

  group(
    "reading the author's attention keeps a re-offer's obligation live",
    () {
      test(
        'after offer, withdraw, offer again, the summary read leaves the new '
        'obligation unsettled and counts it as an open action item',
        () async {
          final s = await _Scenario.seed(writer, 'sr', events: [0, 3, 0]);
          await s.obligation(writer);

          final summary = await AttentionRepository(
            database,
          ).surfaceSummary(accountId: s.author);

          final row = await s.row(writer);
          expect(row.kind, isNull);
          expect(row.settledAt, isNull);
          expect(
            summary.myDeskCount,
            1,
            reason: 'the re-offer is still waiting for the author',
          );
        },
      );
    },
  );

  group(
    'help offers missing an obligation are found after the latest offer',
    () {
      test('offer, withdraw, offer again with no live obligation is listed as '
          'one task to restore', () async {
        final s = await _Scenario.seed(writer, 'lw', events: [0, 3, 0]);

        final tasks = await reconcile().listUnbackedHelpOfferTasks(
          accountId: s.author,
        );

        expect(
          [for (final t in tasks) (t.beaconId, t.helpOffererId)],
          [(s.beacon, s.helper)],
        );
      });

      test('admitted, withdrawn, offered again with no live obligation is '
          'listed as one task to restore', () async {
        final s = await _Scenario.seed(writer, 'la', events: [0, 1, 3, 0]);

        final tasks = await reconcile().listUnbackedHelpOfferTasks(
          accountId: s.author,
        );

        expect(
          [for (final t in tasks) (t.beaconId, t.helpOffererId)],
          [(s.beacon, s.helper)],
        );
      });

      test('an admission after the latest offer means there is nothing to '
          'restore', () async {
        final s = await _Scenario.seed(writer, 'lx', events: [0, 3, 0, 1]);

        final tasks = await reconcile().listUnbackedHelpOfferTasks(
          accountId: s.author,
        );

        expect(
          [for (final t in tasks) (t.beaconId, t.helpOffererId)],
          isNot(contains((s.beacon, s.helper))),
        );
      });
    },
  );

  group('the settle never overwrites a concurrent settlement', () {
    test('a dismiss committed while the settle waits on the row keeps its '
        'settlement, and the settle reports nothing updated', () async {
      // Without the dismiss this row would be superseded: the helper
      // withdrew after the latest offer.
      final s = await _Scenario.seed(writer, 'cc', events: [0, 3]);
      await s.obligation(writer);

      final a = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      try {
        final aPid =
            (await a.execute('SELECT pg_backend_pid()')).single.single! as int;
        await a.execute('BEGIN ISOLATION LEVEL READ COMMITTED');
        await a.execute(
          Sql.named('''
UPDATE public.notification_outbox
SET settlement_kind = 'dismissed',
    settled_at = '2026-09-01T10:00:00Z'::timestamptz,
    settled_by_user_id = @author
WHERE id = @id
'''),
          parameters: {'author': s.author, 'id': s.receiptId},
        );

        final settle = reconcile()
            .settleObsoleteHelpOfferObligations(accountId: s.author)
            .timeout(const Duration(seconds: 30));
        var settleDone = false;
        unawaited(settle.then((_) => settleDone = true, onError: (_) {}));

        await _waitForBlockedBy(writer, aPid, isDone: () => settleDone);
        await a.execute('COMMIT');

        final updated = await settle;
        final row = await s.row(writer);
        expect(row.kind, 'dismissed');
        expect(
          row.settledAt,
          DateTime.parse('2026-09-01T10:00:00Z'),
        );
        expect(row.settledBy, s.author);
        expect(updated, 0, reason: 'the settle must not touch a settled row');
      } finally {
        await a.close();
      }
    });
  });
}

/// Waits until some session is blocked by the backend [blockerPid].
Future<void> _waitForBlockedBy(
  Connection probe,
  int blockerPid, {
  required bool Function() isDone,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (isDone()) {
      fail('the settle finished without waiting for the uncommitted dismiss');
    }
    final rows = await probe.execute(
      Sql.named(
        'SELECT count(*) FROM pg_stat_activity '
        'WHERE @blocker = ANY(pg_blocking_pids(pid))',
      ),
      parameters: {'blocker': blockerPid},
    );
    if ((rows.single.single! as int) > 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('the settle never blocked on the row the dismiss holds');
}

typedef _Row = ({String? kind, DateTime? settledAt, String? settledBy});

/// One author, one helper, one open Request, the helper's offer row in its
/// current state (active, no withdraw reason) and the commitment events in
/// the given order — later events get a higher `seq`.
final class _Scenario {
  _Scenario(String code)
    : author = 'Ulatst${code}a01',
      helper = 'Ulatst${code}h01',
      beacon = 'Blatst${code}01',
      receiptId = 'Nlatst$code';

  final String author;
  final String helper;
  final String beacon;
  final String receiptId;

  static Future<_Scenario> seed(
    Connection writer,
    String code, {
    required List<int> events,
  }) async {
    final s = _Scenario(code);
    for (final id in [s.author, s.helper]) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, 'key-' || @id)
'''),
        parameters: {'id': id},
      );
    }
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @author, 'Request', 'desc', @status)
'''),
      parameters: {
        'id': s.beacon,
        'author': s.author,
        'status': BeaconStatus.open.smallintValue,
      },
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_help_offer
  (beacon_id, user_id, message, status, offer_kind, stake_state, withdraw_reason)
VALUES (@beaconId, @userId, 'offer', 0, 0, 1, NULL)
'''),
      parameters: {'beaconId': s.beacon, 'userId': s.helper},
    );
    var i = 0;
    for (final kind in events) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_commitment_event
  (id, beacon_id, user_id, actor_user_id, kind)
VALUES (@id, @beaconId, @userId, @actor, @kind)
'''),
        parameters: {
          'id': 'Clatst$code${i++}',
          'beaconId': s.beacon,
          'userId': s.helper,
          'actor': (kind == 0 || kind == 3) ? s.helper : s.author,
          'kind': kind,
        },
      );
    }
    return s;
  }

  /// The live «new help offer» obligation for the latest offer.
  Future<void> obligation(Connection writer) async {
    const eventType = 'helpOfferSubmitted';
    final sourceEventKey = 'latest-offer:$receiptId';
    final occurrence = await writer.execute(
      Sql.named('''
INSERT INTO public.attention_occurrence
  (source_event_key, event_type, actor_user_id, immutable_payload)
VALUES (@key, @eventType, @actor, '{"eventType":"fixture"}'::jsonb)
RETURNING id
'''),
      parameters: {
        'key': sourceEventKey,
        'eventType': eventType,
        'actor': helper,
      },
    );
    final occurrenceId = occurrence.single[0]! as String;
    await writer.execute(
      Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key, occurrence_id, target_entity_id,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key,
  logical_task_key, lifecycle_generation
) VALUES (
  @id, @accountId, 'asksOfMe', 'commitmentEvent', 'normal',
  'Obligation', 'Obligation body', '/attention', @dedupKey,
  now(),
  @beaconId, @sourceEventKey, @occurrenceId, @targetEntityId,
  'beacon', 'help_offer_submitted', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  TRUE, @threadKey,
  @logicalTaskKey, 2
)
'''),
      parameters: {
        'id': receiptId,
        'accountId': author,
        'dedupKey': 'dedup-$receiptId',
        'beaconId': beacon,
        'sourceEventKey': sourceEventKey,
        'occurrenceId': occurrenceId,
        'targetEntityId': helper,
        'threadKey': 'v1|$eventType|$beacon|$author',
        'logicalTaskKey': 'v1|$eventType|$beacon|$helper|$author',
      },
    );
  }

  Future<_Row> row(Connection writer) async {
    final result = await writer.execute(
      Sql.named('''
SELECT settlement_kind, settled_at, settled_by_user_id
FROM public.notification_outbox
WHERE id = @id
'''),
      parameters: {'id': receiptId},
    );
    final r = result.single;
    return (
      kind: r[0] as String?,
      settledAt: r[1] as DateTime?,
      settledBy: r[2] as String?,
    );
  }
}
