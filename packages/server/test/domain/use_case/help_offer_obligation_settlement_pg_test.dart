@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_expiry_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
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
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/data/repository/trust_evidence_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/use_case/attention_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/attention_settlement_case.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_draft_purger.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_participant_graph_builder.dart';
import 'package:tentura_server/domain/use_case/evaluation/review_finalization_case.dart';
import 'package:tentura_server/domain/use_case/evaluation_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

const _beaconId = 'Bhoblgbcn01';
const _authorId = 'Uhoblgauth1';
const _helperId = 'Uhoblghelp1';
const _helper2Id = 'Uhoblghelp2';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HELP_OFFER_OBLIGATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_help_obl',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('help-offer obligation settlement', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository attentionQuery;
    late _Harness harness;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      attentionQuery = AttentionRepository(database);
      harness = _Harness.build(database, target.databaseEnv);
    });

    setUp(() async {
      if (skipReason != false) return;
      await _resetFixture(writer);
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<int> needsYou(String accountId) async =>
        (await attentionQuery.surfaceSummary(accountId: accountId))
            .needsYouTotal;

    test('helper withdrawal drops the author obligation count', () async {
      await harness.helpOfferCase.offerHelp(
        beaconId: _beaconId,
        userId: _helperId,
      );
      expect(
        await needsYou(_authorId),
        1,
        reason: 'the offer must raise exactly one author obligation',
      );

      await harness.helpOfferCase.withdraw(
        beaconId: _beaconId,
        userId: _helperId,
        withdrawReason: 'timing',
      );

      expect(
        await needsYou(_authorId),
        0,
        reason: 'a withdrawn offer leaves nothing for the author to answer',
      );
      expect(await _helpOfferSettlementKind(writer, _helperId), 'superseded');
    }, skip: skipReason);

    test('withdrawal settles only the withdrawing helper', () async {
      await harness.helpOfferCase.offerHelp(
        beaconId: _beaconId,
        userId: _helperId,
      );
      await harness.helpOfferCase.offerHelp(
        beaconId: _beaconId,
        userId: _helper2Id,
      );
      expect(await needsYou(_authorId), 2);

      await harness.helpOfferCase.withdraw(
        beaconId: _beaconId,
        userId: _helperId,
        withdrawReason: 'timing',
      );

      expect(await needsYou(_authorId), 1);
      expect(await _helpOfferSettlementKind(writer, _helperId), 'superseded');
      expect(await _helpOfferSettlementKind(writer, _helper2Id), isNull);
    }, skip: skipReason);

    test('closing the request drops every unanswered offer obligation',
        () async {
      await harness.helpOfferCase.offerHelp(
        beaconId: _beaconId,
        userId: _helperId,
      );
      await harness.helpOfferCase.offerHelp(
        beaconId: _beaconId,
        userId: _helper2Id,
      );
      expect(await needsYou(_authorId), 2);

      await harness.evaluationCase.beaconClose(
        beaconId: _beaconId,
        userId: _authorId,
        expectedRequiresReviewWindow: false,
      );

      expect(
        await needsYou(_authorId),
        0,
        reason: 'a closed Request cannot still owe an answer to an offer',
      );
      expect(await _helpOfferSettlementKind(writer, _helperId), 'superseded');
      expect(await _helpOfferSettlementKind(writer, _helper2Id), 'superseded');
    }, skip: skipReason);

    test('removing an admitted offerer drops a still-live author obligation',
        () async {
      await harness.helpOfferCase.offerHelp(
        beaconId: _beaconId,
        userId: _helperId,
      );
      await harness.coordinationCase.acceptHelpOffer(
        beaconId: _beaconId,
        offerUserId: _helperId,
        actorUserId: _authorId,
      );
      // Re-open the obligation to model a receipt that outlived admission
      // (the state P1 is about: a terminal path must settle it regardless).
      await writer.execute('''
UPDATE public.notification_outbox AS outbox
SET settlement_kind = NULL, settled_at = NULL
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND occ.event_type = 'helpOfferSubmitted'
  AND outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
''');
      expect(await needsYou(_authorId), 1);

      await harness.coordinationCase.removeFromRoom(
        beaconId: _beaconId,
        offerUserId: _helperId,
        actorUserId: _authorId,
        reason: 'no longer needed',
      );

      expect(await needsYou(_authorId), 0);
      expect(await _helpOfferSettlementKind(writer, _helperId), 'superseded');
    }, skip: skipReason);

    test('releasing an admitted offerer drops a still-live author obligation',
        () async {
      await harness.helpOfferCase.offerHelp(
        beaconId: _beaconId,
        userId: _helperId,
      );
      await harness.coordinationCase.acceptHelpOffer(
        beaconId: _beaconId,
        offerUserId: _helperId,
        actorUserId: _authorId,
      );
      // Same belt as the removeFromRoom case: model a receipt that outlived
      // admission, so the terminal path under test is the one that must
      // settle it. `releaseCommitment` is the second `offerRemoved` producer.
      await writer.execute('''
UPDATE public.notification_outbox AS outbox
SET settlement_kind = NULL, settled_at = NULL
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND occ.event_type = 'helpOfferSubmitted'
  AND outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
''');
      expect(await needsYou(_authorId), 1);

      await harness.coordinationCase.releaseCommitment(
        beaconId: _beaconId,
        offerUserId: _helperId,
        authorUserId: _authorId,
        reason: 'scope changed',
      );

      expect(
        await needsYou(_authorId),
        0,
        reason: 'releasing the commitment ends the author obligation too',
      );
      expect(await _helpOfferSettlementKind(writer, _helperId), 'superseded');
    }, skip: skipReason);

    test('generic user settlement refuses a help-offer obligation', () async {
      await harness.helpOfferCase.offerHelp(
        beaconId: _beaconId,
        userId: _helperId,
      );
      expect(await needsYou(_authorId), 1);

      final receiptId = await _helpOfferReceiptId(writer, _helperId);
      expect(receiptId, isNotNull);

      final settlementCase = AttentionSettlementCase(
        AttentionSettlementRepository(database),
        env: target.databaseEnv,
        logger: Logger('HelpOfferObligationSettlementPgTest'),
      );

      // Owner decision C: nothing in the product can be honestly resolved by
      // acknowledgment, so the generic path must refuse at the use case.
      await expectLater(
        settlementCase.settle(
          accountId: _authorId,
          receiptId: receiptId!,
          kind: AttentionSettlementKind.resolved,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await _helpOfferSettlementKind(writer, _helperId), isNull);

      // Second layer: the repository statement refuses it even when reached
      // directly, exactly as it already refuses `reviewOpened`.
      final updated = await AttentionSettlementRepository(database).settle(
        accountId: _authorId,
        receiptId: receiptId,
        kind: AttentionSettlementKind.resolved,
      );
      expect(updated, 0, reason: 'the settle statement must match no row');
      expect(await _helpOfferSettlementKind(writer, _helperId), isNull);
      expect(await needsYou(_authorId), 1);
    }, skip: skipReason);
  }, skip: skipReason);
}

Future<String?> _helpOfferReceiptId(
  Connection writer,
  String offererId,
) async {
  final rows = await writer.execute('''
SELECT outbox.id
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE occ.event_type = 'helpOfferSubmitted'
  AND outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND outbox.target_entity_id = '$offererId'
ORDER BY outbox.created_at DESC
LIMIT 1
''');
  if (rows.isEmpty) return null;
  return rows.single[0] as String?;
}

Future<String?> _helpOfferSettlementKind(
  Connection writer,
  String offererId,
) async {
  final rows = await writer.execute('''
SELECT outbox.settlement_kind
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE occ.event_type = 'helpOfferSubmitted'
  AND outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND outbox.target_entity_id = '$offererId'
ORDER BY outbox.created_at DESC
LIMIT 1
''');
  if (rows.isEmpty) return null;
  return rows.single[0] as String?;
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_authorId, _helperId, _helper2Id]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'key-$id')
''');
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (
  '$_beaconId', '$_authorId', 'Obligation beacon', 'desc',
  ${BeaconStatus.open.smallintValue}
)
''');
}

final class _Harness {
  const _Harness({
    required this.helpOfferCase,
    required this.coordinationCase,
    required this.evaluationCase,
  });

  final HelpOfferCase helpOfferCase;
  final CoordinationCase coordinationCase;
  final EvaluationCase evaluationCase;

  static _Harness build(TenturaDb db, Env env) {
    final logger = Logger('HelpOfferObligationSettlementPgTest');
    final unitOfWork = MutatingUnitOfWork(db);
    final dispatch = AttentionDispatchRepository(db, logger);
    final attention = TransactionalAttentionCase(unitOfWork, dispatch);
    final systemSettlement = AttentionSystemSettlementRepository(db);
    final room = BeaconRoomRepository(db);
    final helpOffers = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final beacons = BeaconRepository(db);
    final access = BeaconAccessRepository(db);
    final hierarchy = BeaconHierarchyRepository(db);
    final lifecycleEffects = BeaconLifecycleEffectsCase(
      BeaconHierarchyOutboxRepository(db),
      env: env,
      logger: logger,
    );
    final attentionIntents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(room, db, helpOffers, commitments),
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
    final commitmentQuery = CommitmentQueryCase(
      commitments,
      helpOffers,
      env: env,
      logger: logger,
    );
    final evalRepo = EvaluationRepository(db);
    final forwardEdges = ForwardEdgeRepository(db);
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
      systemSettlement,
      env: env,
      logger: logger,
    );
    return _Harness(
      helpOfferCase: HelpOfferCase(
        helpOffers,
        beacons,
        commitments,
        InboxRepository(db),
        CapabilityCase(
          PersonCapabilityEventRepository(db),
          env: env,
          logger: logger,
        ),
        FakeBeaconAccessGuard(),
        roomRepository: room,
        attentionIntents: attentionIntents,
        attention: attention,
        attentionSystemSettlement: systemSettlement,
        env: env,
        logger: logger,
      ),
      coordinationCase: CoordinationCase(
        beacons,
        helpOffers,
        CoordinationRepository(
          db,
          DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
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
        attentionSystemSettlement: systemSettlement,
        guard: FakeBeaconAccessGuard(),
        env: env,
        logger: logger,
      ),
      evaluationCase: EvaluationCase(
        beacons,
        forwardEdges,
        evalRepo,
        DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
        EvaluationParticipantGraphBuilder(
          commitments,
          helpOffers,
          forwardEdges,
          _StubUserRepository(),
        ),
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
        attentionSystemSettlement: systemSettlement,
        reviewFinalization: reviewFinalization,
        env: env,
        logger: logger,
      ),
    );
  }
}

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _StubUserRepository extends Fake implements UserRepositoryPort {
  @override
  Future<UserEntity> getById(String id) async =>
      UserEntity(id: id, displayName: id);
}
