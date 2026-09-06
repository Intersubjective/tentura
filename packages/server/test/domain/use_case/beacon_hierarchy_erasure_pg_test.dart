@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/user_erasure_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/user_erasure_test_stack.dart';
import '../../data/repository/beacon_hierarchy_pg_helpers.dart';

final class _FailingUserRepository extends UserRepository {
  _FailingUserRepository(
    super.env,
    super.database,
    super.trustEvidenceRepository,
    super.inviteGenealogyRepository,
    super.inviteSeedPrompt,
  );

  var failOnDelete = false;

  @override
  Future<void> deleteById({required String id}) async {
    if (failOnDelete) {
      throw StateError('injected user delete failure');
    }
    return super.deleteById(id: id);
  }
}

Future<Map<String, Object?>> _beaconSnapshot(
  Connection writer,
  String beaconId,
) async {
  final row = await writer.execute(
    Sql.named(r'''
SELECT id, user_id, title, description, status, parent_beacon_id, published_at
FROM public.beacon WHERE id = @id
'''),
    parameters: {'id': beaconId},
  );
  expect(row, hasLength(1));
  return {
    'id': row.single[0],
    'user_id': row.single[1],
    'title': row.single[2],
    'description': row.single[3],
    'status': row.single[4],
    'parent_beacon_id': row.single[5],
    'published_at': row.single[6]?.toString(),
  };
}

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for hierarchy erasure PG test';

  group('Account erasure preserves hierarchy structure', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late UserErasureTestStack stack;
    late _FailingUserRepository users;
    late BeaconHierarchyRepository hierarchy;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      users = _FailingUserRepository(
        Env(environment: Environment.test),
        session.db,
        _NoopTrustEvidenceRepository(),
        _NoopInviteGenealogyRepository(),
        InviteSeedPromptRepositoryMock(),
      );
      final room = BeaconRoomRepository(session.db);
      final helpOffers = HelpOfferRepository(session.db);
      final commitments = CommitmentRepository(session.db);
      final outbox = BeaconHierarchyOutboxRepository(session.db);
      final lifecycleEffects = BeaconLifecycleEffectsCase(
        outbox,
        env: Env(environment: Environment.test),
        logger: Logger('HierarchyErasurePgTest'),
      );
      final dispatch = AttentionDispatchRepository(
        session.db,
        Logger('HierarchyErasurePgTest'),
      );
      final attentionIntents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          room,
          session.db,
          helpOffers,
          commitments,
        ),
        users,
        BeaconAccessRepository(session.db),
        FakeUserBlockRepository(),
      );
      final attention = TransactionalAttentionCase(
        MutatingUnitOfWork(session.db),
        dispatch,
      );
      stack = buildUserErasureTestStack(
        db: session.db,
        userRepository: users,
        lifecycleEffects: lifecycleEffects,
        attention: attention,
      );
      hierarchy = BeaconHierarchyRepository(session.db);
    });

    setUp(() async {
      if (skipReason != false) {
        return;
      }
      users.failOnDelete = false;
      await writer.execute(
        "DELETE FROM public.beacon_hierarchy_deliveries "
        "WHERE event_id LIKE 'Hier%' OR target_beacon_id LIKE 'Berasure%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_hierarchy_events "
        "WHERE source_beacon_id LIKE 'Berasure%' OR id LIKE 'Hier%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_evaluation_ack_tag "
        "WHERE evaluator_id LIKE 'Uerasure%' OR subject_id LIKE 'Uerasure%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_evaluation_visibility "
        "WHERE evaluator_id LIKE 'Uerasure%' OR participant_id LIKE 'Uerasure%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_evaluation_participant "
        "WHERE user_id LIKE 'Uerasure%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_evaluation "
        "WHERE evaluator_id LIKE 'Uerasure%' OR evaluated_user_id LIKE 'Uerasure%'",
      );
      await writer.execute(
        "DELETE FROM public.person_capability_event "
        "WHERE observer_user_id LIKE 'Uerasure%' OR subject_user_id LIKE 'Uerasure%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_fact_card WHERE beacon_id LIKE 'Berasure%'",
      );
      await writer.execute(
        "DELETE FROM public.coordination_item WHERE beacon_id LIKE 'Berasure%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon WHERE id LIKE 'Berasure%'",
      );
      await writer.execute(
        "DELETE FROM public.\"user\" WHERE id LIKE 'Uerasure%'",
      );
      await fixture.tearDown();
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await writer.close();
      await target.drop();
    });

    test('erasing owner of A retains B/C/D structure and scrubs A', () async {
      final beforeB = await _beaconSnapshot(writer, BeaconHierarchyTopology.beaconB);
      final beforeC = await _beaconSnapshot(writer, BeaconHierarchyTopology.beaconC);
      final beforeD = await _beaconSnapshot(writer, BeaconHierarchyTopology.beaconD);

      expect(await stack.userCase.deleteById(id: BeaconHierarchyTopology.aliceId), isTrue);

      final afterA = await _beaconSnapshot(writer, BeaconHierarchyTopology.beaconA);
      expect(afterA['user_id'], isNull);
      expect(afterA['status'], BeaconStatus.deleted.smallintValue);
      expect(afterA['title'], UserErasureScrubPlaceholders.title);
      expect(afterA['description'], UserErasureScrubPlaceholders.description);
      expect(afterA['parent_beacon_id'], isNull);

      expect(await _beaconSnapshot(writer, BeaconHierarchyTopology.beaconB), beforeB);
      expect(await _beaconSnapshot(writer, BeaconHierarchyTopology.beaconC), beforeC);
      expect(await _beaconSnapshot(writer, BeaconHierarchyTopology.beaconD), beforeD);

      final structural = await hierarchy.loadStructuralRecord(
        BeaconHierarchyTopology.beaconA,
      );
      expect(structural, isNotNull);
      expect(structural!.isTombstone, isTrue);
      expect(structural.parentBeaconId, isNull);
    });

    test('erasing owner of B retains parent links on C and scrubs B only', () async {
      final beforeA = await _beaconSnapshot(writer, BeaconHierarchyTopology.beaconA);
      final beforeC = await _beaconSnapshot(writer, BeaconHierarchyTopology.beaconC);

      expect(await stack.userCase.deleteById(id: BeaconHierarchyTopology.bobId), isTrue);

      final afterB = await _beaconSnapshot(writer, BeaconHierarchyTopology.beaconB);
      expect(afterB['user_id'], isNull);
      expect(afterB['status'], BeaconStatus.deleted.smallintValue);
      expect(afterB['parent_beacon_id'], BeaconHierarchyTopology.beaconA);

      final afterC = await _beaconSnapshot(writer, BeaconHierarchyTopology.beaconC);
      expect(afterC['parent_beacon_id'], BeaconHierarchyTopology.beaconB);
      expect(await _beaconSnapshot(writer, BeaconHierarchyTopology.beaconA), beforeA);
      expect(afterC['user_id'], beforeC['user_id']);
      expect(afterC['status'], beforeC['status']);
      expect(afterC['title'], beforeC['title']);
    });

    test('raw user delete is denied while non-deleted owned requests remain', () async {
      await writer.execute(
        Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {
          'id': 'Uerasureowner1',
          'key': 'erasure-owner-key-00000000000000000000001',
        },
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, published_at, created_at, updated_at
) VALUES (
  'Berasureown1', 'Uerasureowner1', 'Owned open', '', 0,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
      );

      expect(
        () => writer.execute(
          Sql.named('DELETE FROM public."user" WHERE id = @id'),
          parameters: {'id': 'Uerasureowner1'},
        ),
        throwsA(isA<PgException>()),
      );

      final remaining = await writer.execute(
        Sql.named(
          'SELECT count(*)::int FROM public."user" WHERE id = @id',
        ),
        parameters: {'id': 'Uerasureowner1'},
      );
      expect(remaining.single.single, 1);
    });

    test('failed erasure rolls back completely', () async {
      await writer.execute(
        Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {
          'id': 'Uerasurefail01',
          'key': 'erasure-fail-key-000000000000000000000001',
        },
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, published_at, created_at, updated_at
) VALUES (
  'Berasurefail1', 'Uerasurefail01', 'Rollback me', 'secret', 0,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
      );

      users.failOnDelete = true;

      await expectLater(
        stack.userCase.deleteById(id: 'Uerasurefail01'),
        throwsA(isA<StateError>()),
      );

      final beacon = await _beaconSnapshot(writer, 'Berasurefail1');
      expect(beacon['status'], 0);
      expect(beacon['title'], 'Rollback me');
      expect(beacon['description'], 'secret');
      expect(beacon['user_id'], 'Uerasurefail01');

      final userCount = await writer.execute(
        Sql.named(
          'SELECT count(*)::int FROM public."user" WHERE id = @id',
        ),
        parameters: {'id': 'Uerasurefail01'},
      );
      expect(userCount.single.single, 1);
    });

    test('nullable-and-anonymise FK dispositions complete erasure', () async {
      const erasedId = 'Uerasurefk001';
      await writer.execute(
        Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {
          'id': erasedId,
          'key': 'erasure-fk-key-000000000000000000000001',
        },
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, published_at, created_at, updated_at
) VALUES (
  'Berasurefk01', @userId, 'FK disposition', 'body', 0,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
        parameters: {'userId': erasedId},
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_fact_card (
  id, beacon_id, fact_text, visibility, status, pinned_by, created_at, updated_at
) VALUES (
  'Fcerasure001', 'Berasurefk01', 'Fact body', 0, 0, @pinner,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
        parameters: {'pinner': erasedId},
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id, target_person_id,
  accepted_by_id, published, created_at, updated_at, published_at, source, ordering
) VALUES (
  'Icerasure001', 'Berasurefk01', @kind, @status, 'Plan', '', @creator, @target,
  @acceptor, true, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z', 0, 0
)
'''),
        parameters: {
          'kind': coordinationItemKindPlan,
          'status': coordinationItemStatusOpen,
          'creator': erasedId,
          'target': BeaconHierarchyTopology.bobId,
          'acceptor': BeaconHierarchyTopology.carolId,
        },
      );

      expect(await stack.userCase.deleteById(id: erasedId), isTrue);

      final fact = await writer.execute(
        Sql.named(
          'SELECT pinned_by FROM public.beacon_fact_card WHERE id = @id',
        ),
        parameters: {'id': 'Fcerasure001'},
      );
      expect(fact.single[0], isNull);

      final plan = await writer.execute(
        Sql.named(r'''
SELECT creator_id, target_person_id, accepted_by_id
FROM public.coordination_item WHERE id = @id
'''),
        parameters: {'id': 'Icerasure001'},
      );
      expect(plan.single[0], isNull);
      expect(plan.single[1], BeaconHierarchyTopology.bobId);
      expect(plan.single[2], BeaconHierarchyTopology.carolId);
    });

    test('delivered hierarchy notices survive erasing the notice author', () async {
      const noticeId = 'Rhiererasure01';
      const eventId = 'Hiererasure001';
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_hierarchy_events (
  id, source_beacon_id, source_sequence, from_status, to_status,
  occurred_at, actor_user_id
) VALUES (
  @eventId, @source, 1, 0, 5, '2026-01-03T00:00:00Z', @actor
)
ON CONFLICT DO NOTHING
'''),
        parameters: {
          'eventId': eventId,
          'source': BeaconHierarchyTopology.beaconA,
          'actor': BeaconHierarchyTopology.aliceId,
        },
      );
      await writer.execute(
        Sql.named(r'''
UPDATE public.beacon
SET hierarchy_event_sequence = 1
WHERE id = @source
'''),
        parameters: {'source': BeaconHierarchyTopology.beaconA},
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, created_at,
  system_message_kind, hierarchy_notice_identity
) VALUES (
  @noticeId, @target, @author, 'Ancestor entered Wrapping up',
  '2026-01-03T00:00:00Z',
  @systemKind, @identity
)
ON CONFLICT DO NOTHING
'''),
        parameters: {
          'noticeId': noticeId,
          'target': BeaconHierarchyTopology.beaconB,
          'author': BeaconHierarchyTopology.aliceId,
          'systemKind': BeaconRoomSystemMessageKind.hierarchyLifecycle,
          'identity': 'hierarchy:$eventId:${BeaconHierarchyTopology.beaconB}',
        },
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_hierarchy_deliveries (
  event_id, target_beacon_id, direction, state, attempt_count,
  next_attempt_at, notice_message_id, completed_at
) VALUES (
  @eventId, @target, 'ancestor', 'delivered', 0,
  '2026-01-03T00:00:00Z', @noticeId, '2026-01-03T00:00:00Z'
)
ON CONFLICT DO NOTHING
'''),
        parameters: {
          'eventId': eventId,
          'target': BeaconHierarchyTopology.beaconB,
          'noticeId': noticeId,
        },
      );

      expect(
        await stack.userCase.deleteById(id: BeaconHierarchyTopology.aliceId),
        isTrue,
      );

      final message = await writer.execute(
        Sql.named(r'''
SELECT author_id, body, hierarchy_notice_identity
FROM public.beacon_room_message WHERE id = @id
'''),
        parameters: {'id': noticeId},
      );
      expect(message, hasLength(1));
      expect(message.single[0], isNull);
      expect(message.single[1], contains('Wrapping up'));
      expect(message.single[2], isNotNull);

      final delivery = await writer.execute(
        Sql.named(r'''
SELECT state, notice_message_id, lease_owner, lease_until
FROM public.beacon_hierarchy_deliveries
WHERE event_id = @eventId AND target_beacon_id = @target
'''),
        parameters: {
          'eventId': eventId,
          'target': BeaconHierarchyTopology.beaconB,
        },
      );
      expect(delivery, hasLength(1));
      expect(delivery.single[0], BeaconHierarchyDeliveryStateWire.delivered);
      expect(delivery.single[1], noticeId);
      expect(delivery.single[2], isNull);
      expect(delivery.single[3], isNull);
    });

    test(
      'erasing the offering user removes their help-offer commitment '
      'chain, but erasing a mere commitment actor anonymises it in place',
      () async {
        // beacon_help_offer's primary key is the composite (beacon_id,
        // user_id) — it cannot be made nullable, so an erased offerer's
        // offer row (and anything with a hard composite FK to it, e.g.
        // beacon_commitment_event's `beacon_commitment_event_offer_fk`)
        // is removed together as one unit, the same way a user's own
        // authored content is removed rather than left orphaned. This is
        // distinct from — and must not be confused with — erasing a user
        // who only appears as a commitment event's *actor*: that case is
        // already covered by nullable-and-anonymise (actor_user_id -> NULL,
        // the event row itself survives). This test makes both properties
        // explicit and verified, not an unverified side effect.
        const offererId = 'Uerasureoffer1';
        const actorOnlyId = 'Uerasureactor1';
        const ownerId = 'Uerasureowner1';
        const beaconId = 'Berasurehelp01';
        const actorEventId = 'CEerasureact01';

        await writer.execute(
          Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  (@offerer, @offerer, @offererKey),
  (@actorOnly, @actorOnly, @actorKey),
  (@owner, @owner, @ownerKey)
'''),
          parameters: {
            'offerer': offererId,
            'offererKey': 'erasure-offerer-key-0000000000001',
            'actorOnly': actorOnlyId,
            'actorKey': 'erasure-actoronly-key-000000001',
            'owner': ownerId,
            'ownerKey': 'erasure-owner-key-00000000000001',
          },
        );
        await writer.execute(
          Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, created_at, updated_at
) VALUES (@id, @owner, 'Help offer erasure', 'body', 0, now(), now())
'''),
          parameters: {'id': beaconId, 'owner': ownerId},
        );
        await writer.execute(
          Sql.named(r'''
INSERT INTO public.beacon_help_offer (
  beacon_id, user_id, message, status, created_at, updated_at
) VALUES (@beacon, @offerer, 'I can help', 0, now(), now())
'''),
          parameters: {'beacon': beaconId, 'offerer': offererId},
        );
        // Commitment event where a DIFFERENT user (actorOnlyId) is only the
        // acting party — must survive erasure of that actor, anonymised.
        await writer.execute(
          Sql.named(r'''
INSERT INTO public.beacon_commitment_event (
  id, beacon_id, user_id, actor_user_id, kind, created_at
) VALUES (@id, @beacon, @offerer, @actorOnly, 1, now())
'''),
          parameters: {
            'id': actorEventId,
            'beacon': beaconId,
            'offerer': offererId,
            'actorOnly': actorOnlyId,
          },
        );

        // Erase the mere actor first: the commitment event must survive,
        // anonymised.
        expect(await stack.userCase.deleteById(id: actorOnlyId), isTrue);
        final afterActorErasure = await writer.execute(
          Sql.named(r'''
SELECT user_id, actor_user_id FROM public.beacon_commitment_event
WHERE id = @id
'''),
          parameters: {'id': actorEventId},
        );
        expect(afterActorErasure, hasLength(1));
        expect(afterActorErasure.single[0], offererId);
        expect(afterActorErasure.single[1], isNull);

        // Now erase the OFFERER — the offer row and its dependent
        // commitment event are removed together (documented, intentional).
        expect(await stack.userCase.deleteById(id: offererId), isTrue);
        final offerAfter = await writer.execute(
          Sql.named(r'''
SELECT beacon_id FROM public.beacon_help_offer WHERE beacon_id = @beacon
'''),
          parameters: {'beacon': beaconId},
        );
        expect(offerAfter, isEmpty);
        final eventAfter = await writer.execute(
          Sql.named(
            'SELECT id FROM public.beacon_commitment_event WHERE id = @id',
          ),
          parameters: {'id': actorEventId},
        );
        expect(eventAfter, isEmpty);

        // The beacon itself (owned by a third, non-erased user) is wholly
        // unaffected by either erasure.
        final beaconAfter = await writer.execute(
          Sql.named(
            'SELECT user_id, status FROM public.beacon WHERE id = @id',
          ),
          parameters: {'id': beaconId},
        );
        expect(beaconAfter.single[0], ownerId);
        expect(beaconAfter.single[1], BeaconStatus.open.smallintValue);
      },
    );
  }, skip: skipReason);
}

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
