@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_command_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_child_create_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/pg_test_public_keys.dart';
import 'beacon_hierarchy_pg_helpers.dart';

final class _ThrowingAttentionDispatch implements AttentionDispatchPort {
  _ThrowingAttentionDispatch(this._inner);

  final AttentionDispatchPort _inner;
  var failNextRecord = false;
  int recordCalls = 0;

  @override
  Future<void> record(AttentionDispatchIntent intent) async {
    recordCalls++;
    if (failNextRecord) {
      failNextRecord = false;
      throw StateError('injected attention failure');
    }
    await _inner.record(intent);
  }
}

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon child create PG test';

  group('BeaconChildCreateCase — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late BeaconRepository beacons;
    late BeaconHierarchyCommandRepository commands;
    late BeaconHierarchyRepository hierarchy;
    late BeaconChildCreateCase case_;
    late _ThrowingAttentionDispatch throwingDispatch;
    late AttentionDispatchRepository dispatchRepo;
    late AttentionIntentCase attentionIntents;

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
      commands = BeaconHierarchyCommandRepository(session.db);
      hierarchy = BeaconHierarchyRepository(session.db);
      dispatchRepo = AttentionDispatchRepository(
        session.db,
        Logger('beacon_child_create_pg'),
      );
      throwingDispatch = _ThrowingAttentionDispatch(dispatchRepo);
      final unitOfWork = MutatingUnitOfWork(session.db);
      final room = BeaconRoomRepository(session.db);
      attentionIntents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          room,
          session.db,
          HelpOfferRepository(session.db),
          CommitmentRepository(session.db),
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
      case_ = BeaconChildCreateCase(
        beacons,
        hierarchy,
        commands,
        BeaconAccessRepository(session.db),
        BeaconRoomNotificationContextRepository(
          room,
          session.db,
          HelpOfferRepository(session.db),
          CommitmentRepository(session.db),
        ),
        attentionIntents: attentionIntents,
        attention: TransactionalAttentionCase(
          unitOfWork,
          throwingDispatch,
        ),
        env: Env(environment: Environment.test),
        logger: Logger('beacon_child_create_pg'),
      );
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        r'''
DELETE FROM public.attention_channel_delivery
WHERE occurrence_id IN (
  SELECT id FROM public.attention_occurrence
  WHERE source_event_key LIKE 'child_created%'
)''',
      );
      await writer.execute(
        r'''
DELETE FROM public.notification_outbox
WHERE occurrence_id IN (
  SELECT id FROM public.attention_occurrence
  WHERE source_event_key LIKE 'child_created%'
)''',
      );
      await writer.execute(
        r'''
DELETE FROM public.attention_occurrence_recipient
WHERE occurrence_id IN (
  SELECT id FROM public.attention_occurrence
  WHERE source_event_key LIKE 'child_created%'
)''',
      );
      await writer.execute(
        "DELETE FROM public.attention_occurrence WHERE source_event_key LIKE 'child_created%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_promotions WHERE parent_beacon_id LIKE 'Bhier%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_child_commands WHERE client_command_id LIKE 'cmd-%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_room_message WHERE hierarchy_notice_identity LIKE 'child_created:%'",
      );
      await writer.execute(
        "DELETE FROM public.user_block WHERE blocker_id LIKE 'Uhier%' OR blocked_id LIKE 'Uhier%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon WHERE parent_beacon_id LIKE 'Bhier%'",
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

    test('creates draft child with idempotent replay', () async {
      await fixture.seedFullTopology();

      const commandId = 'cmd-draft-replay-01';
      final first = await case_.createChild(
        actorUserId: BeaconHierarchyTopology.aliceId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        clientCommandId: commandId,
        title: 'Child title',
        description: 'Child body',
        draft: true,
      );
      expect(first.outcome, BeaconChildCommandOutcome.created);
      expect(first.beaconId, isNotNull);

      final second = await case_.createChild(
        actorUserId: BeaconHierarchyTopology.aliceId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        clientCommandId: commandId,
        title: 'Child title',
        description: 'Child body',
        draft: true,
      );
      expect(second.outcome, BeaconChildCommandOutcome.replayed);
      expect(second.beaconId, first.beaconId);

      final count = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.beacon WHERE parent_beacon_id = @parent',
        ),
        parameters: {'parent': BeaconHierarchyTopology.beaconA},
      );
      expect(count.single.first, 1);
    }, skip: skipReason);

    test('rejects hash conflict for same client command id', () async {
      await fixture.seedFullTopology();
      await case_.createChild(
        actorUserId: BeaconHierarchyTopology.aliceId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        clientCommandId: 'cmd-conflict-01',
        title: 'One',
        description: 'Alpha',
        draft: true,
      );

      await expectLater(
        case_.createChild(
          actorUserId: BeaconHierarchyTopology.aliceId,
          parentBeaconId: BeaconHierarchyTopology.beaconA,
          clientCommandId: 'cmd-conflict-01',
          title: 'Two',
          description: 'Beta',
          draft: true,
        ),
        throwsA(isA<BeaconChildCommandConflictException>()),
      );
    }, skip: skipReason);

    test('returns command gone after draft delete marker', () async {
      await fixture.seedFullTopology();
      const commandId = 'cmd-gone-02';
      await case_.createChild(
        actorUserId: BeaconHierarchyTopology.aliceId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        clientCommandId: commandId,
        title: 'Draft',
        description: 'Body',
        draft: true,
      );
      await commands.markCommandDeleted(
        actorUserId: BeaconHierarchyTopology.aliceId,
        clientCommandId: commandId,
      );

      await expectLater(
        case_.createChild(
          actorUserId: BeaconHierarchyTopology.aliceId,
          parentBeaconId: BeaconHierarchyTopology.beaconA,
          clientCommandId: commandId,
          title: 'Draft',
          description: 'Body',
          draft: true,
        ),
        throwsA(isA<BeaconChildCommandGoneException>()),
      );
    }, skip: skipReason);

    test('promotion draft seeds description from source text', () async {
      await fixture.seedFullTopology();

      final result = await case_.createChild(
        actorUserId: BeaconHierarchyTopology.aliceId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        sourceMessageId: BeaconHierarchyTopology.generalMessageOnA,
        clientCommandId: 'cmd-promo-seed-01',
        title: '',
        description: '',
        draft: true,
      );

      final row = await writer.execute(
        Sql.named(
          'SELECT description FROM public.beacon WHERE id = @id',
        ),
        parameters: {'id': result.beaconId},
      );
      expect(
        row.single.first,
        'General message on A for promotion source fixture',
      );
    }, skip: skipReason);

    test('publishes draft while parent is Wrapping up', () async {
      await fixture.seedFullTopology();
      await writer.execute(
        Sql.named(
          "UPDATE public.beacon SET status = @status WHERE id = @id",
        ),
        parameters: {
          'status': BeaconStatus.reviewOpen.smallintValue,
          'id': BeaconHierarchyTopology.beaconA,
        },
      );

      final draft = await case_.createChild(
        actorUserId: BeaconHierarchyTopology.aliceId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        clientCommandId: 'cmd-wrap-publish-01',
        title: 'Wrapping child',
        description: 'Still valid',
        draft: true,
      );

      final published = await case_.publishDraft(
        actorUserId: BeaconHierarchyTopology.aliceId,
        childBeaconId: draft.beaconId!,
      );
      expect(published.status, BeaconStatus.open);
      expect(published.publishedAt, isNotNull);
    }, skip: skipReason);

    test('rejects publish when parent becomes terminal after draft creation', () async {
      await fixture.seedFullTopology();
      final draft = await case_.createChild(
        actorUserId: BeaconHierarchyTopology.aliceId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        clientCommandId: 'cmd-parent-close-01',
        title: 'Late child',
        description: 'Body',
        draft: true,
      );
      await writer.execute(
        Sql.named(
          "UPDATE public.beacon SET status = @status WHERE id = @id",
        ),
        parameters: {
          'status': BeaconStatus.closed.smallintValue,
          'id': BeaconHierarchyTopology.beaconA,
        },
      );

      await expectLater(
        case_.publishDraft(
          actorUserId: BeaconHierarchyTopology.aliceId,
          childBeaconId: draft.beaconId!,
        ),
        throwsA(isA<BeaconParentNotCoordinatableException>()),
      );
    }, skip: skipReason);

    test('rejects publish after admission removal', () async {
      await fixture.seedFullTopology();
      await writer.execute(
        Sql.named(
          '''INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  'PhierbobA01', @beacon, @user, 0, 0, 3,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
) ON CONFLICT DO NOTHING''',
        ),
        parameters: {
          'beacon': BeaconHierarchyTopology.beaconA,
          'user': BeaconHierarchyTopology.bobId,
        },
      );
      final draft = await case_.createChild(
        actorUserId: BeaconHierarchyTopology.bobId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        clientCommandId: 'cmd-admission-loss-01',
        title: 'Admitted once',
        description: 'Body',
        draft: true,
      );
      await writer.execute(
        Sql.named(
          'DELETE FROM public.beacon_participant WHERE beacon_id = @beacon AND user_id = @user',
        ),
        parameters: {
          'beacon': BeaconHierarchyTopology.beaconA,
          'user': BeaconHierarchyTopology.bobId,
        },
      );

      await expectLater(
        case_.publishDraft(
          actorUserId: BeaconHierarchyTopology.bobId,
          childBeaconId: draft.beaconId!,
        ),
        throwsA(isA<BeaconChildCreateForbiddenException>()),
      );
    }, skip: skipReason);

    test('rejects publish when source message was deleted', () async {
      await fixture.seedFullTopology();
      final draft = await case_.createChild(
        actorUserId: BeaconHierarchyTopology.aliceId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        sourceMessageId: BeaconHierarchyTopology.generalMessageOnA,
        clientCommandId: 'cmd-source-delete-01',
        title: 'Promoted',
        description: '',
        draft: true,
      );
      await writer.execute(
        Sql.named('DELETE FROM public.beacon_room_message WHERE id = @id'),
        parameters: {'id': BeaconHierarchyTopology.generalMessageOnA},
      );

      await expectLater(
        case_.publishDraft(
          actorUserId: BeaconHierarchyTopology.aliceId,
          childBeaconId: draft.beaconId!,
        ),
        throwsA(isA<BeaconPromotionSourceInvalidException>()),
      );

      final provenance = await writer.execute(
        Sql.named(
          'SELECT source_message_id FROM public.beacon_promotions WHERE child_beacon_id = @child',
        ),
        parameters: {'child': draft.beaconId},
      );
      expect(provenance.single.first, isNull);
    }, skip: skipReason);

    test('races two promotion publishes — one wins, one alreadyPromoted', () async {
      await fixture.seedFullTopology();
      await writer.execute(
        Sql.named(
          '''INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  'PhierbobA02', @beacon, @bob, 0, 0, 3,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
), (
  'PhiercarolA02', @beacon, @carol, 0, 0, 3,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
) ON CONFLICT DO NOTHING''',
        ),
        parameters: {
          'beacon': BeaconHierarchyTopology.beaconA,
          'bob': BeaconHierarchyTopology.bobId,
          'carol': BeaconHierarchyTopology.carolId,
        },
      );

      final draft1 = await case_.createChild(
        actorUserId: BeaconHierarchyTopology.bobId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        sourceMessageId: BeaconHierarchyTopology.generalMessageOnA,
        clientCommandId: 'cmd-race-bob-01',
        title: 'Winner',
        description: '',
        draft: true,
      );
      final draft2 = await case_.createChild(
        actorUserId: BeaconHierarchyTopology.carolId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        sourceMessageId: BeaconHierarchyTopology.generalMessageOnA,
        clientCommandId: 'cmd-race-carol-01',
        title: 'Loser',
        description: '',
        draft: true,
      );

      await case_.publishDraft(
        actorUserId: BeaconHierarchyTopology.bobId,
        childBeaconId: draft1.beaconId!,
      );

      await expectLater(
        case_.publishDraft(
          actorUserId: BeaconHierarchyTopology.carolId,
          childBeaconId: draft2.beaconId!,
        ),
        throwsA(isA<BeaconSourceAlreadyPromotedException>()),
      );

      final publishedCount = await writer.execute(
        Sql.named(
          '''SELECT count(*) FROM public.beacon_promotions
WHERE source_message_id = @source AND published_at IS NOT NULL''',
        ),
        parameters: {'source': BeaconHierarchyTopology.generalMessageOnA},
      );
      expect(publishedCount.single.first, 1);
    }, skip: skipReason);

    test('rolls back publish when attention recording fails', () async {
      await fixture.seedFullTopology();
      await writer.execute(
        Sql.named(
          '''INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  'PhierbobA03', @beacon, @user, 0, 0, 3,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
) ON CONFLICT DO NOTHING''',
        ),
        parameters: {
          'beacon': BeaconHierarchyTopology.beaconA,
          'user': BeaconHierarchyTopology.bobId,
        },
      );
      final draft = await case_.createChild(
        actorUserId: BeaconHierarchyTopology.aliceId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        clientCommandId: 'cmd-attention-fail-01',
        title: 'Attention rollback',
        description: 'Body',
        draft: true,
      );

      throwingDispatch.failNextRecord = true;
      await expectLater(
        case_.publishDraft(
          actorUserId: BeaconHierarchyTopology.aliceId,
          childBeaconId: draft.beaconId!,
        ),
        throwsA(isA<StateError>()),
      );

      final status = await writer.execute(
        Sql.named('SELECT status, published_at FROM public.beacon WHERE id = @id'),
        parameters: {'id': draft.beaconId},
      );
      expect(status.single[0], BeaconStatus.draft.smallintValue);
      expect(status.single[1], isNull);

      final notices = await writer.execute(
        Sql.named(
          '''SELECT count(*) FROM public.beacon_room_message
WHERE hierarchy_notice_identity = @identity''',
        ),
        parameters: {'identity': 'child_created:${draft.beaconId}'},
      );
      expect(notices.single.first, 0);
    }, skip: skipReason);

    test('rejects publish after parent author blocks actor', () async {
      await fixture.seedFullTopology();
      await writer.execute(
        Sql.named(
          '''INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  'PhierbobA04', @beacon, @user, 0, 0, 3,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
) ON CONFLICT DO NOTHING''',
        ),
        parameters: {
          'beacon': BeaconHierarchyTopology.beaconA,
          'user': BeaconHierarchyTopology.bobId,
        },
      );
      final draft = await case_.createChild(
        actorUserId: BeaconHierarchyTopology.bobId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        clientCommandId: 'cmd-block-publish-01',
        title: 'Blocked later',
        description: 'Body',
        draft: true,
      );
      await writer.execute(
        Sql.named(
          r'''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocked)
ON CONFLICT DO NOTHING
''',
        ),
        parameters: {
          'blocker': BeaconHierarchyTopology.aliceId,
          'blocked': BeaconHierarchyTopology.bobId,
        },
      );

      await expectLater(
        case_.publishDraft(
          actorUserId: BeaconHierarchyTopology.bobId,
          childBeaconId: draft.beaconId!,
        ),
        throwsA(isA<BeaconChildCreateForbiddenException>()),
      );
    }, skip: skipReason);

    test('rolls back child insert when command record fails', () async {
      await fixture.seedFullTopology();
      await writer.execute(
        'DROP TRIGGER IF EXISTS test_fail_child_cmd ON public.beacon_child_commands',
      );
      await writer.execute(r'''
CREATE OR REPLACE FUNCTION test_fail_child_command_record()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.client_command_id LIKE 'cmd-child-fail%' THEN
    RAISE EXCEPTION 'injected child command record failure';
  END IF;
  RETURN NEW;
END;
$$''');
      await writer.execute(r'''
CREATE TRIGGER test_fail_child_cmd
  BEFORE INSERT ON public.beacon_child_commands
  FOR EACH ROW EXECUTE FUNCTION test_fail_child_command_record()
''');

      await expectLater(
        case_.createChild(
          actorUserId: BeaconHierarchyTopology.aliceId,
          parentBeaconId: BeaconHierarchyTopology.beaconA,
          clientCommandId: 'cmd-child-fail-01',
          title: 'Rollback child',
          description: 'Body',
          draft: true,
        ),
        throwsA(isA<Exception>()),
      );

      final childCount = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.beacon WHERE parent_beacon_id = @parent',
        ),
        parameters: {'parent': BeaconHierarchyTopology.beaconA},
      );
      expect(childCount.single.first, 0);

      await writer.execute(
        'DROP TRIGGER IF EXISTS test_fail_child_cmd ON public.beacon_child_commands',
      );
    }, skip: skipReason);

    test('rolls back when promotion publish insert fails mid-flight', () async {
      await fixture.seedFullTopology();
      await writer.execute('DROP TRIGGER IF EXISTS test_fail_promotion ON public.beacon_promotions');
      await writer.execute(r'''
CREATE OR REPLACE FUNCTION test_fail_promotion_publish()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.child_beacon_id LIKE 'B%' AND NEW.published_at IS NOT NULL THEN
    RAISE EXCEPTION 'injected promotion publish failure';
  END IF;
  RETURN NEW;
END;
$$''');
      await writer.execute(r'''
CREATE TRIGGER test_fail_promotion
  BEFORE INSERT OR UPDATE ON public.beacon_promotions
  FOR EACH ROW EXECUTE FUNCTION test_fail_promotion_publish()
''');

      final draft = await case_.createChild(
        actorUserId: BeaconHierarchyTopology.aliceId,
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        sourceMessageId: BeaconHierarchyTopology.generalMessageOnA,
        clientCommandId: 'cmd-promo-fail-01',
        title: 'Fail path',
        description: '',
        draft: true,
      );

      await expectLater(
        case_.publishDraft(
          actorUserId: BeaconHierarchyTopology.aliceId,
          childBeaconId: draft.beaconId!,
        ),
        throwsA(isA<Exception>()),
      );

      final childStatus = await writer.execute(
        Sql.named('SELECT status FROM public.beacon WHERE id = @id'),
        parameters: {'id': draft.beaconId},
      );
      expect(childStatus.single.first, BeaconStatus.draft.smallintValue);

      await writer.execute('DROP TRIGGER IF EXISTS test_fail_promotion ON public.beacon_promotions');
    }, skip: skipReason);
  });
}

final class _NoopTrustEvidenceRepository implements TrustEvidenceRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class _NoopInviteGenealogyRepository
    implements InviteGenealogyRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
