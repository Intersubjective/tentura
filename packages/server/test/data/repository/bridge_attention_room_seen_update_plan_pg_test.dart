@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BRIDGE_ROOM_SEEN_PLAN_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_brdgseenplan',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for bridge_attention_room_seen plan PG test';

  group('bridge_attention_room_seen UPDATE plan — disposable Postgres', () {
    late Connection writer;

    const targetBeaconId = 'Bbrdgpln0001';
    const authorAccountId = 'Ubrdgplnauth';
    const helperAccountId = 'Ubrdgplnhelp';
    const otherBeaconPrefix = 'Bbrdgplnnoise';

    final watermarkAt = DateTime.utc(2026, 8, 1, 18);

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        Sql.named(
          "DELETE FROM public.notification_outbox WHERE account_id IN "
          "(@authorId, @helperId)",
        ),
        parameters: {
          'authorId': authorAccountId,
          'helperId': helperAccountId,
        },
      );
      await writer.execute(
        Sql.named(
          "DELETE FROM public.beacon_room_message WHERE beacon_id = @beaconId",
        ),
        parameters: {'beaconId': targetBeaconId},
      );
      await writer.execute(
        Sql.named(
          "DELETE FROM public.beacon WHERE id = @beaconId OR id LIKE @noisePrefix",
        ),
        parameters: {
          'beaconId': targetBeaconId,
          'noisePrefix': '${otherBeaconPrefix}%',
        },
      );
      await writer.execute(
        Sql.named(
          "DELETE FROM public.\"user\" WHERE id IN (@authorId, @helperId)",
        ),
        parameters: {
          'authorId': authorAccountId,
          'helperId': helperAccountId,
        },
      );
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await writer.close();
      await target.drop();
    });

    Future<void> seedUser(String id, int slot) async {
      await writer.execute(
        Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @publicKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name
'''),
        parameters: {
          'id': id,
          'publicKey': pgTestPublicKey('brdgpln', slot),
        },
      );
    }

    Future<void> seedBeacon({
      required String id,
      required String ownerId,
    }) async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @ownerId, 'Fixture', 'Fixture', 0)
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {'id': id, 'ownerId': ownerId},
      );
    }

    Future<void> insertRoomMessage({
      required String messageId,
      required String authorId,
      required DateTime createdAt,
    }) async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, mentions, thread_item_id, created_at
) VALUES (
  @messageId, @beaconId, @authorId, 'body', ARRAY[]::text[], NULL, @createdAt
)
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {
          'messageId': messageId,
          'beaconId': targetBeaconId,
          'authorId': authorId,
          'createdAt': createdAt,
        },
      );
    }

    Future<void> insertRoomMessageReceipt({
      required String accountId,
      required String receiptId,
      required String messageId,
      required String createdAt,
      required bool requiresAction,
    }) async {
      final threadKey = requiresAction
          ? 'v1|needsMe|$receiptId|$accountId'
          : null;
      await writer.execute(
        Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, target_entity_id,
  presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Room', 'Body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon_room_message', @messageId,
  'room_message_posted', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  @requiresAction, @threadKey
)
'''),
        parameters: {
          'id': receiptId,
          'accountId': accountId,
          'dedupKey': 'dedup-$receiptId',
          'createdAt': createdAt,
          'beaconId': targetBeaconId,
          'sourceEventKey': 'source-$receiptId',
          'messageId': messageId,
          'requiresAction': requiresAction,
          'threadKey': threadKey,
        },
      );
    }

    Future<void> seedNoiseBeacons({
      required String ownerId,
      required int count,
    }) async {
      await writer.execute(
        Sql.named("""
INSERT INTO public.beacon (id, user_id, title, description, status)
SELECT @prefix || lpad(i::text, 3, '0'), @ownerId, 'Fixture', 'Fixture', 0
FROM generate_series(0, CAST(@count AS int) - 1) AS i
ON CONFLICT (id) DO NOTHING
"""),
        parameters: {
          'prefix': otherBeaconPrefix,
          'ownerId': ownerId,
          'count': count,
        },
      );
    }

    /// Set-based insert (one round trip) so the fixture stays fast under
    /// parallel load; [obligation] rows carry requires_action + thread key.
    Future<void> insertNoise({
      required String accountId,
      required int count,
      required bool obligation,
    }) async {
      await seedNoiseBeacons(ownerId: accountId, count: count);
      final idPrefix = 'Nbrdg${obligation ? 'ob' : 'op'}${accountId.hashCode.abs()}';
      await writer.execute(
        Sql.named("""
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key
)
SELECT
  r.id, @accountId,
  CASE WHEN CAST(@obligation AS boolean) THEN 'asksOfMe' ELSE 'coordination' END,
  CASE WHEN CAST(@obligation AS boolean) THEN 'needsMe' ELSE 'coordinationChanged' END,
  'normal', 'Noise', 'Body', '/attention', 'dedup-' || r.id,
  CAST('2026-07-' || ((r.i % 28) + 1) || 'T12:00:00Z' AS timestamptz),
  @beaconPrefix || lpad(r.i::text, 3, '0'), 'source-' || r.id,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  CAST(@obligation AS boolean),
  CASE WHEN CAST(@obligation AS boolean)
    THEN 'v1|needsMe|' || r.id || '|' || @accountId END
FROM (
  SELECT i, @idPrefix || lpad(i::text, 4, '0') AS id
  FROM generate_series(0, CAST(@count AS int) - 1) AS i
) r
"""),
        parameters: {
          'accountId': accountId,
          'count': count,
          'obligation': obligation,
          'beaconPrefix': otherBeaconPrefix,
          'idPrefix': idPrefix,
        },
      );
    }

    Future<String> explainBridgeUpdatePlan({
      required String accountId,
    }) async {
      await writer.execute('SET enable_seqscan = off');
      final plan = await writer.execute(
        Sql.named(r'''
EXPLAIN (COSTS OFF)
UPDATE public.notification_outbox n
SET seen_at = COALESCE(n.seen_at, now())
WHERE n.account_id = @accountId
  AND n.beacon_id = @beaconId
  AND n.coordination_item_id IS NOT DISTINCT FROM @threadItemId
  AND n.destination_kind = 'beacon_room_message'
  AND n.seen_at IS NULL
  AND EXISTS (
    SELECT 1
    FROM public.beacon_room_message message
    WHERE message.id = n.target_entity_id
      AND message.beacon_id = @beaconId
      AND message.thread_item_id IS NOT DISTINCT FROM @threadItemId
      AND message.created_at <= @lastSeenAt
  )
'''),
        parameters: {
          'accountId': accountId,
          'beaconId': targetBeaconId,
          'threadItemId': null,
          'lastSeenAt': watermarkAt,
        },
      );
      return plan.map((row) => row.single).join('\n');
    }

    void expectRoomMessageUnseenIndexPlan(String planText) {
      expect(planText, isNot(contains('Seq Scan on notification_outbox')));
      expect(
        planText,
        contains('notification_outbox__room_message_unseen'),
        reason:
            'bridge_attention_room_seen UPDATE must use the room-message '
            'unseen partial index (plan §P1.6):\n$planText',
      );
    }

    test(
      'obligation-heavy author fixture uses notification_outbox__room_message_unseen',
      () async {
        if (skipReason != false) {
          return;
        }
        await seedUser(authorAccountId, 1);
        await seedBeacon(id: targetBeaconId, ownerId: authorAccountId);

        await insertNoise(
          accountId: authorAccountId,
          count: 180,
          obligation: true,
        );

        for (var i = 0; i < 20; i++) {
          final messageId = 'Rbrdgplnauth${i.toString().padLeft(2, '0')}';
          await insertRoomMessage(
            messageId: messageId,
            authorId: authorAccountId,
            createdAt: watermarkAt.subtract(Duration(hours: i + 1)),
          );
          await insertRoomMessageReceipt(
            accountId: authorAccountId,
            receiptId: 'Nbrdgplnauth${i.toString().padLeft(2, '0')}',
            messageId: messageId,
            createdAt: '2026-08-01T10:00:00Z',
            requiresAction: false,
          );
        }

        await writer.execute('ANALYZE public.notification_outbox');

        final planText = await explainBridgeUpdatePlan(
          accountId: authorAccountId,
        );
        expectRoomMessageUnseenIndexPlan(planText);
      },
      skip: skipReason,
    );

    test(
      'optional-only helper fixture uses notification_outbox__room_message_unseen',
      () async {
        if (skipReason != false) {
          return;
        }
        await seedUser(helperAccountId, 2);
        await seedBeacon(id: targetBeaconId, ownerId: helperAccountId);

        await insertNoise(
          accountId: helperAccountId,
          count: 180,
          obligation: false,
        );

        for (var i = 0; i < 20; i++) {
          final messageId = 'Rbrdgplnhelp${i.toString().padLeft(2, '0')}';
          await insertRoomMessage(
            messageId: messageId,
            authorId: helperAccountId,
            createdAt: watermarkAt.subtract(Duration(hours: i + 1)),
          );
          await insertRoomMessageReceipt(
            accountId: helperAccountId,
            receiptId: 'Nbrdgplnhelp${i.toString().padLeft(2, '0')}',
            messageId: messageId,
            createdAt: '2026-08-01T10:00:00Z',
            requiresAction: false,
          );
        }

        await writer.execute('ANALYZE public.notification_outbox');

        final planText = await explainBridgeUpdatePlan(
          accountId: helperAccountId,
        );
        expectRoomMessageUnseenIndexPlan(planText);
      },
      skip: skipReason,
    );
  });
}
