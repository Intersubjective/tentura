@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/notification_outbox_repository.dart';
import 'package:tentura_server/data/repository/notification_preference_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';
  final env = target.databaseEnv;

  group('m0114-m0118 realtime notification contract', () {
    late Connection writer;
    late Connection listener;
    late TenturaDb database;
    late NotificationOutboxRepository outboxRepository;
    late NotificationPreferenceRepository preferenceRepository;
    late AttentionRepository attentionRepository;
    late AttentionSettlementRepository settlementRepository;
    late StreamSubscription<String> notificationSubscription;
    var writerOpened = false;
    var listenerOpened = false;
    var databaseCreated = false;
    var notificationSubscriptionCreated = false;
    final notifications = <Map<String, dynamic>>[];
    final migrationNotifications = <Map<String, dynamic>>[];

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        env.pgEndpoint,
        settings: env.pgEndpointSettings,
      );
      writerOpened = true;
      // MeritRank functions are provisioned outside Dart migrations. This
      // disposable database does not execute them, so defer SQL-body checks
      // while reconstructing the legacy schema from the checked-in history.
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      await _rollBackM0119ForTest(writer);
      await _rollBackM0118ForTest(writer);
      await _rollBackM0117ForTest(writer);
      await _rollBackM0116ForTest(writer);
      // Restore the disposable database to its exact pre-m0115 shape so the
      // checked-in migration is exercised over a real legacy row below.
      await _rollBackM0115ForTest(writer);

      // Reapply m0114's idempotent statements before observing the expansion,
      // ensuring the trigger contract comes from this checkout.
      for (final statement in m0114.statements) {
        await writer.execute(statement);
      }
      await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('Ut01migration', 'T-01 migration', 't01-migration-public-key')
''');
      await writer.execute(r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, title, body, action_url, priority,
  read_at, dedup_key
) VALUES (
  'Nt01legacy', 'Ut01migration', 'asksOfMe', 'needsMe',
  'Legacy', 'Legacy body', '/legacy', 'normal',
  '2026-07-16T10:00:00Z', 't01-legacy'
)
''');
      await writer.execute(r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, title, body, action_url, priority,
  read_at, dedup_key
)
SELECT
  'Nt01backfill' || lpad(i::text, 4, '0'),
  'Ut01migration', 'coordination', 'coordinationChanged',
  'Backfill', 'Backfill body', '/backfill', 'normal',
  '2026-07-16T10:00:00Z', 't01-backfill-' || i::text
FROM generate_series(1, 500) AS i
''');

      listener = await Connection.open(
        env.pgEndpoint,
        settings: env.pgEndpointSettings,
      );
      listenerOpened = true;
      await listener.execute('LISTEN entity_changes');
      notificationSubscription = listener.channels['entity_changes'].listen(
        (payload) => notifications.add(
          jsonDecode(payload) as Map<String, dynamic>,
        ),
      );
      notificationSubscriptionCreated = true;

      await migrateDbSchema(writer);
      await _settle();
      migrationNotifications.addAll(notifications);
      notifications.clear();

      // The runner must be safe to invoke again without reapplying either
      // checked-in Updates migration.
      await migrateDbSchema(writer);

      database = TenturaDb(env);
      databaseCreated = true;
      outboxRepository = NotificationOutboxRepository(database);
      preferenceRepository = NotificationPreferenceRepository(database);
      attentionRepository = AttentionRepository(database);
      settlementRepository = AttentionSettlementRepository(database);
    });

    setUp(() async {
      await _settle();
      notifications.clear();
    });

    tearDownAll(() async {
      if (databaseCreated) {
        await database.close();
      }
      if (notificationSubscriptionCreated) {
        await notificationSubscription.cancel();
      }
      if (listenerOpened) {
        await listener.close();
      }
      if (writerOpened) {
        await writer.close();
      }
      await target.drop();
    });

    test(
      'm0115 expands and m0116 backfills under the statement publisher',
      () async {
        expect(migrationNotifications, [
          {
            'event': 'update',
            'entity': 'notification',
            'id': 'Ut01migration',
            'user_ids': ['Ut01migration'],
          },
        ]);

        final legacy = await writer.execute(r'''
SELECT read_at, seen_at
FROM public.notification_outbox
WHERE id = 'Nt01legacy'
''');
        expect(legacy.single[0], isNotNull);
        expect(legacy.single[1], legacy.single[0]);

        final backfill = await writer.execute(r'''
SELECT count(*)::int
FROM public.notification_outbox
WHERE id LIKE 'Nt01backfill%' AND seen_at = read_at
''');
        expect(backfill.single.single, 500);

        final versions = await writer.execute(r'''
SELECT version
FROM public.schema_version
WHERE version IN ('0115', '0116')
ORDER BY version
''');
        expect(versions.map((row) => row.single), ['0115', '0116']);

        final triggers = await writer.execute(r'''
SELECT t.tgname, p.proname, (t.tgtype & 1) = 0,
       pg_get_triggerdef(t.oid)
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE t.tgrelid = 'public.notification_outbox'::regclass
  AND NOT t.tgisinternal
ORDER BY t.tgname
''');
        expect(
          triggers.map((row) => (row[0], row[1], row[2])),
          [
            (
              'notification_outbox_delete_notify',
              'notify_notification_outbox_delete',
              true,
            ),
            (
              'notification_outbox_insert_notify',
              'notify_notification_outbox_insert',
              true,
            ),
            (
              'notification_outbox_update_notify',
              'notify_notification_outbox_update',
              true,
            ),
          ],
        );
        expect(triggers[0][3], contains('REFERENCING OLD TABLE AS old_rows'));
        expect(triggers[1][3], contains('REFERENCING NEW TABLE AS new_rows'));
        expect(
          triggers[2][3],
          allOf(
            contains('REFERENCING OLD TABLE AS old_rows'),
            contains('NEW TABLE AS new_rows'),
          ),
        );
      },
    );

    test(
      'm0115 and m0118 columns, defaults, checks, and index predicates match C1',
      () async {
        final columnRows = await writer.execute(r'''
SELECT table_name, column_name, data_type, udt_name, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    (table_name = 'notification_outbox' AND column_name IN (
      'seen_at', 'source_event_key', 'destination_kind', 'target_entity_id',
      'presentation_key', 'presentation_payload', 'in_app_preference_class',
      'suppression_class', 'access_policy', 'requires_action',
      'attention_thread_key', 'settlement_kind', 'settled_at',
      'settled_by_user_id', 'settled_by_occurrence_id'
    ))
    OR (table_name = 'notification_preference'
        AND column_name = 'muted_in_app_event_classes')
  )
ORDER BY table_name, column_name
''');
        final columns = {
          for (final row in columnRows)
            '${row[0]}.${row[1]}': (
              dataType: row[2],
              udtName: row[3],
              nullable: row[4],
              defaultValue: row[5],
            ),
        };
        expect(columns, hasLength(16));
        expect(
          columns['notification_outbox.seen_at']?.dataType,
          'timestamp with time zone',
        );
        expect(columns['notification_outbox.seen_at']?.nullable, 'YES');
        expect(columns['notification_outbox.seen_at']?.defaultValue, isNull);
        for (final name in const [
          'source_event_key',
          'destination_kind',
          'target_entity_id',
          'presentation_key',
          'in_app_preference_class',
        ]) {
          expect(columns['notification_outbox.$name']?.dataType, 'text');
          expect(columns['notification_outbox.$name']?.nullable, 'YES');
        }
        expect(
          columns['notification_outbox.presentation_payload']?.dataType,
          'jsonb',
        );
        expect(
          columns['notification_outbox.presentation_payload']?.nullable,
          'NO',
        );
        expect(
          columns['notification_outbox.presentation_payload']?.defaultValue,
          "'{}'::jsonb",
        );
        expect(
          columns['notification_outbox.suppression_class']?.defaultValue,
          "'standard'::text",
        );
        expect(
          columns['notification_outbox.access_policy']?.defaultValue,
          "'legacy'::text",
        );
        expect(
          columns['notification_outbox.requires_action']?.dataType,
          'boolean',
        );
        expect(
          columns['notification_outbox.requires_action']?.nullable,
          'NO',
        );
        expect(
          columns['notification_outbox.requires_action']?.defaultValue,
          'false',
        );
        for (final name in const [
          'attention_thread_key',
          'settlement_kind',
          'settled_by_user_id',
          'settled_by_occurrence_id',
        ]) {
          expect(columns['notification_outbox.$name']?.dataType, 'text');
          expect(columns['notification_outbox.$name']?.nullable, 'YES');
        }
        expect(
          columns['notification_outbox.settled_at']?.dataType,
          'timestamp with time zone',
        );
        expect(columns['notification_outbox.settled_at']?.nullable, 'YES');
        expect(
          columns['notification_preference.muted_in_app_event_classes']
              ?.udtName,
          '_text',
        );
        expect(
          columns['notification_preference.muted_in_app_event_classes']
              ?.nullable,
          'NO',
        );
        expect(
          columns['notification_preference.muted_in_app_event_classes']
              ?.defaultValue,
          "'{}'::text[]",
        );

        final checkRows = await writer.execute(r'''
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.notification_outbox'::regclass
  AND conname LIKE 'notification_outbox__%_chk'
ORDER BY conname
''');
        final checks = {
          for (final row in checkRows) row[0]! as String: row[1]! as String,
        };
        expect(checks.keys, {
          'notification_outbox__access_policy_chk',
          'notification_outbox__beacon_policy_chk',
          'notification_outbox__new_shape_chk',
          'notification_outbox__preference_class_chk',
          'notification_outbox__recipient_safe_chk',
          'notification_outbox__settlement_facts_chk',
          'notification_outbox__settlement_kind_chk',
          'notification_outbox__settlement_obligation_chk',
          'notification_outbox__suppression_chk',
          'notification_outbox__thread_key_chk',
        });
        expect(
          checks['notification_outbox__suppression_chk'],
          allOf(contains('mandatory'), contains('standard'), contains('noisy')),
        );
        expect(
          checks['notification_outbox__access_policy_chk'],
          allOf(
            contains('legacy'),
            contains('beacon_content'),
            contains('beacon_tombstone'),
            contains('recipient_safe'),
            contains('profile'),
          ),
        );
        expect(
          checks['notification_outbox__preference_class_chk'],
          allOf(contains('in_app_preference_class'), contains('noisy')),
        );
        expect(
          checks['notification_outbox__beacon_policy_chk'],
          allOf(
            contains('beacon_content'),
            contains('beacon_tombstone'),
            contains('beacon_id'),
          ),
        );
        expect(
          checks['notification_outbox__recipient_safe_chk'],
          allOf(
            contains('recipient_safe'),
            contains('room_member_removed'),
            contains('offer_declined'),
            contains('offer_removed'),
          ),
        );
        expect(
          checks['notification_outbox__new_shape_chk'],
          allOf(
            contains('source_event_key'),
            contains('destination_kind'),
            contains('presentation_key'),
          ),
        );
        expect(
          checks['notification_outbox__settlement_kind_chk'],
          allOf(
            contains('resolved'),
            contains('dismissed'),
            contains('superseded'),
            contains('legacy_archived'),
          ),
        );
        expect(
          checks['notification_outbox__settlement_facts_chk'],
          allOf(contains('settlement_kind'), contains('settled_at')),
        );
        expect(
          checks['notification_outbox__thread_key_chk'],
          allOf(contains('requires_action'), contains('v1')),
        );

        final indexRows = await writer.execute(r'''
SELECT c.relname, pg_get_indexdef(i.indexrelid),
       pg_get_expr(i.indpred, i.indrelid)
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
WHERE i.indrelid = 'public.notification_outbox'::regclass
  AND c.relname IN (
    'notification_outbox__dedup',
    'notification_outbox__unread',
    'notification_outbox__feed_v2',
    'notification_outbox__live_obligation',
    'notification_outbox__live_obligation_thread'
  )
ORDER BY c.relname
''');
        final indexes = {
          for (final row in indexRows)
            row[0]! as String: (
              definition: row[1]! as String,
              predicate: row[2] as String?,
            ),
        };
        expect(indexes, hasLength(5));
        expect(
          indexes['notification_outbox__dedup']?.definition,
          startsWith('CREATE UNIQUE INDEX'),
        );
        expect(
          indexes['notification_outbox__dedup']?.predicate,
          '(read_at IS NULL)',
        );
        expect(
          indexes['notification_outbox__unread']?.definition,
          contains('(account_id, created_at DESC, id DESC)'),
        );
        expect(
          indexes['notification_outbox__unread']?.predicate,
          '(COALESCE(seen_at, read_at) IS NULL)',
        );
        expect(
          indexes['notification_outbox__feed_v2']?.definition,
          contains('(account_id, created_at DESC, id DESC)'),
        );
        expect(indexes['notification_outbox__feed_v2']?.predicate, isNull);
        expect(
          indexes['notification_outbox__live_obligation']?.predicate,
          '(requires_action AND (settlement_kind IS NULL))',
        );
        expect(
          indexes['notification_outbox__live_obligation_thread']?.predicate,
          allOf(
            contains('requires_action'),
            contains('(settlement_kind IS NULL)'),
            contains('(attention_thread_key IS NOT NULL)'),
          ),
        );
      },
    );

    test(
      'statement publishers emit once per affected account and operation',
      () async {
        const otherAccountId = 'Ut01publisherother';
        await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (
  'Ut01publisherother',
  'T-01 publisher other',
  't01-publisher-other-public-key'
)
''');
        addTearDown(() async {
          await writer.execute(r'''
DELETE FROM public."user" WHERE id = 'Ut01publisherother'
''');
        });
        await _settle();
        notifications.clear();

        List<Map<String, dynamic>> changes() =>
            _ofKind(notifications, 'notification');

        Future<void> expectAccountChanges(String event) async {
          await _waitUntil(() => changes().length >= 2);
          await _settle();
          expect(
            changes().map(
              (message) => (
                message['event'],
                message['id'],
                (message['user_ids']! as List).join(','),
              ),
            ),
            unorderedEquals([
              (event, 'Ut01migration', 'Ut01migration'),
              (event, otherAccountId, otherAccountId),
            ]),
          );
          notifications.clear();
        }

        await writer.execute(r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, title, body, action_url, priority, dedup_key
) VALUES
  (
    'Nt01publisher1', 'Ut01migration', 'asksOfMe', 'needsMe',
    'Publisher 1', 'Body', '/publisher/1', 'normal', 't01-publisher-1'
  ),
  (
    'Nt01publisher2', 'Ut01migration', 'asksOfMe', 'needsMe',
    'Publisher 2', 'Body', '/publisher/2', 'normal', 't01-publisher-2'
  ),
  (
    'Nt01publisher3', 'Ut01publisherother', 'asksOfMe', 'needsMe',
    'Publisher 3', 'Body', '/publisher/3', 'normal', 't01-publisher-3'
  )
''');
        await expectAccountChanges('insert');

        await writer.execute(r'''
UPDATE public.notification_outbox
SET title = title || ' updated'
WHERE id LIKE 'Nt01publisher%'
''');
        await expectAccountChanges('update');

        await writer.execute(r'''
UPDATE public.notification_outbox
SET emailed_at = now(), digested_at = now()
WHERE id LIKE 'Nt01publisher%'
''');
        await _settle();
        expect(changes(), isEmpty);

        await writer.execute(r'''
DELETE FROM public.notification_outbox
WHERE id LIKE 'Nt01publisher%'
''');
        await expectAccountChanges('delete');
      },
    );

    test('1/50/500-row acknowledgement updates each emit one hint', () async {
      await writer.execute(r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, title, body, action_url, priority,
  dedup_key, target_entity_id
)
SELECT
  'Nt01budget' || lpad(i::text, 4, '0'),
  'Ut01migration', 'asksOfMe', 'needsMe',
  'Budget', 'Budget body', '/budget', 'normal',
  't01-budget-' || i::text, i::text
FROM generate_series(1, 551) AS i
''');
      addTearDown(() async {
        await writer.execute(r'''
DELETE FROM public.notification_outbox WHERE id LIKE 'Nt01budget%'
''');
      });
      await _waitUntil(
        () => _ofKind(notifications, 'notification').isNotEmpty,
      );
      await _settle();
      expect(_ofKind(notifications, 'notification'), hasLength(1));
      notifications.clear();

      Future<void> acknowledgeRange(
        int start,
        int end,
        int expectedRows,
      ) async {
        await writer.execute(
          Sql.named(r'''
UPDATE public.notification_outbox
SET seen_at = now()
WHERE id LIKE 'Nt01budget%'
  AND target_entity_id::int BETWEEN @start AND @end
'''),
          parameters: {'start': start, 'end': end},
        );
        await _waitUntil(
          () => _ofKind(notifications, 'notification').isNotEmpty,
        );
        await _settle();
        expect(_ofKind(notifications, 'notification'), [
          {
            'event': 'update',
            'entity': 'notification',
            'id': 'Ut01migration',
            'user_ids': ['Ut01migration'],
          },
        ]);
        final seenRows = await writer.execute(
          Sql.named(r'''
SELECT count(*)::int
FROM public.notification_outbox
WHERE id LIKE 'Nt01budget%'
  AND seen_at IS NOT NULL
  AND target_entity_id::int BETWEEN @start AND @end
'''),
          parameters: {'start': start, 'end': end},
        );
        expect(seenRows.single.single, expectedRows);
        notifications.clear();
      }

      await acknowledgeRange(1, 1, 1);
      await acknowledgeRange(2, 51, 50);
      await acknowledgeRange(52, 551, 500);
    });

    test('m0115 checks reject every invalid receipt shape', () async {
      var sequence = 0;
      Future<void> expectRejected(String columns, String values) async {
        sequence += 1;
        await expectLater(
          writer.execute('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, title, body, action_url, priority, dedup_key,
  $columns
) VALUES (
  'Nt01invalid$sequence', 'Ut01migration', 'asksOfMe', 'needsMe',
  'Invalid', 'Invalid', '/invalid', 'normal', 't01-invalid-$sequence',
  $values
)
'''),
          throwsA(isA<ServerException>()),
        );
      }

      await expectRejected('suppression_class', "'other'");
      await expectRejected('access_policy', "'other'");
      await expectRejected(
        'in_app_preference_class, suppression_class',
        "'room_activity', 'standard'",
      );
      await expectRejected('access_policy', "'beacon_content'");
      await expectRejected('access_policy', "'beacon_tombstone'");
      await expectRejected('access_policy', "'recipient_safe'");
      await expectRejected(
        'access_policy, presentation_key',
        "'recipient_safe', 'not_allowlisted'",
      );
      await expectRejected('source_event_key', "'event:1'");
      await expectRejected(
        'source_event_key, destination_kind',
        "'event:2', 'profile'",
      );
      await expectRejected('requires_action', 'true');
      await expectRejected('attention_thread_key', "'v1|needsMe|item|user'");
      await expectRejected(
        'requires_action, attention_thread_key',
        "true, 'not-versioned'",
      );
      await expectRejected('settlement_kind', "'unknown'");
      await expectRejected(
        'requires_action, attention_thread_key, settlement_kind',
        "true, 'v1|needsMe|item|user', 'resolved'",
      );
      await expectRejected(
        'settled_at',
        "'2026-07-17T00:00:00Z'",
      );
    });

    test(
      'settlement is authorized, idempotent, and independent from seen state',
      () async {
        const receiptId = 'Nt01settlement';
        const mandatoryReceiptId = 'Nt01mandatorysettlement';
        await writer.execute(r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, title, body, action_url, priority, dedup_key,
  requires_action, attention_thread_key, seen_at
) VALUES (
  'Nt01settlement', 'Ut01migration', 'asksOfMe', 'needsMe',
  'Settle', 'Settle body', '/settle', 'normal', 't01-settlement',
  true, 'v1|needsMe|item-1|Ut01migration', '2026-07-17T00:00:00Z'
)
''');
        await writer.execute(r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, title, body, action_url, priority, dedup_key,
  suppression_class, requires_action, attention_thread_key
) VALUES (
  'Nt01mandatorysettlement', 'Ut01migration', 'asksOfMe', 'needsMe',
  'Mandatory', 'Mandatory body', '/mandatory', 'normal', 't01-mandatory-settlement',
  'mandatory', true, 'v1|needsMe|item-2|Ut01migration'
)
''');

        final beforeSettlement = await attentionRepository.attentionFeed(
          accountId: 'Ut01migration',
          view: AttentionFeedView.needsYou,
        );
        expect(beforeSettlement.summary.needsYouTotal, 2);
        expect(
          beforeSettlement.page.items.map((item) => item.id),
          containsAll([receiptId, mandatoryReceiptId]),
        );

        expect(
          await settlementRepository.settle(
            accountId: 'Ut01other',
            receiptId: receiptId,
            kind: AttentionSettlementKind.resolved,
          ),
          0,
        );
        expect(
          await settlementRepository.settle(
            accountId: 'Ut01migration',
            receiptId: mandatoryReceiptId,
            kind: AttentionSettlementKind.dismissed,
          ),
          0,
        );
        expect(
          await settlementRepository.settle(
            accountId: 'Ut01migration',
            receiptId: receiptId,
            kind: AttentionSettlementKind.dismissed,
          ),
          1,
        );
        expect(
          await settlementRepository.settle(
            accountId: 'Ut01migration',
            receiptId: receiptId,
            kind: AttentionSettlementKind.resolved,
          ),
          0,
        );

        final settled = await writer.execute(r'''
SELECT seen_at, settlement_kind, settled_at, settled_by_user_id
FROM public.notification_outbox
WHERE id = 'Nt01settlement'
''');
        expect(settled.single[0], DateTime.parse('2026-07-17T00:00:00Z'));
        expect(settled.single[1], 'dismissed');
        expect(settled.single[2], isNotNull);
        expect(settled.single[3], 'Ut01migration');

        final afterDismissal = await attentionRepository.attentionFeed(
          accountId: 'Ut01migration',
          view: AttentionFeedView.needsYou,
        );
        expect(afterDismissal.summary.needsYouTotal, 1);
        expect(
          afterDismissal.page.items.map((item) => item.id),
          [mandatoryReceiptId],
        );

        final legacy = await writer.execute(r'''
SELECT requires_action, settlement_kind
FROM public.notification_outbox
WHERE id = 'Nt01legacy'
''');
        expect(legacy.single, [false, null]);
      },
    );

    test('legacy collapse SQL and partial unique index remain exact', () async {
      const dedupKey = 't01-collapse';
      for (var i = 0; i < 2; i++) {
        await outboxRepository.enqueue(
          accountId: 'Ut01migration',
          category: NotificationCategory.asksOfMe,
          kind: NotificationKind.needsMe,
          priority: NotificationPriority.normal,
          title: 'Collapse $i',
          body: 'Body $i',
          actionUrl: '/collapse',
          dedupKey: dedupKey,
        );
      }
      final collapsed = await writer.execute(r'''
SELECT count(*)::int, max(collapsed_count)::int,
       min(suppression_class), min(access_policy)
FROM public.notification_outbox
WHERE dedup_key = 't01-collapse'
''');
      expect(collapsed.single, [1, 2, 'standard', 'legacy']);

      await writer.execute(r'''
UPDATE public.notification_outbox
SET read_at = now()
WHERE dedup_key = 't01-collapse'
''');
      await outboxRepository.enqueue(
        accountId: 'Ut01migration',
        category: NotificationCategory.asksOfMe,
        kind: NotificationKind.needsMe,
        priority: NotificationPriority.normal,
        title: 'New unread receipt',
        body: 'New body',
        actionUrl: '/collapse/new',
        dedupKey: dedupKey,
      );
      final rows = await writer.execute(r'''
SELECT count(*)::int
FROM public.notification_outbox
WHERE dedup_key = 't01-collapse'
''');
      expect(rows.single.single, 2);
    });

    test('repositories round-trip new receipt and preference fields', () async {
      await writer.execute(r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, title, body, action_url, priority, dedup_key,
  seen_at, source_event_key, destination_kind, target_entity_id,
  presentation_key, presentation_payload, in_app_preference_class,
  suppression_class, access_policy
) VALUES (
  'Nt01roundtrip', 'Ut01migration', 'coordination', 'coordinationChanged',
  'Round trip', 'Round trip body', '/round-trip', 'high', 't01-round-trip',
  '2026-07-16T12:00:00Z', 'activity:42', 'profile', 'Utarget',
  'relationship_formed', '{"count":2,"label":"safe"}'::jsonb,
  'relationship_activity', 'noisy', 'profile'
)
''');
      final receipt = (await outboxRepository.feedForAccount(
        accountId: 'Ut01migration',
        limit: 100,
      )).singleWhere((item) => item.id == 'Nt01roundtrip');
      expect(receipt.seenAt, DateTime.parse('2026-07-16T12:00:00Z'));
      expect(receipt.sourceEventKey, 'activity:42');
      expect(receipt.destinationKind, 'profile');
      expect(receipt.targetEntityId, 'Utarget');
      expect(receipt.presentationKey, 'relationship_formed');
      expect(receipt.presentationPayload, {'count': 2, 'label': 'safe'});
      expect(receipt.inAppPreferenceClass, 'relationship_activity');
      expect(receipt.suppressionClass, 'noisy');
      expect(receipt.accessPolicy, 'profile');
      expect(receipt.readAt, isNull);
      expect(receipt.isRead, isFalse);

      await writer.execute(r'''
INSERT INTO public.notification_preference (account_id)
VALUES ('Ut01migration')
''');
      final preferenceDefault = await writer.execute(r'''
SELECT muted_in_app_event_classes, cardinality(muted_in_app_event_classes)
FROM public.notification_preference
WHERE account_id = 'Ut01migration'
''');
      expect(preferenceDefault.single[0], isEmpty);
      expect(preferenceDefault.single[1], 0);

      await preferenceRepository.upsert(
        NotificationPreferencesEntity(
          accountId: 'Ut01migration',
          mutedInAppEventClasses: const {
            'room_activity',
            'status_activity',
          },
          snoozeUntil: DateTime.parse('2026-07-17T12:00:00Z'),
        ),
      );
      final preferences = await preferenceRepository.getForAccount(
        'Ut01migration',
      );
      expect(
        preferences.mutedInAppEventClasses,
        {'room_activity', 'status_activity'},
      );
      expect(
        preferences.snoozeUntil,
        DateTime.parse('2026-07-17T12:00:00Z'),
      );
    });

    test(
      'all generic trigger arguments and publishers are enumerated',
      () async {
        final triggerRows = await writer.execute('''
SELECT encode(t.tgargs, 'escape')
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
  AND p.proname = 'notify_entity_change'
ORDER BY 1
''');
        final arguments = triggerRows
            .map((row) => (row[0]! as String).replaceAll(r'\000', ''))
            .toSet();

        final contractEntries = _contractEntries();
        final expectedArguments = contractEntries
            .expand(
              (entry) => (entry['genericTriggerArgs']! as List).cast<String>(),
            )
            .toSet();
        expect(arguments, expectedArguments);

        final publisherRows = await writer.execute('''
SELECT p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND pg_get_functiondef(p.oid) LIKE '%pg_notify(''entity_changes''%'
ORDER BY p.proname
''');
        expect(
          publisherRows.map((row) => row[0]),
          ['emit_realtime_entity_change'],
        );

        final expectedSpecializedPublishers = contractEntries
            .expand(
              (entry) =>
                  (entry['specializedPublishers']! as List).cast<String>(),
            )
            .toSet();
        final specializedRows = await writer.execute('''
SELECT DISTINCT p.proname
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
ORDER BY p.proname
''');
        final attachedPublishers = specializedRows
            .map((row) => row[0]! as String)
            .where(expectedSpecializedPublishers.contains)
            .toSet();
        expect(attachedPublishers, expectedSpecializedPublishers);

        final relationshipRows = await writer.execute('''
SELECT c.relname, count(*), bool_and((t.tgtype & 1) = 0)
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
  AND p.proname = 'notify_relationship_change'
GROUP BY c.relname
ORDER BY c.relname
''');
        expect(
          relationshipRows.map((row) => (row[0], row[1], row[2])),
          [
            ('user_trust_edge', 3, true),
            ('vote_user', 3, true),
          ],
        );
      },
      skip: skipReason,
    );

    test(
      'actor is retained and several hundred recipients are byte chunked',
      () async {
        final recipients = [
          for (var i = 0; i < 350; i++)
            'U${i.toRadixString(16).padLeft(12, '0')}',
        ];
        final entityId =
            'Brealtime${DateTime.timestamp().microsecondsSinceEpoch}';
        const actor = 'U000000000001';
        final sqlArray = recipients.map((id) => "'$id'").join(',');

        await writer.execute('BEGIN');
        await writer.execute(
          r"SELECT set_config('tentura.mutating_user_id', $1, true)",
          parameters: [actor],
        );
        await writer.execute('''
SELECT public.emit_realtime_entity_change(
  'beacon', '$entityId', 'update', ARRAY[$sqlArray]::text[]
)
''');
        await writer.execute('COMMIT');

        List<Map<String, dynamic>> testChanges() => _ofKind(
          notifications,
          'beacon',
        ).where((message) => message['id'] == entityId).toList();

        await _waitUntil(() => testChanges().length == 4);
        final chunks = testChanges();
        expect(chunks, hasLength(4));
        expect(
          chunks.expand((message) => message['user_ids']! as List).toSet(),
          recipients.toSet(),
        );
        for (final message in chunks) {
          expect(message['actor_user_id'], actor);
          expect((message['user_ids']! as List).length, lessThanOrEqualTo(100));
          expect(utf8.encode(jsonEncode(message)).length, lessThan(7900));
        }
      },
      skip: skipReason,
    );

    test(
      'bulk relationship writes coalesce through a statement trigger',
      () async {
        final subjectPrefix =
            'realtime_${DateTime.timestamp().microsecondsSinceEpoch}_';
        final subjects = [
          for (var i = 0; i < 600; i++)
            '$subjectPrefix${i.toRadixString(16).padLeft(3, '0')}',
        ];
        await writer.execute('''
CREATE TEMP TABLE realtime_relationship_batch (
  subject text NOT NULL,
  object text NOT NULL
)
''');
        await writer.execute('''
CREATE TRIGGER realtime_relationship_batch_notify
  AFTER INSERT ON realtime_relationship_batch
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION public.notify_relationship_change()
''');
        final values = [
          for (var i = 0; i < 300; i++)
            "('${subjects[i]}','${subjects[i + 300]}')",
        ].join(',');

        await writer.execute('BEGIN');
        await writer.execute(
          'INSERT INTO realtime_relationship_batch (subject, object) VALUES $values',
        );
        await writer.execute('COMMIT');

        List<Map<String, dynamic>> testChanges() =>
            _ofKind(
                  notifications,
                  'relationship',
                )
                .where(
                  (message) =>
                      (message['id']! as String).startsWith(subjectPrefix),
                )
                .toList();

        await _waitUntil(
          () => testChanges().length == 6,
          timeout: const Duration(seconds: 10),
        );
        final changes = testChanges();
        expect(changes, hasLength(6));
        expect(
          changes.expand((message) => message['user_ids']! as List).toSet(),
          subjects.toSet(),
        );
        expect(
          changes.every((message) => !message.containsKey('subject_ids')),
          isTrue,
        );
      },
      skip: skipReason,
    );

    test(
      'row trigger emits insert, update, and delete with actor metadata',
      () async {
        const viewerId = 'Urtcontact001';
        const subjectId = 'Urtcontact002';
        addTearDown(() async {
          await writer.execute(
            Sql.named(
              'DELETE FROM public."user" WHERE id IN (@viewerId, @subjectId)',
            ),
            parameters: {'viewerId': viewerId, 'subjectId': subjectId},
          );
        });
        for (final entry in [
          (viewerId, 'realtime-contact-viewer-key'),
          (subjectId, 'realtime-contact-subject-key'),
        ]) {
          await writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
ON CONFLICT (id) DO NOTHING
'''),
            parameters: {'id': entry.$1, 'key': entry.$2},
          );
        }
        await _settle();
        notifications.clear();

        Future<Map<String, dynamic>> mutate(
          String operation,
          String statement,
        ) async {
          await writer.execute('BEGIN');
          await writer.execute(
            r"SELECT set_config('tentura.mutating_user_id', $1, true)",
            parameters: [viewerId],
          );
          await writer.execute(
            Sql.named(statement),
            parameters: {
              'viewerId': viewerId,
              'subjectId': subjectId,
            },
          );
          await writer.execute('COMMIT');
          List<Map<String, dynamic>> testChanges() => _ofKind(
            notifications,
            'contact',
          ).where((message) => message['id'] == subjectId).toList();
          await _waitUntil(() => testChanges().isNotEmpty);
          final change = testChanges().single;
          expect(change['event'], operation);
          expect(change['id'], subjectId);
          expect(change['user_ids'], [viewerId]);
          expect(change, isNot(contains('subject_ids')));
          expect(change['actor_user_id'], viewerId);
          notifications.clear();
          return change;
        }

        await mutate('insert', '''
INSERT INTO public.user_contact (viewer_id, subject_id, contact_name)
VALUES (@viewerId, @subjectId, 'First name')
''');
        await mutate('update', '''
UPDATE public.user_contact
SET contact_name = 'Updated name'
WHERE viewer_id = @viewerId AND subject_id = @subjectId
''');
        await mutate('delete', '''
DELETE FROM public.user_contact
WHERE viewer_id = @viewerId AND subject_id = @subjectId
''');
      },
      skip: skipReason,
    );

    test(
      'cascade-deleted thread message retains room recipients',
      () async {
        final suffix = DateTime.timestamp().microsecondsSinceEpoch.toString();
        final ownerId = 'Urtmsgowner$suffix';
        final participantId = 'Urtmsgparticipant$suffix';
        final authorId = 'Urtmsgauthor$suffix';
        final mentionedId = 'Urtmsgmentioned$suffix';
        final beaconId = 'Brtmsg$suffix';
        final participantRowId = 'Prtmsg$suffix';
        final itemId = 'Irtmsg$suffix';
        final messageId = 'Rrtmsg$suffix';
        final userIds = [ownerId, participantId, authorId, mentionedId];

        addTearDown(() async {
          await writer.execute(
            Sql.named('DELETE FROM public.beacon WHERE id = @beaconId'),
            parameters: {'beaconId': beaconId},
          );
          await writer.execute(
            Sql.named('DELETE FROM public."user" WHERE id = ANY(@userIds)'),
            parameters: {'userIds': userIds},
          );
        });

        for (final userId in userIds) {
          await writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@userId, @userId, @publicKey)
'''),
            parameters: {
              'userId': userId,
              'publicKey': 'realtime-room-message-$userId',
            },
          );
        }
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES (@beaconId, @ownerId, 'Realtime', 'Thread cascade test')
'''),
          parameters: {'beaconId': beaconId, 'ownerId': ownerId},
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access
) VALUES (@id, @beaconId, @userId, 2, 0, 3)
'''),
          parameters: {
            'id': participantRowId,
            'beaconId': beaconId,
            'userId': participantId,
          },
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, creator_id, target_person_id, accepted_by_id, published
) VALUES (
  @id, @beaconId, 2, @ownerId, @participantId, @authorId, true
)
'''),
          parameters: {
            'id': itemId,
            'beaconId': beaconId,
            'ownerId': ownerId,
            'participantId': participantId,
            'authorId': authorId,
          },
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, mentions, thread_item_id
) VALUES (
  @id, @beaconId, @authorId, 'Thread reply', ARRAY[@mentionedId]::text[], @itemId
)
'''),
          parameters: {
            'id': messageId,
            'beaconId': beaconId,
            'authorId': authorId,
            'mentionedId': mentionedId,
            'itemId': itemId,
          },
        );
        await _settle();
        notifications.clear();

        await writer.execute(
          Sql.named('DELETE FROM public.coordination_item WHERE id = @itemId'),
          parameters: {'itemId': itemId},
        );

        List<Map<String, dynamic>> testChanges() => _ofKind(
          notifications,
          'room_message',
        ).where((message) => message['id'] == beaconId).toList();
        await _waitUntil(() => testChanges().isNotEmpty);

        final change = testChanges().single;
        expect(change['event'], 'delete');
        expect(change['user_ids'], unorderedEquals(userIds));
      },
      skip: skipReason,
    );

    test(
      'profile updates emit only for profile-visible columns',
      () async {
        final suffix = DateTime.timestamp().microsecondsSinceEpoch.toString();
        final userId = 'Urtprofile$suffix';
        addTearDown(() async {
          await writer.execute(
            Sql.named('DELETE FROM public."user" WHERE id = @userId'),
            parameters: {'userId': userId},
          );
        });
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@userId, 'Profile before', @publicKey)
'''),
          parameters: {
            'userId': userId,
            'publicKey': 'realtime-profile-$userId',
          },
        );
        await _settle();
        notifications.clear();

        List<Map<String, dynamic>> testChanges() => _ofKind(
          notifications,
          'profile',
        ).where((message) => message['id'] == userId).toList();

        await writer.execute(
          Sql.named('''
UPDATE public."user"
SET updated_at = updated_at + interval '1 second'
WHERE id = @userId
'''),
          parameters: {'userId': userId},
        );
        await _settle();
        expect(testChanges(), isEmpty);

        await writer.execute(
          Sql.named('''
UPDATE public."user"
SET display_name = 'Profile after'
WHERE id = @userId
'''),
          parameters: {'userId': userId},
        );
        await _waitUntil(() => testChanges().isNotEmpty);

        final change = testChanges().single;
        expect(change['event'], 'update');
        expect(change['user_ids'], [userId]);
      },
      skip: skipReason,
    );

    test('room_seen no-op update emits no feedback invalidation', () async {
      const userId = 'Urtseen000001';
      const beaconId = 'Brtseen000001';
      addTearDown(() async {
        await writer.execute(
          Sql.named('DELETE FROM public."user" WHERE id = @id'),
          parameters: {'id': userId},
        );
      });
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, 'Realtime seen', @key)
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {'id': userId, 'key': 'realtime-seen-public-key'},
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES (@id, @userId, 'Realtime', 'Room seen trigger test')
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {'id': beaconId, 'userId': userId},
      );
      await _settle();
      notifications.clear();

      List<Map<String, dynamic>> testChanges() => _ofKind(
        notifications,
        'room_seen',
      ).where((message) => message['id'] == beaconId).toList();

      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_room_seen (
  user_id, beacon_id, thread_item_id, last_seen_at
) VALUES (@userId, @beaconId, NULL, '2026-07-14T10:00:00Z')
ON CONFLICT (user_id, beacon_id) WHERE thread_item_id IS NULL
DO UPDATE SET last_seen_at = EXCLUDED.last_seen_at
'''),
        parameters: {'userId': userId, 'beaconId': beaconId},
      );
      await _waitUntil(() => testChanges().length == 1);
      notifications.clear();

      await writer.execute(
        Sql.named('''
UPDATE public.beacon_room_seen
SET last_seen_at = last_seen_at
WHERE user_id = @userId AND beacon_id = @beaconId AND thread_item_id IS NULL
'''),
        parameters: {'userId': userId, 'beaconId': beaconId},
      );
      await _settle();
      expect(testChanges(), isEmpty);

      await writer.execute(
        Sql.named('''
UPDATE public.beacon_room_seen
SET last_seen_at = '2026-07-14T10:01:00Z'
WHERE user_id = @userId AND beacon_id = @beaconId AND thread_item_id IS NULL
'''),
        parameters: {'userId': userId, 'beaconId': beaconId},
      );
      await _waitUntil(() => testChanges().length == 1);
    }, skip: skipReason);

    test(
      'full trust recompute refreshes weights without relationship fan-out',
      () async {
        final suffix = DateTime.timestamp().microsecondsSinceEpoch.toString();
        final subjectId = 'Urttrustsubj$suffix';
        final objectId = 'Urttrustobj$suffix';
        final ids = [subjectId, objectId];
        addTearDown(() async {
          await writer.execute(
            Sql.named('DELETE FROM public."user" WHERE id = ANY(@ids)'),
            parameters: {'ids': ids},
          );
        });
        for (final id in ids) {
          await writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
            parameters: {'id': id, 'key': 'realtime-trust-$id'},
          );
        }
        await _settle();
        notifications.clear();

        List<Map<String, dynamic>> ownEdgeChanges() =>
            _ofKind(notifications, 'relationship')
                .where(
                  (message) => ((message['user_ids'] as List?) ?? const [])
                      .contains(subjectId),
                )
                .toList();

        // An ordinary trust-edge write still fans out: the suppression flag is
        // scoped to bulk maintenance, not applied to real relationship changes.
        await writer.execute(
          Sql.named('''
INSERT INTO public.user_trust_edge (subject, object, anchor_at, s_good)
VALUES (@subject, @object, now() - interval '1 hour', 10)
'''),
          parameters: {'subject': subjectId, 'object': objectId},
        );
        await _waitUntil(() => ownEdgeChanges().isNotEmpty);

        final before = await writer.execute(
          Sql.named('''
SELECT prev_sent_weight FROM public.user_trust_edge
WHERE subject = @s AND object = @o
'''),
          parameters: {'s': subjectId, 'o': objectId},
        );

        await _settle();
        notifications.clear();

        // Full-graph decay recompute refreshes prev_sent_weight but must emit
        // no relationship invalidation for any edge (bookkeeping-only rewrite).
        await writer.execute(
          r'SELECT public.trust_recompute_all($1)',
          parameters: [3600.0],
        );
        await _settle();
        expect(_ofKind(notifications, 'relationship'), isEmpty);

        final after = await writer.execute(
          Sql.named('''
SELECT prev_sent_weight FROM public.user_trust_edge
WHERE subject = @s AND object = @o
'''),
          parameters: {'s': subjectId, 'o': objectId},
        );
        expect((before.single.single! as num).toDouble(), 0);
        // s_good = 10, ~one half-life old ⇒ f ≈ 0.5 ⇒ weight = 5 / 10 ≈ 0.5
        // (marginally under 0.5 since elapsed time exceeds the half-life by the
        // test's own runtime). The point is prev_sent_weight was refreshed off 0.
        expect((after.single.single! as num).toDouble(), closeTo(0.5, 0.01));
      },
      skip: skipReason,
    );

    test(
      'a single evidence application emits one relationship invalidation',
      () async {
        final suffix = DateTime.timestamp().microsecondsSinceEpoch.toString();
        final subjectId = 'Urtapplysubj$suffix';
        final objectId = 'Urtapplyobj$suffix';
        final ids = [subjectId, objectId];
        addTearDown(() async {
          await writer.execute(
            Sql.named('DELETE FROM public."user" WHERE id = ANY(@ids)'),
            parameters: {'ids': ids},
          );
        });
        for (final id in ids) {
          await writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
            parameters: {'id': id, 'key': 'realtime-apply-$id'},
          );
        }
        await _settle();
        notifications.clear();

        List<Map<String, dynamic>> edgeChanges() =>
            _ofKind(notifications, 'relationship')
                .where(
                  (message) => ((message['user_ids'] as List?) ?? const [])
                      .contains(subjectId),
                )
                .toList();

        // A large epsilon means no engine push, so prev_sent_weight is left
        // alone: the only write that should reach the wire is the single bump
        // UPDATE, not the former upsert + bump (+ prev_sent_weight) trio that
        // each fired the statement trigger.
        await writer.execute(
          r'SELECT public.trust_apply_evidence($1, $2, $3, $4, $5, $6)',
          parameters: [subjectId, objectId, 'good', 4.0, 3600.0, 1000000.0],
        );
        await _waitUntil(() => edgeChanges().isNotEmpty);
        await _settle();
        expect(edgeChanges(), hasLength(1));

        final edge = await writer.execute(
          Sql.named('''
SELECT s_good, prev_sent_weight FROM public.user_trust_edge
WHERE subject = @s AND object = @o
'''),
          parameters: {'s': subjectId, 'o': objectId},
        );
        expect((edge.single[0]! as num).toDouble(), greaterThan(0));
        expect((edge.single[1]! as num).toDouble(), 0);
      },
      skip: skipReason,
    );
  }, skip: skipReason);
}

List<Map<String, dynamic>> _ofKind(
  List<Map<String, dynamic>> notifications,
  String kind,
) => notifications.where((message) => message['entity'] == kind).toList();

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

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    ).timeout(const Duration(seconds: 2));
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

Future<void> _rollBackM0117ForTest(Connection connection) async {
  for (final statement in const [
    '''
DROP TRIGGER beacon_room_seen_attention_bridge
  ON public.beacon_room_seen
''',
    'DROP FUNCTION public.bridge_attention_room_seen_trigger()',
    'DROP FUNCTION public.bridge_attention_room_seen(text, text, text, timestamptz)',
    'DROP FUNCTION public.visible_attention_receipts(text)',
    "DELETE FROM public.schema_version WHERE version = '0117'",
  ]) {
    await connection.execute(statement);
  }
}

Future<void> _rollBackM0118ForTest(Connection connection) async {
  for (final statement in const [
    'DROP INDEX public.notification_outbox__live_obligation_thread',
    'DROP INDEX public.notification_outbox__live_obligation',
    '''
ALTER TABLE public.notification_outbox
  DROP CONSTRAINT notification_outbox__thread_key_chk,
  DROP CONSTRAINT notification_outbox__settlement_obligation_chk,
  DROP CONSTRAINT notification_outbox__settlement_facts_chk,
  DROP CONSTRAINT notification_outbox__settlement_kind_chk,
  DROP COLUMN settled_by_occurrence_id,
  DROP COLUMN settled_by_user_id,
  DROP COLUMN settled_at,
  DROP COLUMN settlement_kind,
  DROP COLUMN attention_thread_key,
  DROP COLUMN requires_action
''',
    "DELETE FROM public.schema_version WHERE version = '0118'",
  ]) {
    await connection.execute(statement);
  }
}

Future<void> _rollBackM0119ForTest(Connection connection) async {
  for (final statement in const [
    'DROP INDEX public.notification_outbox__payload_search',
    "DELETE FROM public.schema_version WHERE version = '0119'",
  ]) {
    await connection.execute(statement);
  }
}

Future<void> _rollBackM0116ForTest(Connection connection) async {
  for (final statement in const [
    '''
DROP TRIGGER notification_outbox_insert_notify
  ON public.notification_outbox
''',
    '''
DROP TRIGGER notification_outbox_update_notify
  ON public.notification_outbox
''',
    '''
DROP TRIGGER notification_outbox_delete_notify
  ON public.notification_outbox
''',
    'DROP FUNCTION public.notify_notification_outbox_insert()',
    'DROP FUNCTION public.notify_notification_outbox_update()',
    'DROP FUNCTION public.notify_notification_outbox_delete()',
    '''
CREATE TRIGGER notification_outbox_entity_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.notification_outbox
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('notification')
''',
    "DELETE FROM public.schema_version WHERE version = '0116'",
  ]) {
    await connection.execute(statement);
  }
}

Future<void> _rollBackM0115ForTest(Connection connection) async {
  for (final statement in const [
    'DROP INDEX public.notification_outbox__unread',
    'DROP INDEX public.notification_outbox__feed_v2',
    r'''
ALTER TABLE public.notification_outbox
  DROP COLUMN seen_at,
  DROP COLUMN source_event_key,
  DROP COLUMN destination_kind,
  DROP COLUMN target_entity_id,
  DROP COLUMN presentation_key,
  DROP COLUMN presentation_payload,
  DROP COLUMN in_app_preference_class,
  DROP COLUMN suppression_class,
  DROP COLUMN access_policy
''',
    r'''
ALTER TABLE public.notification_preference
  DROP COLUMN muted_in_app_event_classes
''',
    "DELETE FROM public.schema_version WHERE version = '0115'",
  ]) {
    await connection.execute(statement);
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_REALTIME_NOTIFICATION_TEST_DB'] ??
        'tentura_test_rt_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_REALTIME_NOTIFICATION_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      final remaining = await connection.execute(
        r'SELECT count(*)::int FROM pg_database WHERE datname = $1',
        parameters: [databaseName],
      );
      if (remaining.single.single != 0) {
        throw StateError('Disposable database was not dropped: $databaseName');
      }
    } finally {
      await connection.close();
    }
  }
}

List<Map<String, dynamic>> _contractEntries() {
  final contract = jsonDecode(_contractFile().readAsStringSync()) as Map;
  return (contract['kinds']! as List)
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList(growable: false);
}

File _contractFile() {
  for (final path in const [
    '../../docs/contracts/realtime-entity-contract.json',
    'docs/contracts/realtime-entity-contract.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) return file.absolute;
  }
  throw StateError('Realtime entity contract manifest not found');
}
