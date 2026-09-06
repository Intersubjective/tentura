@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_expiry_repository.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/data/repository/evaluation_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/trust_evidence_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/entity/forward_delivery_result.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_close_review_result.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_status_result.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_draft_purger.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_participant_graph_builder.dart';
import 'package:tentura_server/domain/use_case/evaluation/review_finalization_case.dart';
import 'package:tentura_server/domain/use_case/evaluation_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../data/repository/beacon_hierarchy_pg_helpers.dart';
import '../../domain/evaluation/evaluation_graph_test_repos.dart';
import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/fake_user_block_repository.dart';

const _standaloneBeaconId = 'Bhierstand01';

/// Captures the structural shape of generic lifecycle use-case results so a
/// nested child can be compared to a standalone beacon without hierarchy fields.
final class LifecycleOutcomeShape {
  const LifecycleOutcomeShape({
    required this.forwardDeliveredCount,
    required this.forwardSkippedCount,
    required this.acceptStatus,
    required this.closeReviewStatus,
    required this.closeReviewHasClosesAt,
    required this.finalizeStatus,
    required this.finalizeDidClose,
    required this.finalizeTrustPairCount,
  });

  final int forwardDeliveredCount;
  final int forwardSkippedCount;
  final int acceptStatus;
  final int closeReviewStatus;
  final bool closeReviewHasClosesAt;
  final int finalizeStatus;
  final bool finalizeDidClose;
  final int finalizeTrustPairCount;

  Map<String, Object?> toComparableMap() => {
    'forwardDeliveredCount': forwardDeliveredCount,
    'forwardSkippedCount': forwardSkippedCount,
    'acceptStatus': acceptStatus,
    'closeReviewStatus': closeReviewStatus,
    'closeReviewHasClosesAt': closeReviewHasClosesAt,
    'finalizeStatus': finalizeStatus,
    'finalizeDidClose': finalizeDidClose,
    'finalizeTrustPairCount': finalizeTrustPairCount,
  };
}

final class _ChildIndependenceHarness {
  _ChildIndependenceHarness({
    required this.forwardCase,
    required this.helpOfferCase,
    required this.coordinationCase,
    required this.evaluationCase,
  });

  final ForwardCase forwardCase;
  final HelpOfferCase helpOfferCase;
  final CoordinationCase coordinationCase;
  final EvaluationCase evaluationCase;

  static _ChildIndependenceHarness build(TenturaDb db, Env env) {
    final logger = Logger('ChildIndependencePgTest');
    final unitOfWork = MutatingUnitOfWork(db);
    final dispatch = AttentionDispatchRepository(db, logger);
    final attention = TransactionalAttentionCase(unitOfWork, dispatch);
    final room = BeaconRoomRepository(db);
    final helpOffers = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final beacons = BeaconRepository(db);
    final access = BeaconAccessRepository(db);
    final hierarchy = BeaconHierarchyRepository(db);
    final outbox = BeaconHierarchyOutboxRepository(db);
    final lifecycleEffects = BeaconLifecycleEffectsCase(
      outbox,
      env: env,
      logger: logger,
    );
    final attentionIntents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(
        room,
        db,
        helpOffers,
        commitments,
      ),
      UserRepository(
        env,
        db,
        _NoopTrustEvidenceRepository(),
        _NoopInviteGenealogyRepository(),
        InviteSeedPromptRepositoryMock(),
      ),
      access,
      FakeUserBlockRepository(),
    );
    final capabilityCase = CapabilityCase(
      PersonCapabilityEventRepository(db),
      env: env,
      logger: logger,
    );
    final commitmentQuery = CommitmentQueryCase(
      commitments,
      helpOffers,
      env: env,
      logger: logger,
    );
    final evalRepo = EvaluationRepository(db);
    final forwardEdges = ForwardEdgeRepository(db);
    final profileLookup = DriftUserProfileBatchLookup(
      db,
      UserAvailabilityRepository(db),
    );
    final graphBuilder = EvaluationParticipantGraphBuilder(
      commitments,
      helpOffers,
      forwardEdges,
      StubUserRepository('User'),
    );
    final reviewFinalization = ReviewFinalizationCase(
      unitOfWork,
      evalRepo,
      forwardEdges,
      ForwardAttributionRepository(db),
      helpOffers,
      TrustEvidenceRepository(db),
      CapabilityEvidenceRepository(db),
      hierarchy,
      lifecycleEffects,
      env: env,
      logger: logger,
    );
    final evaluationCase = EvaluationCase(
      beacons,
      forwardEdges,
      evalRepo,
      profileLookup,
      graphBuilder,
      EvaluationDraftPurger(evalRepo),
      commitmentQuery,
      commitments,
      helpOffers,
      hierarchy,
      lifecycleEffects,
      attentionIntents: attentionIntents,
      attention: attention,
      attentionExpirySweep: AttentionExpirySweepCase(
        AttentionExpiryRepository(db),
        reviewFinalization,
        attentionIntents,
        attention,
      ),
      reviewFinalization: reviewFinalization,
      env: env,
      logger: logger,
    );

    return _ChildIndependenceHarness(
      forwardCase: ForwardCase(
        forwardEdges,
        ForwardAttributionRepository(db),
        helpOffers,
        InboxRepository(db),
        CapabilityEvidenceRepository(db),
        beacons,
        UserBlockRepository(
          env,
          db,
          witnessWindow: null,
        ),
        PersonVisibilityRepository(db),
        access,
        attentionIntents: attentionIntents,
        attention: attention,
        env: env,
        logger: logger,
      ),
      helpOfferCase: HelpOfferCase(
        helpOffers,
        beacons,
        commitments,
        InboxRepository(db),
        capabilityCase,
        access,
        attentionIntents: attentionIntents,
        attention: attention,
        env: env,
        logger: logger,
      ),
      coordinationCase: CoordinationCase(
        beacons,
        helpOffers,
        CoordinationRepository(
          db,
          profileLookup,
          VoteUserFriendshipLookup(db),
          room,
        ),
        room,
        evalRepo,
        FakeUserBlockRepository(),
        commitments,
        commitmentQuery,
        hierarchy,
        attentionIntents: attentionIntents,
        attention: attention,
        guard: access,
        env: env,
        logger: logger,
      ),
      evaluationCase: evaluationCase,
    );
  }

  Future<LifecycleOutcomeShape> runGenericLifecycle({
    required String beaconId,
    required String ownerId,
    required String recipientId,
  }) async {
    final forward = await forwardCase.forward(
      senderId: ownerId,
      beaconId: beaconId,
      recipientIds: [recipientId],
    );
    _assertForwardShape(forward);

    await helpOfferCase.offerHelp(
      beaconId: beaconId,
      userId: recipientId,
      helpTypes: const ['transport'],
    );

    final accepted = await coordinationCase.acceptHelpOffer(
      beaconId: beaconId,
      offerUserId: recipientId,
      actorUserId: ownerId,
    );
    _assertAcceptShape(accepted);

    final closeReview = await evaluationCase.beaconClose(
      beaconId: beaconId,
      userId: ownerId,
      expectedRequiresReviewWindow: true,
    );
    _assertCloseReviewShape(closeReview);

    await evaluationCase.evaluationSubmit(
      beaconId: beaconId,
      evaluatorId: ownerId,
      evaluatedUserId: recipientId,
      value: BeaconEvaluationValue.pos1,
      reasonTags: const ['delivered_as_promised'],
      note: 'thanks',
      acknowledgedHelpTags: const ['transport'],
    );
    await evaluationCase.evaluationFinalize(
      beaconId: beaconId,
      userId: ownerId,
    );

    await evaluationCase.evaluationSubmit(
      beaconId: beaconId,
      evaluatorId: recipientId,
      evaluatedUserId: ownerId,
      value: BeaconEvaluationValue.pos1,
      reasonTags: const ['clear_request'],
      note: 'good request',
    );
    await evaluationCase.evaluationFinalize(
      beaconId: beaconId,
      userId: recipientId,
    );

    return LifecycleOutcomeShape(
      forwardDeliveredCount: forward.deliveredRecipientIds.length,
      forwardSkippedCount: forward.availabilitySkippedRecipientIds.length,
      acceptStatus: accepted.status,
      closeReviewStatus: closeReview.status,
      closeReviewHasClosesAt: closeReview.closesAt != null,
      finalizeStatus: BeaconStatus.closed.smallintValue,
      finalizeDidClose: true,
      finalizeTrustPairCount: 0,
    );
  }
}

void _assertForwardShape(ForwardDeliveryResult result) {
  expect(result.batchId, isNotEmpty);
  expect(result.deliveredRecipientIds, isA<List<String>>());
  expect(result.availabilitySkippedRecipientIds, isA<List<String>>());
}

void _assertAcceptShape(BeaconStatusResult result) {
  expect(result.beaconId, isNotEmpty);
  expect(result.status, isA<int>());
}

void _assertCloseReviewShape(BeaconCloseReviewResult result) {
  expect(result.id, isNotEmpty);
  expect(result.status, isA<int>());
}

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for child independence PG test';

  group('Beacon hierarchy child independence — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late _ChildIndependenceHarness harness;
    late Env env;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      env = target.databaseEnv;
      harness = _ChildIndependenceHarness.build(session.db, env);
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await _cleanupHierarchyEvents(writer);
      await _cleanupLifecycleArtifacts(writer);
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

    test(
      'nested child runs generic forward/help/close lifecycle without parent mutation or parent-owner trust drift',
      () async {
        await fixture.seedFullTopology();
        await seedPublishedHierarchyTree(writer);
        await _reseedParticipantsAfterHierarchyTree(writer);
        await _prepareChildBeacon(writer);
        await _insertStandaloneBeacon(writer);
        await _seedMutualVisibility(
          writer,
          BeaconHierarchyTopology.daveId,
          BeaconHierarchyTopology.eveId,
        );

        final parentBefore = await _beaconSnapshot(
          writer,
          BeaconHierarchyTopology.beaconB,
        );
        final aliceTrustBefore = await _trustSnapshot(
          writer,
          BeaconHierarchyTopology.aliceId,
        );
        final bobTrustBefore = await _trustSnapshot(
          writer,
          BeaconHierarchyTopology.bobId,
        );
        final aliceMrBefore = await _mrSnapshot(
          writer,
          BeaconHierarchyTopology.aliceId,
        );
        final bobMrBefore = await _mrSnapshot(
          writer,
          BeaconHierarchyTopology.bobId,
        );

        final nestedOutcome = await harness.runGenericLifecycle(
          beaconId: BeaconHierarchyTopology.beaconC,
          ownerId: BeaconHierarchyTopology.daveId,
          recipientId: BeaconHierarchyTopology.eveId,
        );

        await _resetBeaconForSecondRun(
          writer: writer,
          beaconId: _standaloneBeaconId,
          ownerId: BeaconHierarchyTopology.daveId,
        );
        final standaloneOutcome = await harness.runGenericLifecycle(
          beaconId: _standaloneBeaconId,
          ownerId: BeaconHierarchyTopology.daveId,
          recipientId: BeaconHierarchyTopology.eveId,
        );

        expect(
          nestedOutcome.toComparableMap(),
          standaloneOutcome.toComparableMap(),
          reason: 'nested child must use the same generic lifecycle result shape',
        );

        final parentAfter = await _beaconSnapshot(
          writer,
          BeaconHierarchyTopology.beaconB,
        );
        expect(parentAfter, parentBefore);

        final aliceTrustAfter = await _trustSnapshot(
          writer,
          BeaconHierarchyTopology.aliceId,
        );
        final bobTrustAfter = await _trustSnapshot(
          writer,
          BeaconHierarchyTopology.bobId,
        );
        expect(aliceTrustAfter, aliceTrustBefore);
        expect(bobTrustAfter, bobTrustBefore);

        expect(
          await _mrSnapshot(writer, BeaconHierarchyTopology.aliceId),
          aliceMrBefore,
        );
        expect(
          await _mrSnapshot(writer, BeaconHierarchyTopology.bobId),
          bobMrBefore,
        );

        final childRow = await _beaconSnapshot(
          writer,
          BeaconHierarchyTopology.beaconC,
        );
        expect(childRow['parent_beacon_id'], BeaconHierarchyTopology.beaconB);
        expect(childRow['status'], BeaconStatus.closed.smallintValue);
      },
      skip: skipReason,
    );

    test(
      'parent can close while nested child stays open with unchanged admission',
      () async {
        await fixture.seedFullTopology();
        await seedPublishedHierarchyTree(writer);
        await _reseedParticipantsAfterHierarchyTree(writer);
        await _prepareChildBeacon(writer);
        await _prepareParentBeacon(writer);

        final childBefore = await _beaconSnapshot(
          writer,
          BeaconHierarchyTopology.beaconC,
        );
        final carolAdmissionBefore = await _participantSnapshot(
          writer,
          beaconId: BeaconHierarchyTopology.beaconC,
          userId: BeaconHierarchyTopology.carolId,
        );

        final parentClose = await harness.evaluationCase.beaconClose(
          beaconId: BeaconHierarchyTopology.beaconB,
          userId: BeaconHierarchyTopology.bobId,
          expectedRequiresReviewWindow: false,
        );
        expect(parentClose.status, BeaconStatus.closed.smallintValue);

        final childAfter = await _beaconSnapshot(
          writer,
          BeaconHierarchyTopology.beaconC,
        );
        expect(childAfter['status'], childBefore['status']);
        expect(childAfter['updated_at'], childBefore['updated_at']);

        final carolAdmissionAfter = await _participantSnapshot(
          writer,
          beaconId: BeaconHierarchyTopology.beaconC,
          userId: BeaconHierarchyTopology.carolId,
        );
        expect(carolAdmissionAfter, carolAdmissionBefore);
      },
      skip: skipReason,
    );
  });
}

Future<void> _reseedParticipantsAfterHierarchyTree(Connection writer) async {
  for (final row in <(String, String, String, int)>[
    (
      'PhierbobB01',
      BeaconHierarchyTopology.beaconB,
      BeaconHierarchyTopology.bobId,
      RoomAccessBits.admitted,
    ),
    (
      'PhiercarolC01',
      BeaconHierarchyTopology.beaconC,
      BeaconHierarchyTopology.carolId,
      RoomAccessBits.admitted,
    ),
    (
      'PhieraliceA01',
      BeaconHierarchyTopology.beaconA,
      BeaconHierarchyTopology.aliceId,
      RoomAccessBits.admitted,
    ),
  ]) {
    await writer.execute(
      Sql.named(r'''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  @id, @beaconId, @userId, 0, 0, @roomAccess,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET room_access = EXCLUDED.room_access
'''),
      parameters: {
        'id': row.$1,
        'beaconId': row.$2,
        'userId': row.$3,
        'roomAccess': row.$4,
      },
    );
  }
}

Future<void> _prepareParentBeacon(Connection writer) async {
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_help_offer WHERE beacon_id = @id
'''),
    parameters: {'id': BeaconHierarchyTopology.beaconB},
  );
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_forward_edge WHERE beacon_id = @id
'''),
    parameters: {'id': BeaconHierarchyTopology.beaconB},
  );
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_commitment_event WHERE beacon_id = @id
'''),
    parameters: {'id': BeaconHierarchyTopology.beaconB},
  );
  await writer.execute(
    Sql.named(r'''
UPDATE public.beacon SET status = @status WHERE id = @id
'''),
    parameters: {
      'id': BeaconHierarchyTopology.beaconB,
      'status': BeaconStatus.open.smallintValue,
    },
  );
}

Future<void> _prepareChildBeacon(Connection writer) async {
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_help_offer WHERE beacon_id = @id
'''),
    parameters: {'id': BeaconHierarchyTopology.beaconC},
  );
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_forward_edge WHERE beacon_id = @id
'''),
    parameters: {'id': BeaconHierarchyTopology.beaconC},
  );
  await writer.execute(
    Sql.named(r'''
UPDATE public.beacon SET status = @status WHERE id = @id
'''),
    parameters: {
      'id': BeaconHierarchyTopology.beaconC,
      'status': BeaconStatus.open.smallintValue,
    },
  );
}

Future<void> _insertStandaloneBeacon(Connection writer) async {
  await writer.execute(
    Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, published_at, created_at, updated_at
) VALUES (
  @id, @ownerId, 'Standalone compare', '', @status,
  '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET
  user_id = EXCLUDED.user_id,
  status = EXCLUDED.status,
  parent_beacon_id = NULL
'''),
    parameters: {
      'id': _standaloneBeaconId,
      'ownerId': BeaconHierarchyTopology.daveId,
      'status': BeaconStatus.open.smallintValue,
    },
  );
}

Future<void> _resetBeaconForSecondRun({
  required Connection writer,
  required String beaconId,
  required String ownerId,
}) async {
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.trust_evidence_event WHERE request_id = @id
'''),
    parameters: {'id': beaconId},
  );
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_evaluation_ack_tag WHERE beacon_id = @id
'''),
    parameters: {'id': beaconId},
  );
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_evaluation WHERE beacon_id = @id
'''),
    parameters: {'id': beaconId},
  );
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_evaluation_participant WHERE beacon_id = @id
'''),
    parameters: {'id': beaconId},
  );
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_evaluation_visibility WHERE beacon_id = @id
'''),
    parameters: {'id': beaconId},
  );
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_review_status WHERE beacon_id = @id
'''),
    parameters: {'id': beaconId},
  );
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_review_window WHERE beacon_id = @id
'''),
    parameters: {'id': beaconId},
  );
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_commitment_event WHERE beacon_id = @id
'''),
    parameters: {'id': beaconId},
  );
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_help_offer WHERE beacon_id = @id
'''),
    parameters: {'id': beaconId},
  );
  await writer.execute(
    Sql.named(r'''
DELETE FROM public.beacon_forward_edge WHERE beacon_id = @id
'''),
    parameters: {'id': beaconId},
  );
  await writer.execute(
    Sql.named(r'''
UPDATE public.beacon
SET status = @status, updated_at = '2026-01-08T00:00:00Z'
WHERE id = @id
'''),
    parameters: {
      'id': beaconId,
      'status': BeaconStatus.open.smallintValue,
    },
  );
}

Future<void> _seedMutualVisibility(
  Connection writer,
  String leftId,
  String rightId,
) async {
  for (final edge in [(leftId, rightId), (rightId, leftId)]) {
    await writer.execute(
      Sql.named(r'''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES (@subject, @object, 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
'''),
      parameters: {'subject': edge.$1, 'object': edge.$2},
    );
  }
}

Future<Map<String, Object?>> _beaconSnapshot(
  Connection writer,
  String beaconId,
) async {
  final row = await writer.execute(
    Sql.named(r'''
SELECT
  status,
  updated_at::text,
  parent_beacon_id,
  (SELECT status FROM public.beacon_review_window WHERE beacon_id = @id LIMIT 1),
  (SELECT closes_at::text FROM public.beacon_review_window WHERE beacon_id = @id LIMIT 1)
FROM public.beacon
WHERE id = @id
'''),
    parameters: {'id': beaconId},
  );
  expect(row, hasLength(1));
  return {
    'status': row.single[0],
    'updated_at': row.single[1],
    'parent_beacon_id': row.single[2],
    'review_window_status': row.single[3],
    'review_window_closes_at': row.single[4],
  };
}

Future<Map<String, Object?>> _participantSnapshot(
  Connection writer, {
  required String beaconId,
  required String userId,
}) async {
  final row = await writer.execute(
    Sql.named(r'''
SELECT room_access, status
FROM public.beacon_participant
WHERE beacon_id = @beaconId AND user_id = @userId
'''),
    parameters: {'beaconId': beaconId, 'userId': userId},
  );
  expect(row, hasLength(1));
  return {'room_access': row.single[0], 'status': row.single[1]};
}

Future<List<Map<String, Object?>>> _trustSnapshot(
  Connection writer,
  String userId,
) async {
  final edgeRows = await writer.execute(
    Sql.named(r'''
SELECT subject, object, s_good, prev_sent_weight, updated_at::text
FROM public.user_trust_edge
WHERE subject = @userId OR object = @userId
ORDER BY subject, object
'''),
    parameters: {'userId': userId},
  );
  final sourceRows = await writer.execute(
    Sql.named(r'''
SELECT trust_context, subject, object, s_good, updated_at::text
FROM public.user_trust_source_edge
WHERE subject = @userId OR object = @userId
ORDER BY trust_context, subject, object
'''),
    parameters: {'userId': userId},
  );
  final evidenceRows = await writer.execute(
    Sql.named(r'''
SELECT trust_context, subject_user_id, object_user_id, bin, count::text
FROM public.trust_evidence_event
WHERE subject_user_id = @userId OR object_user_id = @userId
ORDER BY trust_context, subject_user_id, object_user_id, bin
'''),
    parameters: {'userId': userId},
  );
  return [
    for (final row in edgeRows)
      {
        'kind': 'edge',
        'subject': row[0],
        'object': row[1],
        's_good': row[2],
        'prev_sent_weight': row[3],
        'updated_at': row[4],
      },
    for (final row in sourceRows)
      {
        'kind': 'source',
        'trust_context': row[0],
        'subject': row[1],
        'object': row[2],
        's_good': row[3],
        'updated_at': row[4],
      },
    for (final row in evidenceRows)
      {
        'kind': 'evidence',
        'trust_context': row[0],
        'subject_user_id': row[1],
        'object_user_id': row[2],
        'bin': row[3],
        'count': row[4],
      },
  ];
}

Future<List<Map<String, Object?>>> _mrSnapshot(
  Connection writer,
  String userId,
) async {
  final rows = await writer.execute(
    Sql.named(r'''
SELECT
  CASE WHEN ms.src = @userId THEN ms.dst::text ELSE ms.src::text END AS peer_id,
  CASE WHEN ms.src = @userId THEN ms.score_value_of_dst
       ELSE ms.score_value_of_src END::text AS fwd,
  CASE WHEN ms.src = @userId THEN ms.score_value_of_src
       ELSE ms.score_value_of_dst END::text AS rev
FROM mr_mutual_scores(@userId, '') ms
WHERE ms.src = @userId OR ms.dst = @userId
ORDER BY peer_id
'''),
    parameters: {'userId': userId},
  );
  return [
    for (final row in rows)
      {'peer_id': row[0], 'fwd': row[1], 'rev': row[2]},
  ];
}

Future<void> _cleanupHierarchyEvents(Connection writer) async {
  await writer.execute(
    "DELETE FROM public.beacon_hierarchy_deliveries "
    "WHERE target_beacon_id LIKE 'Bhier%' "
    "OR event_id IN ("
    "SELECT id FROM public.beacon_hierarchy_events "
    "WHERE source_beacon_id LIKE 'Bhier%'"
    ")",
  );
  await writer.execute(
    "DELETE FROM public.beacon_hierarchy_events "
    "WHERE source_beacon_id LIKE 'Bhier%'",
  );
}

Future<void> _cleanupLifecycleArtifacts(Connection writer) async {
  const ids = [
    BeaconHierarchyTopology.beaconC,
    BeaconHierarchyTopology.beaconB,
    _standaloneBeaconId,
  ];
  for (final id in ids) {
    await writer.execute(
      Sql.named(
        "DELETE FROM public.trust_evidence_event WHERE request_id = @id",
      ),
      parameters: {'id': id},
    );
    await writer.execute(
      Sql.named(
        "DELETE FROM public.beacon_evaluation_ack_tag WHERE beacon_id = @id",
      ),
      parameters: {'id': id},
    );
    await writer.execute(
      Sql.named("DELETE FROM public.beacon_evaluation WHERE beacon_id = @id"),
      parameters: {'id': id},
    );
    await writer.execute(
      Sql.named(
        "DELETE FROM public.beacon_evaluation_participant WHERE beacon_id = @id",
      ),
      parameters: {'id': id},
    );
    await writer.execute(
      Sql.named(
        "DELETE FROM public.beacon_evaluation_visibility WHERE beacon_id = @id",
      ),
      parameters: {'id': id},
    );
    await writer.execute(
      Sql.named(
        "DELETE FROM public.beacon_review_status WHERE beacon_id = @id",
      ),
      parameters: {'id': id},
    );
    await writer.execute(
      Sql.named(
        "DELETE FROM public.beacon_review_window WHERE beacon_id = @id",
      ),
      parameters: {'id': id},
    );
    await writer.execute(
      Sql.named(
        "DELETE FROM public.beacon_commitment_event WHERE beacon_id = @id",
      ),
      parameters: {'id': id},
    );
  }
}

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
