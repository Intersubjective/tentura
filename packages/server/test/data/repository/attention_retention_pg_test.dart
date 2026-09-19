@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/notification_outbox_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

import '../../support/disposable_pg_target.dart';

/// Retention must keep durable channel handoffs until they reach a terminal
/// state. Once a receipt has been seen and emailed, m0125 lets retention
/// remove terminal delivery jobs along with their receipt.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_RETENTION_TEST_DB',
    defaultNamePrefix: 'tentura_test_attretn',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('AttentionRetentionRepository deleteSettledOlderThan', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late NotificationOutboxRepository outbox;
    late AttentionDispatchRepository dispatch;
    late MutatingUnitOfWork unitOfWork;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      outbox = NotificationOutboxRepository(database);
      dispatch = AttentionDispatchRepository(database, Logger('attention_retention_pg_test'));
      unitOfWork = MutatingUnitOfWork(database);

      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('Uattretactor', 'Retention actor', 'attention-retention-actor-key')
''');
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test(
      'keeps pending and leased handoffs, and after U06b keeps the terminal '
      'and no-delivery receipts too',
      () async {
        final oldAt = DateTime.parse('2020-01-01T00:00:00Z');

        // A settled, old receipt with no delivery job attached.
        await writer.execute(
          Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at, emailed_at,
  source_event_key, destination_kind, presentation_key, access_policy
) VALUES (
  'Nattretlegacy', 'Uattretactor', 'asksOfMe', 'needsMe', 'normal',
  'No delivery', 'No delivery body', '/no-delivery',
  'attention-retention-no-delivery', @oldAt, @oldAt, @oldAt,
  'attention-retention-no-delivery', 'profile', 'invite_accepted', 'profile'
)
'''),
          parameters: {'oldAt': oldAt},
        );
        // Seeing a receipt alone must never discard an unsent digest entry.
        await writer.execute(
          Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at,
  source_event_key, destination_kind, presentation_key, access_policy
) VALUES (
  'Nattretunemailed', 'Uattretactor', 'asksOfMe', 'needsMe', 'normal',
  'Unsent digest', 'Unsent digest body', '/unsent-digest',
  'attention-retention-unsent-digest', @oldAt, @oldAt,
  'attention-retention-unsent-digest', 'profile', 'invite_accepted', 'profile'
)
'''),
          parameters: {'oldAt': oldAt},
        );

        Future<String> recordDeliveryBackedReceipt(String suffix) async {
          await unitOfWork.run(
            actorUserId: 'Uattretactor',
            action: () => dispatch.record(
              AttentionDispatchIntent(
                eventType: AttentionEventType.relayReceived,
                sourceEventKey: 'attention-retention-relay-$suffix',
                actorUserId: 'Uattretactor',
                priority: NotificationPriority.normal,
                kind: NotificationKind.newRelay,
                title: 'Forwarded Request',
                body: 'A Request was forwarded to you',
                actionUrl: '/#/view?id=Battret',
                collapseKey: 'attention-retention-relay-$suffix',
                recipients: const [
                  AttentionRecipientSnapshot(
                    recipientId: 'Uattretactor',
                    reasons: {AttentionRecipientReason.forwardRecipient},
                    role: AttentionRecipientRoleFacts(
                      canReadBeaconContent: true,
                      beaconId: 'Battret',
                      actorUserId: 'Uattretactor',
                    ),
                  ),
                ],
                beaconId: 'Battret',
              ),
            ),
          );
          final receipt = await writer.execute(
            Sql.named('''
SELECT id FROM public.notification_outbox
WHERE dedup_key = @dedupKey
'''),
            parameters: {
              'dedupKey':
                  'Uattretactor|attention-v1|attention-retention-relay-$suffix',
            },
          );
          return receipt.single.single! as String;
        }

        final pendingId = await recordDeliveryBackedReceipt('pending');
        final leasedId = await recordDeliveryBackedReceipt('leased');
        final terminalId = await recordDeliveryBackedReceipt('terminal');
        await writer.execute(
          Sql.named('''
UPDATE public.notification_outbox
SET seen_at = @oldAt, created_at = @oldAt, emailed_at = @oldAt
WHERE id IN (@pendingId, @leasedId, @terminalId)
'''),
          parameters: {
            'oldAt': oldAt,
            'pendingId': pendingId,
            'leasedId': leasedId,
            'terminalId': terminalId,
          },
        );
        await writer.execute(
          Sql.named('''
UPDATE public.attention_channel_delivery
SET status = 'leased', lease_owner = 'retention-test-worker',
    lease_until = @leaseUntil
WHERE receipt_id = @receiptId
'''),
          parameters: {
            'leaseUntil': oldAt.add(const Duration(minutes: 2)),
            'receiptId': leasedId,
          },
        );
        await writer.execute(
          Sql.named('''
UPDATE public.attention_channel_delivery
SET status = 'delivered', delivered_at = @deliveredAt
WHERE receipt_id = @receiptId
'''),
          parameters: {'deliveredAt': oldAt, 'receiptId': terminalId},
        );

        Future<int> deliveryCountFor(String receiptId) async {
          final rows = await writer.execute(
            Sql.named('''
SELECT count(*)::int FROM public.attention_channel_delivery
WHERE receipt_id = @receiptId
'''),
            parameters: {'receiptId': receiptId},
          );
          return rows.single.single! as int;
        }

        expect(await deliveryCountFor(pendingId), 1);
        expect(await deliveryCountFor(leasedId), 1);
        expect(await deliveryCountFor(terminalId), 1);

        final deleted = await outbox.deleteSettledOlderThan(
          const Duration(days: 30),
        );
        // U06b (D17): this was 2 before this unit. `Nattretlegacy` is an
        // uncleared optional (`requires_action = false AND cleared_at IS
        // NULL`) and the terminal relay receipt carries an `occurrence_id`,
        // so both are now retained history rather than retention fodder.
        expect(deleted, 0);

        final remaining = await writer.execute(
          r'''
SELECT count(*)::int FROM public.notification_outbox
WHERE id IN ('Nattretlegacy', 'Nattretunemailed', $1, $2, $3)
''',
          parameters: [pendingId, leasedId, terminalId],
        );
        expect(remaining.single.single, 5);
        final remainingIds = await writer.execute(
          r'''
SELECT id FROM public.notification_outbox
WHERE id IN ('Nattretlegacy', 'Nattretunemailed', $1, $2, $3)
ORDER BY id
''',
          parameters: [pendingId, leasedId, terminalId],
        );
        expect(remainingIds.map((row) => row.single).toSet(), {
          'Nattretlegacy',
          'Nattretunemailed',
          pendingId,
          leasedId,
          terminalId,
        });

        // Nothing was deleted, so no delivery job cascaded away (m0125).
        expect(await deliveryCountFor(pendingId), 1);
        expect(await deliveryCountFor(leasedId), 1);
        expect(await deliveryCountFor(terminalId), 1);
        final occurrence = await writer.execute('''
SELECT count(*)::int FROM public.attention_occurrence
WHERE source_event_key IN (
  'attention-retention-relay-pending',
  'attention-retention-relay-leased',
  'attention-retention-relay-terminal'
)
''');
        expect(occurrence.single.single, 3);
      },
    );

    test(
      'retains live obligations even when seen, emailed, and older than the retention window',
      () async {
        final oldAt = DateTime.parse('2020-01-01T00:00:00Z');

        await writer.execute(
          Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at, emailed_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key
) VALUES (
  'Nattretliveobl', 'Uattretactor', 'asksOfMe', 'needsMe', 'normal',
  'Live obligation', 'Still owed', '/live-obligation',
  'attention-retention-live-obligation', @oldAt, @oldAt, @oldAt,
  'Battret', 'attention-retention-live-obligation',
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  true, 'v1|needsMe|Nattretliveobl|Uattretactor'
)
'''),
          parameters: {'oldAt': oldAt},
        );

        final deleted = await outbox.deleteSettledOlderThan(
          const Duration(days: 30),
        );
        expect(deleted, 0);

        final remaining = await writer.execute('''
SELECT count(*)::int FROM public.notification_outbox
WHERE id = 'Nattretliveobl'
''');
        expect(remaining.single.single, 1);
      },
    );

    /// Seeds one legacy (`occurrence_id IS NULL`) receipt that is seen,
    /// emailed and older than the window, with no delivery job at all.
    Future<void> seedLegacy(
      String id, {
      required bool requiresAction,
      String? settlementKind,
      DateTime? clearedAt,
      String? clearReason,
    }) async {
      final oldAt = DateTime.parse('2020-01-01T00:00:00Z');
      await writer.execute(
        Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at, emailed_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key,
  settlement_kind, settled_at, cleared_at, clear_reason
) VALUES (
  @id, 'Uattretactor', 'asksOfMe', 'needsMe', 'normal',
  @id, @id, '/legacy', @id, @oldAt, @oldAt, @oldAt,
  'Battret', @id,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  @requiresAction, @threadKey,
  @settlementKind, @settledAt, @clearedAt, @clearReason
)
'''),
        parameters: {
          'id': id,
          'oldAt': oldAt,
          'requiresAction': requiresAction,
          'threadKey': requiresAction ? 'v1|needsMe|$id|Uattretactor' : null,
          'settlementKind': settlementKind,
          'settledAt': settlementKind == null ? null : oldAt,
          'clearedAt': clearedAt,
          'clearReason': clearReason,
        },
      );
    }

    Future<bool> exists(String id) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT count(*)::int FROM public.notification_outbox WHERE id = @id',
        ),
        parameters: {'id': id},
      );
      return (rows.single.single! as int) == 1;
    }

    test(
      'still deletes a legacy settled obligation that is seen, emailed, old '
      'and carries no pending delivery',
      () async {
        // Retention is NOT a no-op after U06b: this is the class that stays
        // deletable — pre-cutover rows (`occurrence_id IS NULL`) whose
        // obligation is already settled and which were never cleared. U18
        // backfill does not replay these.
        await seedLegacy(
          'Nattretlegacysettled',
          requiresAction: true,
          settlementKind: 'resolved',
        );
        expect(await exists('Nattretlegacysettled'), isTrue);

        final deleted = await outbox.deleteSettledOlderThan(
          const Duration(days: 30),
        );

        expect(deleted, 1);
        expect(await exists('Nattretlegacysettled'), isFalse);
      },
    );

    test(
      'retains an uncleared optional even when seen, emailed and old',
      () async {
        await seedLegacy('Nattretuncleared', requiresAction: false);

        expect(
          await outbox.deleteSettledOlderThan(const Duration(days: 30)),
          0,
        );
        expect(await exists('Nattretuncleared'), isTrue);
      },
    );

    test(
      'retains a cleared receipt — clearing is not deletion (D17)',
      () async {
        await seedLegacy(
          'Nattretcleared',
          requiresAction: false,
          clearedAt: DateTime.parse('2020-01-02T00:00:00Z'),
          clearReason: 'explicit',
        );

        expect(
          await outbox.deleteSettledOlderThan(const Duration(days: 30)),
          0,
        );
        expect(await exists('Nattretcleared'), isTrue);
      },
    );

    test(
      'retains a post-cutover settled obligation (occurrence_id IS NOT NULL)',
      () async {
        final oldAt = DateTime.parse('2020-01-01T00:00:00Z');
        await writer.execute(
          Sql.named('''
INSERT INTO public.attention_occurrence (
  id, event_type, source_event_key, actor_user_id, immutable_payload,
  occurred_at
) VALUES (
  'Oattretpostcut', 'relayReceived', 'attention-retention-postcutover',
  'Uattretactor', '{"beaconId":"Battret"}'::jsonb, @oldAt
)
'''),
          parameters: {'oldAt': oldAt},
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at, emailed_at,
  beacon_id, source_event_key, occurrence_id,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key, settlement_kind, settled_at
) VALUES (
  'Nattretpostcut', 'Uattretactor', 'asksOfMe', 'needsMe', 'normal',
  'Post cutover', 'Settled but retained', '/post-cutover',
  'attention-retention-postcutover', @oldAt, @oldAt, @oldAt,
  'Battret', 'attention-retention-postcutover', 'Oattretpostcut',
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  true, 'v1|needsMe|Nattretpostcut|Uattretactor', 'resolved', @oldAt
)
'''),
          parameters: {'oldAt': oldAt},
        );

        expect(
          await outbox.deleteSettledOlderThan(const Duration(days: 30)),
          0,
        );
        expect(await exists('Nattretpostcut'), isTrue);
      },
    );
  }, skip: skipReason);
}
