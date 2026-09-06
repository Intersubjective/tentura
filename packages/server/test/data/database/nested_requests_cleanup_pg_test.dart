@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/pg_test_public_keys.dart';

/// Deployment gate (documented procedure — never executed against production
/// data in this test suite):
///
/// 1. Enter maintenance; stop app servers and workers.
/// 2. Capture backup: `pg_dump -Fc -f tentura-nested-cleanup-<UTC-ISO8601>-<source-db>.dump <source-db>`
/// 3. Prove restore to an isolated database: `pg_restore -d tentura-restore-rehearsal-<id> ...`
/// 4. Apply migrations including `m0158`; verify postconditions from this file.
/// 5. Rollback after cleanup is **restore backup + matching app versions only** — no down-migration.
///
/// Backup identifier convention: `tentura-nested-cleanup-<UTC-ISO8601>-<source-db>`
/// (example: `tentura-nested-cleanup-20260906T170900Z-tentura_prod`).
///
/// Fixture construction: migrate disposable DB through `0155` (pre-`m0156`
/// General-only guards), insert legacy mixed data via raw SQL, then apply
/// `migrateDbSchema` to run `m0156`–`m0158` (cleanup executes inside `m0158`).
/// Idempotent "rerun" means invoking `nested_requests_apply_legacy_cleanup()`
/// again after `m0158` — not re-applying the migration.
final class _CleanupFixtureIds {
  const _CleanupFixtureIds();
  static const beaconId = 'Bm158beacon01';
  static const privateBeaconDraftId = 'Bm158draft001';
  static const ownerId = 'Um158owner001';
  static const memberId = 'Um158member01';

  static const supportedPlanId = 'Im158planpub1';
  static const supportedPlanDraftId = 'Im158plandraf';
  static const retiredAskId = 'Im158askpub01';
  static const retiredBlockerId = 'Im158blocker1';
  static const retiredPromiseId = 'Im158promise1';
  static const retiredAskDraftId = 'Im158askdraft';

  static const generalMessageId = 'Rm158genmsg01';
  static const generalMessage2Id = 'Rm158genmsg02';
  static const doomedThreadMessageId = 'Rm158doomth01';
  static const doomedPollMessageId = 'Rm158doompol1';
  static const systemAnchorMessageId = 'Rm158sysanc01';
  static const survivorLinkedMessageId = 'Rm158survlnk1';

  static const sharedImageId = '11111111-a158-4111-8111-a15811111111';
  static const doomedOnlyImageId = '22222222-b158-4222-8222-b15822222222';
  static const doomedPollId = 'Pm158doompoll';
  static const supportedFactId = 'Fm158factgen1';
  static const doomedSourceFactId = 'Fm158factdoom';

  static const retiredAttentionReceiptId = 'Nm158retired1';
  static const supportedAttentionReceiptId = 'Nm158support1';
  static const retiredOccurrenceId = 'Om158retired1';
  static const supportedOccurrenceId = 'Om158support1';
  static const retiredChannelDeliveryId = 'Dm158retired1';
  static const retiredActivityEventId = 'Am158retired1';
  static const unrelatedActivityEventId = 'Am158unrelat1';
}

final class _TableCounts {
  const _TableCounts(this.byTable);

  final Map<String, int> byTable;

  Map<String, int> diff(_TableCounts other) {
    final keys = {...byTable.keys, ...other.byTable.keys};
    return {
      for (final key in keys)
        key: (other.byTable[key] ?? 0) - (byTable[key] ?? 0),
    };
  }

  @override
  String toString() => const JsonEncoder.withIndent('  ').convert(byTable);
}

Future<_TableCounts> _countAffectedTables(Connection writer) async {
  const tables = [
    'coordination_item',
    'beacon_room_message',
    'beacon_room_message_attachment',
    'beacon_room_message_reaction',
    'polling',
    'polling_variant',
    'polling_act',
    'beacon_room_seen',
    'beacon_fact_card',
    'beacon_activity_event',
    'notification_outbox',
    'attention_occurrence',
    'attention_occurrence_recipient',
    'attention_channel_delivery',
    'image',
    'image_object_gc',
  ];
  final byTable = <String, int>{};
  for (final table in tables) {
    final row = await writer.execute(
      'SELECT count(*)::int FROM public.$table',
    );
    byTable[table] = row.single.first as int;
  }
  return _TableCounts(byTable);
}

Future<void> _seedPreRetirementFixture(Connection writer) async {
  for (final entry in [(_CleanupFixtureIds.ownerId, 1), (_CleanupFixtureIds.memberId, 2)]) {
    await writer.execute(
      Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @publicKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
      parameters: {
        'id': entry.$1,
        'publicKey': pgTestPublicKey('m158', entry.$2),
      },
    );
  }

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, parent_beacon_id, published_at, created_at, updated_at
) VALUES
  (@publishedId, @ownerId, 'Cleanup host', '', 0, NULL, '2026-01-01T00:00:00Z',
   '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  (@draftId, @ownerId, 'Private beacon draft', '', 3, @parentId, NULL,
   '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {
      'publishedId': _CleanupFixtureIds.beaconId,
      'draftId': _CleanupFixtureIds.privateBeaconDraftId,
      'parentId': _CleanupFixtureIds.beaconId,
      'ownerId': _CleanupFixtureIds.ownerId,
    },
  );

  Future<void> insertItem({
    required String id,
    required int kind,
    required bool published,
    required String title,
  }) async {
    await writer.execute(
      Sql.named(r'''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id, target_person_id,
  published, created_at, updated_at, published_at, source, ordering
) VALUES (
  @id, @beaconId, @kind, 0, @title, '', @creatorId, @targetId,
  @published,
  '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z',
  CASE WHEN @published THEN '2026-01-02T00:00:00Z'::timestamptz ELSE NULL END,
  0, 0
)
ON CONFLICT (id) DO NOTHING
'''),
      parameters: {
        'id': id,
        'beaconId': _CleanupFixtureIds.beaconId,
        'kind': kind,
        'title': title,
        'creatorId': _CleanupFixtureIds.ownerId,
        'targetId': _CleanupFixtureIds.memberId,
        'published': published,
      },
    );
  }

  await insertItem(
    id: _CleanupFixtureIds.supportedPlanId,
    kind: coordinationItemKindPlan,
    published: true,
    title: 'Supported plan',
  );
  await insertItem(
    id: _CleanupFixtureIds.supportedPlanDraftId,
    kind: coordinationItemKindPlan,
    published: false,
    title: 'Private plan draft',
  );
  await insertItem(
    id: _CleanupFixtureIds.retiredAskId,
    kind: coordinationItemKindAsk,
    published: true,
    title: 'Retired ask',
  );
  await insertItem(
    id: _CleanupFixtureIds.retiredBlockerId,
    kind: coordinationItemKindBlocker,
    published: true,
    title: 'Retired blocker',
  );
  await insertItem(
    id: _CleanupFixtureIds.retiredPromiseId,
    kind: coordinationItemKindPromise,
    published: true,
    title: 'Retired promise',
  );
  await insertItem(
    id: _CleanupFixtureIds.retiredAskDraftId,
    kind: coordinationItemKindAsk,
    published: false,
    title: 'Private ask draft',
  );

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.image (id, author_id, height, width, hash)
VALUES
  (@shared::uuid, @authorId, 10, 10, 'shared-hash'),
  (@doomedOnly::uuid, @authorId, 10, 10, 'doomed-only-hash')
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {
      'shared': _CleanupFixtureIds.sharedImageId,
      'doomedOnly': _CleanupFixtureIds.doomedOnlyImageId,
      'authorId': _CleanupFixtureIds.ownerId,
    },
  );

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.polling (
  id, author_id, question, poll_type, is_anonymous, allow_revote, created_at, updated_at
) VALUES (
  @pollId, @authorId, 'Doomed thread poll?', 'single', true, true,
  '2026-01-03T00:00:00Z', '2026-01-03T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {
      'pollId': _CleanupFixtureIds.doomedPollId,
      'authorId': _CleanupFixtureIds.ownerId,
    },
  );
  await writer.execute(
    Sql.named(r'''
INSERT INTO public.polling_variant (id, polling_id, description)
VALUES ('Vm158doomopt1', @pollId, 'Yes')
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {'pollId': _CleanupFixtureIds.doomedPollId},
  );
  await writer.execute(
    Sql.named(r'''
INSERT INTO public.polling_act (author_id, polling_id, polling_variant_id, created_at)
VALUES (@userId, @pollId, 'Vm158doomopt1', '2026-01-03T01:00:00Z')
ON CONFLICT DO NOTHING
'''),
    parameters: {
      'pollId': _CleanupFixtureIds.doomedPollId,
      'userId': _CleanupFixtureIds.memberId,
    },
  );

  Future<void> insertMessage({
    required String id,
    required String body,
    String? threadItemId,
    String? replyToMessageId,
    String? linkedItemId,
    int? linkedEventKind,
    String? linkedPollingId,
  }) async {
    await writer.execute(
      Sql.named(r'''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, thread_item_id, reply_to_message_id,
  linked_item_id, linked_event_kind, linked_polling_id, created_at
) VALUES (
  @id, @beaconId, @authorId, @body, @threadItemId, @replyToMessageId,
  @linkedItemId, @linkedEventKind, @linkedPollingId, @createdAt::timestamptz
)
ON CONFLICT (id) DO NOTHING
'''),
      parameters: {
        'id': id,
        'beaconId': _CleanupFixtureIds.beaconId,
        'authorId': _CleanupFixtureIds.ownerId,
        'body': body,
        'threadItemId': threadItemId,
        'replyToMessageId': replyToMessageId,
        'linkedItemId': linkedItemId,
        'linkedEventKind': linkedEventKind,
        'linkedPollingId': linkedPollingId,
        'createdAt': '2026-01-03T00:00:00Z',
      },
    );
  }

  await insertMessage(
    id: _CleanupFixtureIds.generalMessageId,
    body: 'Supported General message',
  );
  await insertMessage(
    id: _CleanupFixtureIds.doomedThreadMessageId,
    body: 'Retired ask thread message',
    threadItemId: _CleanupFixtureIds.retiredAskId,
  );
  await insertMessage(
    id: _CleanupFixtureIds.doomedPollMessageId,
    body: 'Retired promise poll host',
    threadItemId: _CleanupFixtureIds.retiredPromiseId,
    linkedPollingId: _CleanupFixtureIds.doomedPollId,
  );
  await insertMessage(
    id: _CleanupFixtureIds.systemAnchorMessageId,
    body: '',
    linkedItemId: _CleanupFixtureIds.retiredAskId,
    linkedEventKind: coordinationEventKindCreated,
  );
  await insertMessage(
    id: _CleanupFixtureIds.survivorLinkedMessageId,
    body: 'General survivor with retired links',
    linkedItemId: _CleanupFixtureIds.retiredBlockerId,
    linkedEventKind: coordinationEventKindCreated,
  );
  await insertMessage(
    id: _CleanupFixtureIds.generalMessage2Id,
    body: 'General reply to doomed message',
    replyToMessageId: _CleanupFixtureIds.doomedThreadMessageId,
  );

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.beacon_room_message_attachment (
  id, message_id, kind, image_id, mime, size_bytes
) VALUES
  ('Am158shared01', @generalMessageId, 1, @shared::uuid, 'image/png', 100),
  ('Am158doomed01', @doomedMessageId, 1, @shared::uuid, 'image/png', 100),
  ('Am158doomonly', @doomedMessageId, 1, @doomedOnly::uuid, 'image/png', 50)
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {
      'generalMessageId': _CleanupFixtureIds.generalMessageId,
      'doomedMessageId': _CleanupFixtureIds.doomedThreadMessageId,
      'shared': _CleanupFixtureIds.sharedImageId,
      'doomedOnly': _CleanupFixtureIds.doomedOnlyImageId,
    },
  );

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.beacon_room_message_reaction (
  id, message_id, user_id, emoji, created_at
) VALUES ('Em158doomed1', @messageId, @userId, '👍', '2026-01-03T01:00:00Z')
ON CONFLICT DO NOTHING
'''),
    parameters: {
      'messageId': _CleanupFixtureIds.doomedThreadMessageId,
      'userId': _CleanupFixtureIds.memberId,
    },
  );

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.beacon_fact_card (
  id, beacon_id, pinned_by, fact_text, visibility, source_message_id,
  created_at, updated_at
) VALUES
  (@supportedFact, @beaconId, @ownerId, 'Fact from General', 1, @generalMessageId,
   '2026-01-03T00:00:00Z', '2026-01-03T00:00:00Z'),
  (@doomedSourceFact, @beaconId, @ownerId, 'Fact from doomed thread', 1, @doomedMessageId,
   '2026-01-03T00:00:00Z', '2026-01-03T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {
      'supportedFact': _CleanupFixtureIds.supportedFactId,
      'doomedSourceFact': _CleanupFixtureIds.doomedSourceFactId,
      'beaconId': _CleanupFixtureIds.beaconId,
      'ownerId': _CleanupFixtureIds.ownerId,
      'generalMessageId': _CleanupFixtureIds.generalMessageId,
      'doomedMessageId': _CleanupFixtureIds.doomedThreadMessageId,
    },
  );

  // Note: beacon_promotions.source_message_id cannot legally reference a
  // non-General (doomed) message at all — m0154's
  // beacon_promotions_consistency_guard trigger rejects ANY insert/update
  // whose source message has a non-null thread scope, at draft time as
  // well as publish time (plan §3.4.9: "Message must have null thread
  // scope"). So m0158's own provenance-nulling UPDATE for this table can
  // never actually match a row in practice — there is nothing to fixture
  // here, since the precondition is unconstructible under the live schema.

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.beacon_room_state (
  beacon_id, current_line, open_blocker_id, last_room_meaningful_change,
  updated_at, updated_by
) VALUES (
  @beaconId, '', @blockerId, @doomedMessageId,
  '2026-01-03T00:00:00Z', @ownerId
)
ON CONFLICT (beacon_id) DO UPDATE SET
  open_blocker_id = EXCLUDED.open_blocker_id,
  last_room_meaningful_change = EXCLUDED.last_room_meaningful_change
'''),
    parameters: {
      'beaconId': _CleanupFixtureIds.beaconId,
      'blockerId': _CleanupFixtureIds.retiredBlockerId,
      'doomedMessageId': _CleanupFixtureIds.doomedThreadMessageId,
      'ownerId': _CleanupFixtureIds.ownerId,
    },
  );

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.beacon_room_seen (user_id, beacon_id, thread_item_id, last_seen_at)
VALUES
  (@ownerId, @beaconId, NULL, '2026-01-04T10:00:00Z'),
  (@ownerId, @beaconId, @retiredAskId, '2026-01-04T11:00:00Z')
ON CONFLICT DO NOTHING
'''),
    parameters: {
      'ownerId': _CleanupFixtureIds.ownerId,
      'beaconId': _CleanupFixtureIds.beaconId,
      'retiredAskId': _CleanupFixtureIds.retiredAskId,
    },
  );

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.attention_occurrence (
  id, source_event_key, event_type, actor_user_id, immutable_payload, occurred_at
) VALUES
  (@retiredOcc, 'm158-retired-occ', 'coordinationChanged', @ownerId,
   '{"coordinationItemId":"${_CleanupFixtureIds.retiredAskId}"}'::jsonb, '2026-01-03T00:00:00Z'),
  (@supportedOcc, 'm158-supported-occ', 'coordinationChanged', @ownerId,
   '{"coordinationItemId":"${_CleanupFixtureIds.supportedPlanId}"}'::jsonb, '2026-01-03T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {
      'retiredOcc': _CleanupFixtureIds.retiredOccurrenceId,
      'supportedOcc': _CleanupFixtureIds.supportedOccurrenceId,
      'ownerId': _CleanupFixtureIds.ownerId,
    },
  );

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.attention_occurrence_recipient (
  occurrence_id, account_id, reasons, role_facts, collapse_key, channel_eligible
) VALUES
  (@retiredOcc, @memberId, '[]'::jsonb, '{}'::jsonb, 'm158-retired', true),
  (@supportedOcc, @memberId, '[]'::jsonb, '{}'::jsonb, 'm158-supported', true)
ON CONFLICT DO NOTHING
'''),
    parameters: {
      'retiredOcc': _CleanupFixtureIds.retiredOccurrenceId,
      'supportedOcc': _CleanupFixtureIds.supportedOccurrenceId,
      'memberId': _CleanupFixtureIds.memberId,
    },
  );

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, coordination_item_id, source_event_key,
  destination_kind, target_entity_id, occurrence_id,
  presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES
  (
    @retiredReceipt, @memberId, 'coordination', 'coordinationChanged', 'normal',
    'Retired item notice', 'body', '/attention', 'dedup-retired',
    '2026-01-03T00:00:00Z', @beaconId, @retiredAskId, 'm158-retired',
    'coordination_item', @retiredAskId, @retiredOcc,
    'coordination_item_changed',
    jsonb_build_object('coordinationItemId', @retiredAskId::text),
    'standard', 'beacon_content'
  ),
  (
    @supportedReceipt, @memberId, 'coordination', 'coordinationChanged', 'normal',
    'Supported plan notice', 'body', '/attention', 'dedup-supported',
    '2026-01-03T00:00:00Z', @beaconId, @supportedPlanId, 'm158-supported',
    'coordination_item', @supportedPlanId, @supportedOcc,
    'coordination_item_changed',
    jsonb_build_object('coordinationItemId', @supportedPlanId::text),
    'standard', 'beacon_content'
  )
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {
      'retiredReceipt': _CleanupFixtureIds.retiredAttentionReceiptId,
      'supportedReceipt': _CleanupFixtureIds.supportedAttentionReceiptId,
      'memberId': _CleanupFixtureIds.memberId,
      'beaconId': _CleanupFixtureIds.beaconId,
      'retiredAskId': _CleanupFixtureIds.retiredAskId,
      'supportedPlanId': _CleanupFixtureIds.supportedPlanId,
      'retiredOcc': _CleanupFixtureIds.retiredOccurrenceId,
      'supportedOcc': _CleanupFixtureIds.supportedOccurrenceId,
    },
  );

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.attention_channel_delivery (
  id, occurrence_id, receipt_id, account_id, status, payload, created_at
) VALUES (
  @deliveryId, @occurrenceId, @receiptId, @memberId, 'pending',
  '{"fixture":true}'::jsonb, '2026-01-03T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {
      'deliveryId': _CleanupFixtureIds.retiredChannelDeliveryId,
      'occurrenceId': _CleanupFixtureIds.retiredOccurrenceId,
      'receiptId': _CleanupFixtureIds.retiredAttentionReceiptId,
      'memberId': _CleanupFixtureIds.memberId,
    },
  );

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.beacon_activity_event (
  id, beacon_id, visibility, type, actor_id, coordination_item_id, source_message_id,
  created_at
) VALUES
  (@retiredEvent, @beaconId, 0, 1, @ownerId, @retiredAskId, @doomedMessageId,
   '2026-01-03T00:00:00Z'),
  (@unrelatedEvent, @beaconId, 0, 1, @ownerId, @supportedPlanId, @generalMessageId,
   '2026-01-03T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {
      'retiredEvent': _CleanupFixtureIds.retiredActivityEventId,
      'unrelatedEvent': _CleanupFixtureIds.unrelatedActivityEventId,
      'beaconId': _CleanupFixtureIds.beaconId,
      'ownerId': _CleanupFixtureIds.ownerId,
      'retiredAskId': _CleanupFixtureIds.retiredAskId,
      'supportedPlanId': _CleanupFixtureIds.supportedPlanId,
      'doomedMessageId': _CleanupFixtureIds.doomedThreadMessageId,
      'generalMessageId': _CleanupFixtureIds.generalMessageId,
    },
  );
}

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for nested requests cleanup PG test';

  group('m0158 nested requests legacy cleanup', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late _TableCounts beforeCounts;
    late _TableCounts afterCounts;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment(
        databaseNameOverride:
            'tentura_test_m158_${DateTime.timestamp().microsecondsSinceEpoch}',
      );
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');

      final currentDb = await writer.execute('SELECT current_database()');
      expect(currentDb.single.first, target.databaseName);
      expect(target.databaseName, isNot('postgres'));
      expect(target.databaseName, startsWith('tentura_test_'));

      await migrateDbSchemaThrough(writer, '0155');
      await _seedPreRetirementFixture(writer);
      beforeCounts = await _countAffectedTables(writer);

      await migrateDbSchema(writer);
      afterCounts = await _countAffectedTables(writer);
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await writer.close();
      await target.drop();
    });

    test('disposable database name is isolated', () {
      expect(target.databaseName, startsWith('tentura_test_m158_'));
    }, skip: skipReason);

    test(
      'mixed fixture cleanup removes retired scope and preserves supported rows',
      () async {
        final diff = beforeCounts.diff(afterCounts);
        // Recorded for journal / deployment evidence (backup id documented above).
        expect(beforeCounts.byTable['coordination_item'], 6);
        expect(afterCounts.byTable['coordination_item'], 2);
        expect(diff['coordination_item'], -4);
        expect(diff['beacon_room_message'], lessThan(0));
        expect(diff['beacon_room_seen'], -1);
        expect(diff['polling'], -1);
        expect(diff['image'], -1);

        final retiredKinds = await writer.execute(
          'SELECT count(*)::int FROM public.coordination_item WHERE kind IN (2, 3, 5)',
        );
        expect(retiredKinds.single.first, 0);

        final nonGeneralMessages = await writer.execute(
          'SELECT count(*)::int FROM public.beacon_room_message '
          'WHERE thread_item_id IS NOT NULL',
        );
        expect(nonGeneralMessages.single.first, 0);

        final retainedPlanIds = await writer.execute(
          Sql.named(
            'SELECT id FROM public.coordination_item WHERE beacon_id = @beaconId ORDER BY id',
          ),
          parameters: {'beaconId': _CleanupFixtureIds.beaconId},
        );
        expect(
          retainedPlanIds.map((row) => row.first as String).toList(),
          [_CleanupFixtureIds.supportedPlanDraftId, _CleanupFixtureIds.supportedPlanId],
        );

        final retainedMessages = await writer.execute(
          Sql.named(
            'SELECT id FROM public.beacon_room_message WHERE beacon_id = @beaconId ORDER BY id',
          ),
          parameters: {'beaconId': _CleanupFixtureIds.beaconId},
        );
        expect(
          retainedMessages.map((row) => row.first as String).toList(),
          containsAll([
            _CleanupFixtureIds.generalMessageId,
            _CleanupFixtureIds.generalMessage2Id,
            _CleanupFixtureIds.survivorLinkedMessageId,
          ]),
        );
        expect(
          retainedMessages.map((row) => row.first as String),
          isNot(contains(_CleanupFixtureIds.systemAnchorMessageId)),
        );
        expect(
          retainedMessages.map((row) => row.first as String),
          isNot(contains(_CleanupFixtureIds.doomedThreadMessageId)),
        );

        final generalWatermark = await writer.execute(
          Sql.named('''
SELECT last_seen_at
FROM public.beacon_room_seen
WHERE user_id = @userId AND beacon_id = @beaconId AND thread_item_id IS NULL
'''),
          parameters: {'userId': _CleanupFixtureIds.ownerId, 'beaconId': _CleanupFixtureIds.beaconId},
        );
        expect(generalWatermark, hasLength(1));
        expect(
          generalWatermark.single.first,
          DateTime.utc(2026, 1, 4, 10),
        );

        final threadSeen = await writer.execute(
          'SELECT count(*)::int FROM public.beacon_room_seen WHERE thread_item_id IS NOT NULL',
        );
        expect(threadSeen.single.first, 0);

        final factRows = await writer.execute(
          Sql.named('''
SELECT id, source_message_id
FROM public.beacon_fact_card
WHERE beacon_id = @beaconId
ORDER BY id
'''),
          parameters: {'beaconId': _CleanupFixtureIds.beaconId},
        );
        expect(factRows, hasLength(2));
        expect(factRows[0][0], _CleanupFixtureIds.doomedSourceFactId);
        expect(factRows[0][1], isNull);
        expect(factRows[1][0], _CleanupFixtureIds.supportedFactId);
        expect(factRows[1][1], _CleanupFixtureIds.generalMessageId);

        final survivorLinks = await writer.execute(
          Sql.named('''
SELECT linked_item_id, linked_event_kind, system_payload
FROM public.beacon_room_message
WHERE id = @messageId
'''),
          parameters: {'messageId': _CleanupFixtureIds.survivorLinkedMessageId},
        );
        expect(survivorLinks.single[0], isNull);
        expect(survivorLinks.single[1], isNull);
        expect(survivorLinks.single[2], isNull);

        final generalReply = await writer.execute(
          Sql.named(
            'SELECT reply_to_message_id FROM public.beacon_room_message WHERE id = @id',
          ),
          parameters: {'id': _CleanupFixtureIds.generalMessage2Id},
        );
        expect(generalReply.single.first, isNull);

        final roomState = await writer.execute(
          Sql.named('''
SELECT open_blocker_id, last_room_meaningful_change
FROM public.beacon_room_state
WHERE beacon_id = @beaconId
'''),
          parameters: {'beaconId': _CleanupFixtureIds.beaconId},
        );
        expect(roomState.single[0], isNull);
        expect(roomState.single[1], isNull);

        final sharedImage = await writer.execute(
          Sql.named('SELECT count(*)::int FROM public.image WHERE id = @id::uuid'),
          parameters: {'id': _CleanupFixtureIds.sharedImageId},
        );
        expect(sharedImage.single.first, 1);

        final doomedOnlyImage = await writer.execute(
          Sql.named('SELECT count(*)::int FROM public.image WHERE id = @id::uuid'),
          parameters: {'id': _CleanupFixtureIds.doomedOnlyImageId},
        );
        expect(doomedOnlyImage.single.first, 0);

        final gcQueued = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.image_object_gc WHERE image_id = @id::uuid',
          ),
          parameters: {'id': _CleanupFixtureIds.doomedOnlyImageId},
        );
        expect(gcQueued.single.first, 1);

        final retiredAttention = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.notification_outbox WHERE id = @id',
          ),
          parameters: {'id': _CleanupFixtureIds.retiredAttentionReceiptId},
        );
        expect(retiredAttention.single.first, 0);

        final supportedAttention = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.notification_outbox WHERE id = @id',
          ),
          parameters: {'id': _CleanupFixtureIds.supportedAttentionReceiptId},
        );
        expect(supportedAttention.single.first, 1);

        final retiredActivity = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.beacon_activity_event WHERE id = @id',
          ),
          parameters: {'id': _CleanupFixtureIds.retiredActivityEventId},
        );
        expect(retiredActivity.single.first, 0);

        final supportedActivity = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.beacon_activity_event WHERE id = @id',
          ),
          parameters: {'id': _CleanupFixtureIds.unrelatedActivityEventId},
        );
        expect(supportedActivity.single.first, 1);

        final privateDraftBeacon = await writer.execute(
          Sql.named('SELECT status FROM public.beacon WHERE id = @id'),
          parameters: {'id': _CleanupFixtureIds.privateBeaconDraftId},
        );
        expect(privateDraftBeacon.single.first, 3);

        final brokenFk = await writer.execute(r'''
SELECT count(*)::int
FROM (
  SELECT 1
  FROM public.beacon_room_message m
  WHERE m.reply_to_message_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.beacon_room_message t WHERE t.id = m.reply_to_message_id
    )
  UNION ALL
  SELECT 1
  FROM public.beacon_fact_card f
  WHERE f.source_message_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.beacon_room_message t WHERE t.id = f.source_message_id
    )
  UNION ALL
  SELECT 1
  FROM public.notification_outbox n
  WHERE n.coordination_item_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.coordination_item ci WHERE ci.id = n.coordination_item_id
    )
) dangling
''');
        expect(brokenFk.single.first, 0);
      },
      skip: skipReason,
    );

    test(
      'nested_requests_apply_legacy_cleanup is safe to invoke again',
      () async {
        final countsBeforeRerun = await _countAffectedTables(writer);
        await writer.execute(
          'SELECT public.nested_requests_apply_legacy_cleanup()',
        );
        final countsAfterRerun = await _countAffectedTables(writer);
        expect(countsBeforeRerun.byTable, countsAfterRerun.byTable);
      },
      skip: skipReason,
    );
  });
}
