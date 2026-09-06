@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';

import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/recording_beacon_hierarchy_outbox.dart';
import 'beacon_hierarchy_pg_helpers.dart';

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for lifecycle atomic PG test';

  group('Beacon hierarchy lifecycle — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late BeaconRepository beacons;
    late BeaconHierarchyOutboxRepository outbox;
    late BeaconLifecycleEffectsCase lifecycleEffects;
    late TransactionalAttentionCase attention;
    late AttentionIntentCase attentionIntents;
    late ThrowingBeaconHierarchyOutbox throwingOutbox;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      beacons = BeaconRepository(session.db);
      outbox = BeaconHierarchyOutboxRepository(session.db);
      throwingOutbox = ThrowingBeaconHierarchyOutbox(outbox);
      lifecycleEffects = BeaconLifecycleEffectsCase(
        outbox,
        env: Env(environment: Environment.test),
        logger: Logger('LifecyclePgTest'),
      );
      final room = BeaconRoomRepository(session.db);
      final helpOffers = HelpOfferRepository(session.db);
      final commitments = CommitmentRepository(session.db);
      final dispatch = AttentionDispatchRepository(
        session.db,
        Logger('LifecyclePgTest'),
      );
      attentionIntents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          room,
          session.db,
          helpOffers,
          commitments,
        ),
        UserRepository(
          Env(environment: Environment.test),
          session.db,
          _NoopTrustEvidenceRepository(),
          _NoopInviteGenealogyRepository(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(session.db),
        FakeUserBlockRepository(),
      );
      attention = TransactionalAttentionCase(
        MutatingUnitOfWork(session.db),
        dispatch,
      );
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        "DELETE FROM public.beacon_hierarchy_deliveries WHERE event_id LIKE 'HE%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_hierarchy_events WHERE id LIKE 'HE%'",
      );
      await fixture.tearDown();
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await fixture.db.close();
      await writer.close();
      await target.drop();
    });

    test('topology insert is a single set-based statement', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      final plan = await writer.execute(
        Sql.named(r'''
EXPLAIN (FORMAT TEXT)
WITH RECURSIVE descendants AS (
  SELECT b.id
  FROM public.beacon b
  WHERE b.parent_beacon_id = @source
    AND b.published_at IS NOT NULL
  UNION ALL
  SELECT child.id
  FROM public.beacon child
  JOIN descendants d ON child.parent_beacon_id = d.id
  WHERE child.published_at IS NOT NULL
),
ancestor AS (
  SELECT p.id
  FROM public.beacon source
  JOIN public.beacon p ON p.id = source.parent_beacon_id
  WHERE source.id = @source
    AND p.published_at IS NOT NULL
),
targets AS (
  SELECT id AS target_beacon_id, 'ancestor'::text AS direction FROM descendants
  UNION ALL
  SELECT id, 'child'::text FROM ancestor
)
INSERT INTO public.beacon_hierarchy_deliveries (
  event_id, target_beacon_id, direction, state, next_attempt_at
)
SELECT 'HE-plan', target_beacon_id, direction, 'pending', now()
FROM targets
WHERE target_beacon_id <> @source
ON CONFLICT (event_id, target_beacon_id) DO NOTHING
'''),
        parameters: {'source': BeaconHierarchyTopology.beaconA},
      );
      final text = plan.map((r) => r[0]).join('\n');
      expect(text.toLowerCase(), contains('recursive'));
      expect(text.toLowerCase(), isNot(contains('function scan')));
    }, skip: skipReason);

    test(
      'close on A reaches C through deleted intermediate B and records ordered events',
      () async {
        await fixture.seedFullTopology();
        await seedPublishedHierarchyTree(writer);
        await writer.execute(
          Sql.named('UPDATE public.beacon SET status = 2 WHERE id = @id'),
          parameters: {'id': BeaconHierarchyTopology.beaconB},
        );

        final wrappingEvent = await lifecycleEffects.recordEligibleSourceTransition(
          sourceBeaconId: BeaconHierarchyTopology.beaconA,
          fromStatus: BeaconStatus.open,
          toStatus: BeaconStatus.reviewOpen,
          occurredAt: DateTime.utc(2026, 4, 1),
          actorUserId: BeaconHierarchyTopology.aliceId,
          reason: BeaconStatusTransitionReason.reviewWindowOpened,
        );
        final closedEvent = await lifecycleEffects.recordEligibleSourceTransition(
          sourceBeaconId: BeaconHierarchyTopology.beaconA,
          fromStatus: BeaconStatus.reviewOpen,
          toStatus: BeaconStatus.closed,
          occurredAt: DateTime.utc(2026, 4, 8),
          actorUserId: BeaconHierarchyTopology.aliceId,
          reason: BeaconStatusTransitionReason.authorCloseNow,
        );

        expect(wrappingEvent, isNotNull);
        expect(closedEvent, isNotNull);
        expect(wrappingEvent!.sourceSequence, 1);
        expect(closedEvent!.sourceSequence, 2);

        final deliveries = await writer.execute(
          Sql.named(r'''
SELECT target_beacon_id
FROM public.beacon_hierarchy_deliveries
WHERE event_id = @eventId
ORDER BY target_beacon_id
'''),
          parameters: {'eventId': closedEvent!.eventId},
        );
        expect(
          deliveries.map((r) => r[0]),
          contains(BeaconHierarchyTopology.beaconC),
        );
      },
      skip: skipReason,
    );

    test('outbox failure rolls back status transition and attention together', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      throwingOutbox.failOnTopologyInsert = true;
      final failingEffects = BeaconLifecycleEffectsCase(
        throwingOutbox,
        env: Env(environment: Environment.test),
        logger: Logger('LifecyclePgTest'),
      );

      await expectLater(
        attention.runAction<void>(
          actorUserId: BeaconHierarchyTopology.aliceId,
          action: (transaction) async {
            await beacons.runInBeaconStateTransaction(
              beaconId: BeaconHierarchyTopology.beaconA,
              userId: BeaconHierarchyTopology.aliceId,
              fn: (beacon) async {
                final intent = await attentionIntents.requestStatusChanged(
                  beaconId: BeaconHierarchyTopology.beaconA,
                  fromStatus: beacon.status.name,
                  toStatus: BeaconStatus.cancelled.name,
                  actorUserId: BeaconHierarchyTopology.aliceId,
                  sourceEventKey: 'request_status:rollback-test',
                );
                await failingEffects.recordEligibleSourceTransition(
                  sourceBeaconId: BeaconHierarchyTopology.beaconA,
                  fromStatus: beacon.status,
                  toStatus: BeaconStatus.cancelled,
                  occurredAt: DateTime.utc(2026, 5, 1),
                  actorUserId: BeaconHierarchyTopology.aliceId,
                  reason: BeaconStatusTransitionReason.cancelled,
                );
                await beacons.recordBeaconStatusTransition(
                  beaconId: BeaconHierarchyTopology.beaconA,
                  fromStatus: beacon.status,
                  toStatus: BeaconStatus.cancelled,
                  reason: 'cancelled',
                  actorId: BeaconHierarchyTopology.aliceId,
                );
                await transaction.record(intent);
              },
            );
          },
        ),
        throwsA(isA<StateError>()),
      );

      final statusRow = await writer.execute(
        Sql.named('SELECT status FROM public.beacon WHERE id = @id'),
        parameters: {'id': BeaconHierarchyTopology.beaconA},
      );
      expect(statusRow.single.first, BeaconStatus.open.smallintValue);

      final eventCount = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.beacon_hierarchy_events WHERE source_beacon_id = @id',
        ),
        parameters: {'id': BeaconHierarchyTopology.beaconA},
      );
      expect(eventCount.single.first, 0);

      final attentionCount = await writer.execute(
        Sql.named(
          "SELECT count(*) FROM public.attention_occurrence WHERE source_event_key = 'request_status:rollback-test'",
        ),
      );
      expect(attentionCount.single.first, 0);
    }, skip: skipReason);
  });
}
