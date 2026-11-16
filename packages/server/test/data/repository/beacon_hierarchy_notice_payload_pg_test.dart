@Tags(['pg'])
library;

import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_event.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_hierarchy_delivery_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/fake_user_block_repository.dart';
import 'beacon_hierarchy_pg_helpers.dart';

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

/// A Request closing notifies the members of the related Request in the
/// hierarchy. The stored receipt (and what the Request history serves) names
/// the Request the news is about and which way it travelled.
Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for hierarchy payload PG test';

  group('hierarchy notice facts — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late BeaconHierarchyOutboxRepository outbox;
    late BeaconHierarchyDeliveryCase delivery;
    late AttentionRepository feed;

    setUpAll(() async {
      if (skipReason != false) return;
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      outbox = BeaconHierarchyOutboxRepository(session.db);
      feed = AttentionRepository(session.db);
      delivery = BeaconHierarchyDeliveryCase(
        outbox,
        TransactionalAttentionCase(
          MutatingUnitOfWork(session.db),
          AttentionDispatchRepository(
            session.db,
            Logger('HierarchyNoticePayloadPg'),
          ),
        ),
        AttentionIntentCase(
          BeaconRoomNotificationContextRepository(
            BeaconRoomRepository(session.db),
            session.db,
            HelpOfferRepository(session.db),
            CommitmentRepository(session.db),
          ),
          UserRepository(
            Env(environment: Environment.test),
            session.db,
            _NoopInviteGenealogyRepository(),
            InviteSeedPromptRepositoryMock(),
          ),
          BeaconAccessRepository(session.db),
          FakeUserBlockRepository(),
        ),
        env: Env(environment: Environment.test),
        logger: Logger('HierarchyNoticePayloadPg'),
      );
    });

    tearDown(() async {
      if (skipReason != false) return;
      await writer.execute('''
DELETE FROM public.attention_channel_delivery WHERE occurrence_id IN (
  SELECT id FROM public.attention_occurrence
  WHERE source_event_key LIKE 'hierarchy:%')''');
      await writer.execute('''
DELETE FROM public.notification_outbox WHERE occurrence_id IN (
  SELECT id FROM public.attention_occurrence
  WHERE source_event_key LIKE 'hierarchy:%')''');
      await writer.execute('''
DELETE FROM public.attention_occurrence_recipient WHERE occurrence_id IN (
  SELECT id FROM public.attention_occurrence
  WHERE source_event_key LIKE 'hierarchy:%')''');
      await writer.execute(
        "DELETE FROM public.attention_occurrence WHERE source_event_key LIKE 'hierarchy:%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_hierarchy_deliveries WHERE event_id LIKE 'HE%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_hierarchy_events WHERE id LIKE 'HE%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_room_message WHERE hierarchy_notice_identity LIKE 'hierarchy:%'",
      );
      await fixture.tearDown();
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await fixture.db.close();
      await writer.close();
      await target.drop();
    });

    Future<void> addParticipant(String id, String beacon, String user) =>
        writer.execute(
          Sql.named('''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (@id, @beacon, @user, 0, 0, 3, now(), now())
ON CONFLICT DO NOTHING'''),
          parameters: {'id': id, 'beacon': beacon, 'user': user},
        );

    /// Source [source] closes; the notice is delivered to [targetBeacon].
    /// Returns the facts stored for [recipient] and the ones the feed serves.
    Future<({Map<String, Object?> stored, Map<String, Object?> served})>
    deliver({
      required String source,
      required String targetBeacon,
      required BeaconHierarchyDeliveryDirection direction,
      required String actor,
      required String recipient,
    }) async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      await addParticipant('Pnfphier0001', targetBeacon, recipient);
      final event = await outbox.recordEvent(
        occurredAt: DateTime.utc(2026, 6),
        sourceBeaconId: source,
        fromStatus: BeaconStatus.open,
        toStatus: BeaconStatus.closed,
        actorUserId: actor,
      );
      await outbox.insertDeliveryTargets(
        event: event,
        targets: [
          BeaconHierarchyDeliveryTarget(
            eventId: event.eventId,
            targetBeaconId: targetBeacon,
            direction: direction,
          ),
        ],
      );

      await delivery.runDue(workerId: 'worker-1', now: DateTime.timestamp());

      final rows = await writer.execute(
        Sql.named('''
SELECT presentation_payload::text FROM public.notification_outbox
WHERE account_id = @a AND presentation_key = 'beacon_hierarchy_status_changed'
'''),
        parameters: {'a': recipient},
      );
      expect(rows, hasLength(1), reason: 'one stored receipt');
      final stored =
          jsonDecode(rows.single[0]! as String) as Map<String, Object?>;

      // Hierarchy notices are timeline-only receipts: the client reads them
      // through the Request's history page, not the For You / Activity feed.
      final history = await feed.attentionRequestHistory(
        accountId: recipient,
        beaconId: targetBeacon,
      );
      final served = <Map<String, Object?>>[
        for (final r in history.items)
          if (r.presentationKey == 'beacon_hierarchy_status_changed')
            jsonDecode(
                  QueryAttention.mapReceiptForTesting(
                        r,
                      )['presentationPayloadJson']!
                      as String,
                )
                as Map<String, Object?>,
      ];
      expect(served, hasLength(1), reason: 'one receipt in the Request history');
      return (stored: stored, served: served.single);
    }

    test('closing a child tells the parent Request’s members which child it '
        'was', () async {
      final r = await deliver(
        source: BeaconHierarchyTopology.beaconB,
        targetBeacon: BeaconHierarchyTopology.beaconA,
        direction: BeaconHierarchyDeliveryDirection.child,
        actor: BeaconHierarchyTopology.bobId,
        recipient: BeaconHierarchyTopology.eveId,
      );

      for (final payload in [r.stored, r.served]) {
        expect(payload['beaconId'], BeaconHierarchyTopology.beaconA);
        expect(payload['relatedBeaconId'], BeaconHierarchyTopology.beaconB);
        expect(payload['direction'], 'child');
      }
    }, skip: skipReason);

    test('closing a parent tells the child Request’s members which parent it '
        'was', () async {
      final r = await deliver(
        source: BeaconHierarchyTopology.beaconA,
        targetBeacon: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
        actor: BeaconHierarchyTopology.aliceId,
        recipient: BeaconHierarchyTopology.carolId,
      );

      for (final payload in [r.stored, r.served]) {
        expect(payload['beaconId'], BeaconHierarchyTopology.beaconB);
        expect(payload['relatedBeaconId'], BeaconHierarchyTopology.beaconA);
        expect(payload['direction'], 'ancestor');
      }
    }, skip: skipReason);
  });
}
