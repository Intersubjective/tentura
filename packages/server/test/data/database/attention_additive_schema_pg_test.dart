@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// U04 — additive attention schema (`m0178`).
///
/// Every constraint here is proven by an offending write that must be
/// rejected *by name*; asserting the catalogue merely contains a constraint
/// would pass against a constraint that never fires.
Future<void> main() async {
  final freshTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U04_SCHEMA_TEST_DB',
    defaultNamePrefix: 'tentura_test_u04_fresh',
  );
  final upgradeTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U04_UPGRADE_TEST_DB',
    defaultNamePrefix: 'tentura_test_u04_upgrade',
  );
  final reachable = await canReachPostgresAdmin(freshTarget);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('m0178 on a fresh database', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: freshTarget);
      writer = session.writer;
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await _resetFixtures(writer);
    });

    test('adds the §0.1 columns and tables', () async {
      final columns = await writer.execute('''
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'notification_outbox'
  AND column_name IN (
    'cleared_at', 'clear_reason', 'cleared_by_operation_id',
    'logical_task_key', 'lifecycle_generation')
ORDER BY column_name
''');
      expect(
        columns.map((row) => [row[0], row[1], row[2]]).toList(),
        [
          ['clear_reason', 'text', 'YES'],
          ['cleared_at', 'timestamp with time zone', 'YES'],
          ['cleared_by_operation_id', 'text', 'YES'],
          ['lifecycle_generation', 'integer', 'YES'],
          ['logical_task_key', 'text', 'YES'],
        ],
      );

      final tables = await writer.execute('''
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN (
  'attention_clear_operation', 'attention_clear_operation_member',
  'attention_request_state')
ORDER BY table_name
''');
      expect(tables.map((row) => row[0]).toList(), [
        'attention_clear_operation',
        'attention_clear_operation_member',
        'attention_request_state',
      ]);
    });

    test('creates the partial indexes without CONCURRENTLY', () async {
      final indexes = await writer.execute('''
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'public' AND indexname IN (
  'notification_outbox__occurrence_account',
  'notification_outbox__live_logical_task',
  'notification_outbox__active_optional_beacon',
  'notification_outbox__live_obligation_beacon',
  'notification_outbox__cleared_by_operation')
ORDER BY indexname
''');
      expect(indexes.length, 5);
      for (final row in indexes) {
        expect(row[1]! as String, contains('WHERE'));
      }
      expect(
        indexes
            .firstWhere(
              (row) => row[0] == 'notification_outbox__occurrence_account',
            )[1]
            as String?,
        allOf(contains('UNIQUE'), contains('occurrence_id IS NOT NULL')),
      );
    });

    test('leaves every existing row unclear', () async {
      await _insertOptionalReceipt(writer, receiptId: 'Nu04opt1', seen: true);
      final rows = await writer.execute('''
SELECT count(*) FROM public.notification_outbox
WHERE cleared_at IS NOT NULL OR clear_reason IS NOT NULL
   OR cleared_by_operation_id IS NOT NULL
   OR logical_task_key IS NOT NULL OR lifecycle_generation IS NOT NULL
''');
      expect(rows.single[0], 0);
    });

    test('rejects clear metadata on an obligation', () async {
      await _insertObligation(writer, receiptId: 'Nu04obl1');
      await _expectConstraintViolation(
        () => writer.execute('''
UPDATE public.notification_outbox
SET cleared_at = now(), clear_reason = 'explicit'
WHERE id = 'Nu04obl1'
'''),
        'notification_outbox__clear_optional_only_chk',
      );
    });

    test('rejects a cleared receipt with no reason', () async {
      await _insertOptionalReceipt(writer, receiptId: 'Nu04opt2');
      await _expectConstraintViolation(
        () => writer.execute('''
UPDATE public.notification_outbox SET cleared_at = now()
WHERE id = 'Nu04opt2'
'''),
        'notification_outbox__clear_facts_chk',
      );
    });

    test('rejects a clear reason without a clear timestamp', () async {
      await _insertOptionalReceipt(writer, receiptId: 'Nu04opt3');
      await _expectConstraintViolation(
        () => writer.execute('''
UPDATE public.notification_outbox SET clear_reason = 'explicit'
WHERE id = 'Nu04opt3'
'''),
        'notification_outbox__clear_facts_chk',
      );
    });

    test('rejects an unknown clear reason', () async {
      await _insertOptionalReceipt(writer, receiptId: 'Nu04opt4');
      await _expectConstraintViolation(
        () => writer.execute('''
UPDATE public.notification_outbox
SET cleared_at = now(), clear_reason = 'because'
WHERE id = 'Nu04opt4'
'''),
        'notification_outbox__clear_reason_chk',
      );
    });

    test('accepts the U18 legacy_seen shape with no operation id', () async {
      await _insertOptionalReceipt(writer, receiptId: 'Nu04opt5', seen: true);
      await writer.execute('''
UPDATE public.notification_outbox
SET cleared_at = seen_at, clear_reason = 'legacy_seen'
WHERE id = 'Nu04opt5'
  AND NOT requires_action AND seen_at IS NOT NULL AND cleared_at IS NULL
''');
      final rows = await writer.execute('''
SELECT clear_reason, cleared_by_operation_id IS NULL
FROM public.notification_outbox WHERE id = 'Nu04opt5'
''');
      expect(rows.single[0], 'legacy_seen');
      expect(rows.single[1], isTrue);
    });

    test('accepts a sweep clear that names its operation', () async {
      await _insertOptionalReceipt(writer, receiptId: 'Nu04opt6');
      await _insertClearOperation(writer, operationId: 'OPu04a');
      await writer.execute('''
UPDATE public.notification_outbox
SET cleared_at = now(), clear_reason = 'sweep',
    cleared_by_operation_id = 'OPu04a'
WHERE id = 'Nu04opt6'
''');
      final rows = await writer.execute('''
SELECT cleared_by_operation_id FROM public.notification_outbox
WHERE id = 'Nu04opt6'
''');
      expect(rows.single[0], 'OPu04a');
    });

    test('rejects logical task columns on an optional receipt', () async {
      await _insertOptionalReceipt(writer, receiptId: 'Nu04opt7');
      await _expectConstraintViolation(
        () => writer.execute('''
UPDATE public.notification_outbox SET logical_task_key = 'task-1'
WHERE id = 'Nu04opt7'
'''),
        'notification_outbox__logical_task_chk',
      );
    });

    test('rejects a negative lifecycle generation', () async {
      await _insertObligation(writer, receiptId: 'Nu04obl2');
      await _expectConstraintViolation(
        () => writer.execute('''
UPDATE public.notification_outbox SET lifecycle_generation = -1
WHERE id = 'Nu04obl2'
'''),
        'notification_outbox__logical_task_chk',
      );
    });

    test('rejects a second receipt for one occurrence and account', () async {
      await _insertOccurrence(writer, occurrenceId: 'OCu04a');
      await _insertOptionalReceipt(
        writer,
        receiptId: 'Nu04occ1',
        occurrenceId: 'OCu04a',
      );
      await _expectConstraintViolation(
        () => _insertOptionalReceipt(
          writer,
          receiptId: 'Nu04occ2',
          occurrenceId: 'OCu04a',
        ),
        'notification_outbox__occurrence_account',
      );
    });

    test('still allows many receipts with no occurrence', () async {
      await _insertOptionalReceipt(writer, receiptId: 'Nu04null1');
      await _insertOptionalReceipt(writer, receiptId: 'Nu04null2');
      final rows = await writer.execute('''
SELECT count(*) FROM public.notification_outbox WHERE occurrence_id IS NULL
''');
      expect(rows.single[0], 2);
    });

    test('rejects two live obligations for one logical task', () async {
      await _insertObligation(
        writer,
        receiptId: 'Nu04task1',
        logicalTaskKey: 'task|u04',
      );
      await _expectConstraintViolation(
        () => _insertObligation(
          writer,
          receiptId: 'Nu04task2',
          logicalTaskKey: 'task|u04',
        ),
        'notification_outbox__live_logical_task',
      );
    });

    test('frees the logical task key once the obligation settles', () async {
      await _insertObligation(
        writer,
        receiptId: 'Nu04task3',
        logicalTaskKey: 'task|u04b',
      );
      await writer.execute('''
UPDATE public.notification_outbox
SET settlement_kind = 'superseded', settled_at = now()
WHERE id = 'Nu04task3'
''');
      await _insertObligation(
        writer,
        receiptId: 'Nu04task4',
        logicalTaskKey: 'task|u04b',
      );
      final rows = await writer.execute('''
SELECT count(*) FROM public.notification_outbox
WHERE logical_task_key = 'task|u04b'
''');
      expect(rows.single[0], 2);
    });

    test('captures sweep membership exactly once', () async {
      await _insertOptionalReceipt(writer, receiptId: 'Nu04mem1');
      await _insertClearOperation(writer, operationId: 'OPu04b');
      await writer.execute('''
INSERT INTO public.attention_clear_operation_member
  (operation_id, receipt_id, beacon_id, outcome_generation, state)
VALUES ('OPu04b', 'Nu04mem1', 'Bu04', 0, 'applied')
''');
      await _expectConstraintViolation(
        () => writer.execute('''
INSERT INTO public.attention_clear_operation_member
  (operation_id, receipt_id, beacon_id, outcome_generation, state)
VALUES ('OPu04b', 'Nu04mem1', 'Bu04', 1, 'skipped')
'''),
        'attention_clear_operation_member_pkey',
      );
    });

    test('rejects a negative sweep counter', () async {
      await _expectConstraintViolation(
        () => writer.execute('''
INSERT INTO public.attention_clear_operation
  (id, account_id, surface, status, applied)
VALUES ('OPu04neg', 'Uu04', 'activity', 'captured', -1)
'''),
        'attention_clear_operation__counters_chk',
      );
    });

    test('keeps one Request state row per viewer and Request', () async {
      await writer.execute('''
INSERT INTO public.attention_request_state
  (account_id, beacon_id, first_entry_at, outcome_generation, decision_revision)
VALUES ('Uu04', 'Bu04', now(), 0, 0)
''');
      await _expectConstraintViolation(
        () => writer.execute('''
INSERT INTO public.attention_request_state
  (account_id, beacon_id, first_entry_at, outcome_generation, decision_revision)
VALUES ('Uu04', 'Bu04', now(), 1, 1)
'''),
        'attention_request_state_pkey',
      );
    });

    test('rejects a negative Request state generation', () async {
      await _expectConstraintViolation(
        () => writer.execute('''
INSERT INTO public.attention_request_state
  (account_id, beacon_id, outcome_generation, decision_revision)
VALUES ('Uu04', 'Bu04', -1, 0)
'''),
        'attention_request_state__generations_chk',
      );
    });

    test('re-applying every m0178 statement is a no-op', () async {
      // migrant records the version once and would never re-run the
      // migration, so restart safety is proven by replaying the statements
      // themselves against the already-upgraded database — twice.
      final statements = migrationsForTesting
          .firstWhere((migration) => migration.version == '0178')
          .statements;
      for (var pass = 0; pass < 2; pass++) {
        for (final statement in statements) {
          await writer.execute(statement);
        }
      }

      final constraints = await writer.execute('''
SELECT conname, count(*) FROM pg_constraint
WHERE conrelid = 'public.notification_outbox'::regclass
  AND conname LIKE 'notification_outbox__cleared%'
   OR conname LIKE 'notification_outbox__clear_%'
   OR conname = 'notification_outbox__logical_task_chk'
GROUP BY conname ORDER BY conname
''');
      expect(constraints, isNotEmpty);
      for (final row in constraints) {
        expect(row[1], 1, reason: 'duplicate constraint ${row[0]}');
      }

      final columns = await writer.execute('''
SELECT count(*) FROM information_schema.columns
WHERE table_name = 'notification_outbox'
  AND column_name IN ('cleared_at', 'clear_reason', 'cleared_by_operation_id',
                      'logical_task_key', 'lifecycle_generation')
''');
      expect(columns.single[0], 5);
    });
  }, skip: skipReason);

  group('m0178 upgrade path from 0177', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    final notifications = <Map<String, dynamic>>[];

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(
        target: upgradeTarget,
        lastInclusiveVersion: '0177',
      );
      writer = session.writer;

      // Production-shaped data written while the schema is still at 0177.
      await _resetFixtures(writer);
      await _insertOptionalReceipt(
        writer,
        receiptId: 'Nu04legacy',
        seen: true,
      );
      await _insertOccurrence(writer, occurrenceId: 'OCu04legacy');
      await _insertOptionalReceipt(
        writer,
        receiptId: 'Nu04modern',
        occurrenceId: 'OCu04legacy',
      );
      await _insertObligation(writer, receiptId: 'Nu04live');
      await _insertObligation(writer, receiptId: 'Nu04settled');
      await writer.execute('''
UPDATE public.notification_outbox
SET settlement_kind = 'resolved', settled_at = now()
WHERE id = 'Nu04settled'
''');

      await migrateDbSchemaThrough(writer, '0178');

      listener = await Connection.open(
        upgradeTarget.databaseEnv.pgEndpoint,
        settings: upgradeTarget.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      notificationSubscription = listener.channels['entity_changes'].listen(
        (payload) =>
            notifications.add(jsonDecode(payload) as Map<String, dynamic>),
      );
      await _settle();
      notifications.clear();
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await notificationSubscription.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session);
    });

    test('preserves every pre-existing row untouched', () async {
      final rows = await writer.execute('''
SELECT id, occurrence_id, seen_at IS NOT NULL, cleared_at, clear_reason,
       logical_task_key, lifecycle_generation
FROM public.notification_outbox ORDER BY id
''');
      expect(rows.length, 4);
      expect(rows.map((row) => row[0]).toList(), [
        'Nu04legacy',
        'Nu04live',
        'Nu04modern',
        'Nu04settled',
      ]);
      for (final row in rows) {
        expect(row[3], isNull, reason: 'cleared_at on ${row[0]}');
        expect(row[4], isNull, reason: 'clear_reason on ${row[0]}');
        expect(row[5], isNull, reason: 'logical_task_key on ${row[0]}');
        expect(row[6], isNull, reason: 'lifecycle_generation on ${row[0]}');
      }
      // The legacy row keeps a NULL occurrence and its seen_at.
      expect(rows.first[1], isNull);
      expect(rows.first[2], isTrue);
    });

    test('enforces the new constraints on upgraded rows', () async {
      await _expectConstraintViolation(
        () => writer.execute('''
UPDATE public.notification_outbox
SET cleared_at = now(), clear_reason = 'explicit' WHERE id = 'Nu04live'
'''),
        'notification_outbox__clear_optional_only_chk',
      );
      await _expectConstraintViolation(
        () => _insertOptionalReceipt(
          writer,
          receiptId: 'Nu04dupe',
          occurrenceId: 'OCu04legacy',
        ),
        'notification_outbox__occurrence_account',
      );
    });

    test('backfills the U18 legacy_seen shape on the upgraded row', () async {
      await writer.execute('''
UPDATE public.notification_outbox
SET cleared_at = seen_at, clear_reason = 'legacy_seen'
WHERE NOT requires_action AND seen_at IS NOT NULL AND cleared_at IS NULL
''');
      final rows = await writer.execute('''
SELECT id FROM public.notification_outbox
WHERE clear_reason = 'legacy_seen' ORDER BY id
''');
      expect(rows.map((row) => row[0]).toList(), ['Nu04legacy']);
      await writer.execute('''
UPDATE public.notification_outbox
SET cleared_at = NULL, clear_reason = NULL WHERE clear_reason = 'legacy_seen'
''');
    });

    test('emits a realtime update when clear state changes', () async {
      notifications.clear();
      await writer.execute('''
UPDATE public.notification_outbox
SET cleared_at = now(), clear_reason = 'explicit'
WHERE id = 'Nu04modern'
''');
      await _waitUntil(() => _notificationUpdates(notifications).isNotEmpty);
      expect(_notificationUpdates(notifications), [
        {
          'event': 'update',
          'entity': 'notification',
          'id': 'Uu04',
          'user_ids': ['Uu04'],
        },
      ]);

      notifications.clear();
      await writer.execute('''
UPDATE public.notification_outbox
SET logical_task_key = 'task|notify', lifecycle_generation = 1
WHERE id = 'Nu04live'
''');
      await _waitUntil(() => _notificationUpdates(notifications).isNotEmpty);
      expect(_notificationUpdates(notifications).length, 1);

      await writer.execute('''
UPDATE public.notification_outbox
SET cleared_at = NULL, clear_reason = NULL WHERE id = 'Nu04modern'
''');
      await writer.execute('''
UPDATE public.notification_outbox
SET logical_task_key = NULL, lifecycle_generation = NULL
WHERE id = 'Nu04live'
''');
      await _settle();
    });
  }, skip: skipReason);

  group('m0178 preflight', () {
    late DisposablePgTarget preflightTarget;

    setUp(() {
      preflightTarget = DisposablePgTarget.fromNamedEnvironment(
        envVarName: 'TENTURA_U04_PREFLIGHT_TEST_DB',
        defaultNamePrefix: 'tentura_test_u04_preflight',
      );
    });

    test('aborts by naming duplicate occurrence/account pairs', () async {
      final session = await setUpDisposablePgWriter(
        target: preflightTarget,
        lastInclusiveVersion: '0177',
      );
      final writer = session.writer;
      try {
        await _resetFixtures(writer);
        await _insertOccurrence(writer, occurrenceId: 'OCu04dup');
        await _insertOptionalReceipt(
          writer,
          receiptId: 'Nu04dupA',
          occurrenceId: 'OCu04dup',
        );
        await _insertOptionalReceipt(
          writer,
          receiptId: 'Nu04dupB',
          occurrenceId: 'OCu04dup',
        );

        await expectLater(
          migrateDbSchemaThrough(writer, '0178'),
          throwsA(
            isA<ServerException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('m0178 preflight failed'),
                contains('occurrence_id=OCu04dup'),
                contains('account_id=Uu04'),
              ),
            ),
          ),
        );

        final version = await writer.execute('''
SELECT version FROM public.schema_version ORDER BY version DESC LIMIT 1
''');
        expect(version.single[0], '0177');
      } finally {
        await tearDownDisposablePgWriter(session: session);
      }
    });
  }, skip: skipReason);
}

Future<void> _expectConstraintViolation(
  Future<void> Function() action,
  String constraintName,
) => expectLater(
  action(),
  throwsA(
    isA<ServerException>().having(
      (error) => error.constraintName,
      'constraintName',
      constraintName,
    ),
  ),
);

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE public.notification_outbox, public.attention_occurrence,
  public.beacon, public."user" CASCADE
''');
  await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('Uu04', 'U04 schema', 'u04-schema-public-key')
''');
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES ('Bu04', 'Uu04', 'U04 request', 'U04 request description')
''');
}

Future<void> _insertOccurrence(
  Connection writer, {
  required String occurrenceId,
}) => writer.execute('''
INSERT INTO public.attention_occurrence
  (id, source_event_key, event_type, immutable_payload)
VALUES ('$occurrenceId', 'src-$occurrenceId', 'fixture', '{}'::jsonb)
''');

Future<void> _insertClearOperation(
  Connection writer, {
  required String operationId,
}) => writer.execute('''
INSERT INTO public.attention_clear_operation (id, account_id, surface, status)
VALUES ('$operationId', 'Uu04', 'activity', 'captured')
''');

Future<void> _insertOptionalReceipt(
  Connection writer, {
  required String receiptId,
  String? occurrenceId,
  bool seen = false,
}) => writer.execute('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy, requires_action, occurrence_id
) VALUES (
  '$receiptId', 'Uu04', 'activity', 'comment', 'normal',
  'Optional', 'Optional body', '/attention', 'dedup-$receiptId',
  '2026-09-16T12:00:00Z'::timestamptz,
  ${seen ? "'2026-09-17T12:00:00Z'::timestamptz" : 'NULL'},
  'Bu04', 'source-$receiptId',
  'beacon', 'beacon_commented', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content', false,
  ${occurrenceId == null ? 'NULL' : "'$occurrenceId'"}
)
''');

Future<void> _insertObligation(
  Connection writer, {
  required String receiptId,
  String? logicalTaskKey,
}) => writer.execute('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key${logicalTaskKey == null ? '' : ', logical_task_key'}
) VALUES (
  '$receiptId', 'Uu04', 'asksOfMe', 'needsMe', 'normal',
  'Obligation', 'Obligation body', '/attention', 'dedup-$receiptId',
  '2026-09-16T12:00:00Z'::timestamptz,
  'Bu04', 'source-$receiptId',
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  true, 'v1|needsMe|$receiptId|Uu04'${logicalTaskKey == null ? '' : ", '$logicalTaskKey'"}
)
''');

List<Map<String, dynamic>> _notificationUpdates(
  List<Map<String, dynamic>> notifications,
) => notifications
    .where(
      (message) =>
          message['entity'] == 'notification' && message['event'] == 'update',
    )
    .toList();

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.timestamp().add(timeout);
  while (!condition()) {
    if (DateTime.timestamp().isAfter(deadline)) {
      fail('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));
