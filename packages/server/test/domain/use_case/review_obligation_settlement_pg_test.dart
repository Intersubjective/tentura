@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_expiry_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/evaluation_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/attention_expiry_repository_port.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/use_case/attention_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/attention_settlement_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_draft_purger.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_participant_graph_builder.dart';
import 'package:tentura_server/domain/use_case/evaluation/review_finalization_case.dart';
import 'package:tentura_server/domain/use_case/evaluation_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/review_finalization_test_support.dart';

const _beaconId = 'Broblgbcn001';
const _authorId = 'Uroblgauth01';
const _reviewer1 = 'Uroblgrevw01';
const _reviewer2 = 'Uroblgrevw02';
const _subjectId = 'Uroblgsubj01';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('review obligation system settlement', () {
    late Connection writer;
    late TenturaDb database;
    late AttentionDispatchRepository dispatch;
    late AttentionIntentCase intents;
    late AttentionSystemSettlementRepository systemSettlement;
    late ReviewFinalizationCase finalizationCase;
    late EvaluationRepository evalRepo;
    late EvaluationCase evaluationCase;
    late AttentionExpirySweepCase expirySweep;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      database = TenturaDb(target.databaseEnv);
      final logger = Logger('ReviewObligationSettlementPgTest');
      final unitOfWork = MutatingUnitOfWork(database);
      dispatch = AttentionDispatchRepository(database, logger);
      final room = BeaconRoomRepository(database);
      final helpOffers = HelpOfferRepository(database);
      final commitments = CommitmentRepository(database);
      intents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          room,
          database,
          helpOffers,
          commitments,
        ),
        UserRepository(
          target.databaseEnv,
          database,
          _NoopTrustEvidenceRepository(),
          _NoopInviteGenealogyRepository(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(database),
        FakeUserBlockRepository(),
      );
      systemSettlement = AttentionSystemSettlementRepository(database);
      evalRepo = EvaluationRepository(database);
      finalizationCase = ReviewFinalizationCase(
        unitOfWork,
        evalRepo,
        FakeForwardEdges(),
        FakeAttribution(),
        FakeHelpOffers(),
        RecordingTrustEvidence(),
        NoopCapabilityEvidence(),
        FakeBeaconHierarchyRepository(),
        buildLifecycleEffectsCase(),
        systemSettlement,
        env: target.databaseEnv,
        logger: logger,
      );
      expirySweep = AttentionExpirySweepCase(
        AttentionExpiryRepository(database),
        finalizationCase,
        intents,
        TransactionalAttentionCase(unitOfWork, dispatch),
      );
      evaluationCase = _buildEvaluationCase(
        database,
        target.databaseEnv,
        logger,
        evalRepo,
        intents,
        dispatch,
        unitOfWork,
        finalizationCase,
        systemSettlement,
      );
    });

    setUp(() async => _resetFixture(writer));

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test('finalized package settles receipt as resolved', () async {
      await _dispatchReviewOpened(dispatch, intents);
      await evalRepo.submitEvaluationAtomic(
        beaconId: _beaconId,
        evaluatorId: _reviewer1,
        evaluatedUserId: _subjectId,
        value: BeaconEvaluationValue.pos1,
        reasonTags: const ['quality'],
        note: 'ok',
        ackTags: const [],
      );
      await evalRepo.setReviewUserStatus(
        beaconId: _beaconId,
        userId: _reviewer1,
        status: 2,
      );

      await finalizationCase.closeAndFinalize(
        _beaconId,
        reason: BeaconLifecycleChangeReason.reviewExpired,
        actorUserId: _authorId,
      );

      expect(
        await _settlementKind(writer, _reviewer1),
        'resolved',
      );
    }, skip: skipReason);

    test('submitted but unsent package settles as expired not resolved', () async {
      await _dispatchReviewOpened(dispatch, intents);
      await evalRepo.submitEvaluationAtomic(
        beaconId: _beaconId,
        evaluatorId: _reviewer1,
        evaluatedUserId: _subjectId,
        value: BeaconEvaluationValue.pos1,
        reasonTags: const ['quality'],
        note: 'submitted only',
        ackTags: const [],
      );
      await evalRepo.setReviewUserStatus(
        beaconId: _beaconId,
        userId: _reviewer1,
        status: 1,
      );

      await finalizationCase.closeAndFinalize(
        _beaconId,
        reason: BeaconLifecycleChangeReason.reviewExpired,
        actorUserId: _authorId,
      );

      expect(await _settlementKind(writer, _reviewer1), 'expired');
      expect(await _settlementKind(writer, _reviewer1), isNot('resolved'));
    }, skip: skipReason);

    test('an expired sweep explains the obligation it ended, exactly once',
        () async {
      await _dispatchReviewOpened(dispatch, intents);
      // The window is already due: the sweeper, not a person, ends this.
      await writer.execute('''
UPDATE public.beacon_review_window
SET closes_at = now() - interval '1 hour'
WHERE beacon_id = '$_beaconId'
''');

      expect(await expirySweep.runDue(), 1);
      // The sweeper can run more than once; the second pass must add nothing.
      expect(await expirySweep.runDue(), 0);

      expect(await _settlementKind(writer, _reviewer1), 'expired');
      expect(await _settlementKind(writer, _reviewer2), 'expired');

      // §5: the count fell without either reviewer acting, so each is owed
      // exactly one explanation — and only one, however often we sweep.
      expect(await _obligationEndedOccurrenceCount(writer), 1);
      expect(await _obligationEndedReceiptCount(writer, _reviewer1), 1);
      expect(await _obligationEndedReceiptCount(writer, _reviewer2), 1);
      expect(
        await _obligationEndedBody(writer),
        contains('review window closed'),
      );
    }, skip: skipReason);

    test('a reviewer who sent their package gets no expiry explanation',
        () async {
      await _dispatchReviewOpened(dispatch, intents);
      await evalRepo.submitEvaluationAtomic(
        beaconId: _beaconId,
        evaluatorId: _reviewer1,
        evaluatedUserId: _subjectId,
        value: BeaconEvaluationValue.pos1,
        reasonTags: const ['quality'],
        note: 'sent',
        ackTags: const [],
      );
      await evalRepo.setReviewUserStatus(
        beaconId: _beaconId,
        userId: _reviewer1,
        status: 2,
      );
      await writer.execute('''
UPDATE public.beacon_review_window
SET closes_at = now() - interval '1 hour'
WHERE beacon_id = '$_beaconId'
''');

      expect(await expirySweep.runDue(), 1);

      expect(await _settlementKind(writer, _reviewer1), 'resolved');
      expect(await _settlementKind(writer, _reviewer2), 'expired');
      expect(
        await _obligationEndedReceiptCount(writer, _reviewer1),
        0,
        reason: 'their obligation ended by their own act; nothing to explain',
      );
      expect(await _obligationEndedReceiptCount(writer, _reviewer2), 1);
    }, skip: skipReason);

    test('reopen from review supersedes reviewOpened obligations', () async {
      await _dispatchReviewOpened(dispatch, intents);
      await evaluationCase.reopenFromReview(
        beaconId: _beaconId,
        userId: _authorId,
      );

      expect(await _settlementKind(writer, _reviewer1), 'superseded');
      expect(await _settlementKind(writer, _reviewer2), 'superseded');
    }, skip: skipReason);

    test('one reviewer finalize leaves peer obligation live until window close', () async {
      await _dispatchReviewOpened(dispatch, intents);
      await evalRepo.submitEvaluationAtomic(
        beaconId: _beaconId,
        evaluatorId: _reviewer1,
        evaluatedUserId: _subjectId,
        value: BeaconEvaluationValue.pos1,
        reasonTags: const ['quality'],
        note: 'r1',
        ackTags: const [],
      );
      await evalRepo.setReviewUserStatus(
        beaconId: _beaconId,
        userId: _reviewer1,
        status: 2,
      );

      expect(await _settlementKind(writer, _reviewer2), isNull);

      await finalizationCase.closeAndFinalize(
        _beaconId,
        reason: BeaconLifecycleChangeReason.reviewExpired,
        actorUserId: _authorId,
      );

      expect(await _settlementKind(writer, _reviewer1), 'resolved');
      expect(await _settlementKind(writer, _reviewer2), 'expired');
    }, skip: skipReason);

    test('evaluationFinalize settles sender receipt immediately', () async {
      await _dispatchReviewOpened(dispatch, intents);
      await evalRepo.submitEvaluationAtomic(
        beaconId: _beaconId,
        evaluatorId: _reviewer1,
        evaluatedUserId: _subjectId,
        value: BeaconEvaluationValue.pos1,
        reasonTags: const ['quality'],
        note: 'r1',
        ackTags: const [],
      );

      await evaluationCase.evaluationFinalize(
        beaconId: _beaconId,
        userId: _reviewer1,
      );

      expect(await _settlementKind(writer, _reviewer1), 'resolved');
      expect(await _settlementKind(writer, _reviewer2), isNull);
    }, skip: skipReason);

    test('package send and its settlement commit together', () async {
      await _dispatchReviewOpened(dispatch, intents);
      await evalRepo.submitEvaluationAtomic(
        beaconId: _beaconId,
        evaluatorId: _reviewer1,
        evaluatedUserId: _subjectId,
        value: BeaconEvaluationValue.pos1,
        reasonTags: const ['quality'],
        note: 'r1',
        ackTags: const [],
      );

      await evaluationCase.evaluationFinalize(
        beaconId: _beaconId,
        userId: _reviewer1,
      );

      expect(await evalRepo.getReviewUserStatus(_beaconId, _reviewer1), 2);
      expect(await _settlementKind(writer, _reviewer1), 'resolved');
    }, skip: skipReason);

    test('a failing settlement rolls the package send back with it', () async {
      await _dispatchReviewOpened(dispatch, intents);
      await evalRepo.submitEvaluationAtomic(
        beaconId: _beaconId,
        evaluatorId: _reviewer1,
        evaluatedUserId: _subjectId,
        value: BeaconEvaluationValue.pos1,
        reasonTags: const ['quality'],
        note: 'r1',
        ackTags: const [],
      );
      final failing = _buildEvaluationCase(
        database,
        target.databaseEnv,
        Logger('ReviewObligationSettlementPgTest'),
        evalRepo,
        intents,
        dispatch,
        MutatingUnitOfWork(database),
        finalizationCase,
        _FailingPackageSendSettlement(systemSettlement),
      );

      await expectLater(
        failing.evaluationFinalize(beaconId: _beaconId, userId: _reviewer1),
        throwsA(isA<StateError>()),
      );

      expect(
        await evalRepo.getReviewUserStatus(_beaconId, _reviewer1),
        isNot(2),
        reason: 'the package send must not survive a failed settlement',
      );
      expect(await _settlementKind(writer, _reviewer1), isNull);
    }, skip: skipReason);

    test('user settle of reviewOpened throws and leaves receipt live', () async {
      await _dispatchReviewOpened(dispatch, intents);
      final receiptId = await _reviewReceiptId(writer, _reviewer1);
      expect(receiptId, isNotNull);

      final settlementCase = AttentionSettlementCase(
        AttentionSettlementRepository(database),
        env: target.databaseEnv,
        logger: Logger('ReviewObligationSettlementPgTest'),
      );

      expect(
        () => settlementCase.settle(
          accountId: _reviewer1,
          receiptId: receiptId!,
          kind: AttentionSettlementKind.resolved,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await _settlementKind(writer, _reviewer1), isNull);
    }, skip: skipReason);

    test('help-offer obligation on same beacon survives review close settlement',
        () async {
      await _dispatchReviewOpened(dispatch, intents);
      await dispatch.record(
        await intents.helpOfferSubmitted(
          beaconId: _beaconId,
          helpOffererId: _reviewer2,
          authorId: _authorId,
          sourceEventKey: 'help_offer:Broblgfixture',
        ),
      );

      await finalizationCase.closeAndFinalize(
        _beaconId,
        reason: BeaconLifecycleChangeReason.reviewExpired,
        actorUserId: _authorId,
      );

      expect(await _settlementKind(writer, _reviewer1), 'expired');
      final helpRows = await writer.execute('''
SELECT settlement_kind
FROM public.notification_outbox outbox
JOIN public.attention_occurrence occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND occ.event_type = 'helpOfferSubmitted'
''');
      expect(helpRows.single[0], isNull);
    }, skip: skipReason);

    test('settleAuthorHelpOfferSubmitted resolves author help-offer obligation',
        () async {
      await dispatch.record(
        await intents.helpOfferSubmitted(
          beaconId: _beaconId,
          helpOffererId: _reviewer2,
          authorId: _authorId,
          sourceEventKey: 'help_offer:admit',
        ),
      );

      final updated = await systemSettlement.settleAuthorHelpOfferSubmitted(
        beaconId: _beaconId,
        authorAccountId: _authorId,
        helpOffererUserId: _reviewer2,
      );
      expect(updated, 1);

      final helpRows = await writer.execute('''
SELECT settlement_kind, seen_at
FROM public.notification_outbox outbox
JOIN public.attention_occurrence occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND occ.event_type = 'helpOfferSubmitted'
''');
      expect(helpRows.single[0], 'resolved');
      expect(helpRows.single[1], isNotNull);
    }, skip: skipReason);

    test(
        'settleAuthorHelpOfferSubmitted preserves prior seen_at and leaves other offerers',
        () async {
      await dispatch.record(
        await intents.helpOfferSubmitted(
          beaconId: _beaconId,
          helpOffererId: _reviewer1,
          authorId: _authorId,
          sourceEventKey: 'help_offer:other',
        ),
      );
      await dispatch.record(
        await intents.helpOfferSubmitted(
          beaconId: _beaconId,
          helpOffererId: _reviewer2,
          authorId: _authorId,
          sourceEventKey: 'help_offer:target',
        ),
      );
      await writer.execute('''
UPDATE public.notification_outbox AS outbox
SET seen_at = '2026-07-17T10:00:00Z'::timestamptz
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND occ.event_type = 'helpOfferSubmitted'
  AND outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND outbox.target_entity_id = '$_reviewer2'
''');

      final updated = await systemSettlement.settleAuthorHelpOfferSubmitted(
        beaconId: _beaconId,
        authorAccountId: _authorId,
        helpOffererUserId: _reviewer2,
      );
      expect(updated, 1);

      final targetRows = await writer.execute('''
SELECT settlement_kind, seen_at
FROM public.notification_outbox outbox
JOIN public.attention_occurrence occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND outbox.target_entity_id = '$_reviewer2'
  AND occ.event_type = 'helpOfferSubmitted'
''');
      expect(targetRows.single[0], 'resolved');
      expect(
        DateTime.parse(targetRows.single[1]!.toString()).toUtc(),
        DateTime.utc(2026, 7, 17, 10),
      );

      final otherRows = await writer.execute('''
SELECT settlement_kind, seen_at
FROM public.notification_outbox outbox
JOIN public.attention_occurrence occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND outbox.target_entity_id = '$_reviewer1'
  AND occ.event_type = 'helpOfferSubmitted'
''');
      expect(otherRows.single[0], isNull);
      expect(otherRows.single[1], isNull);
    }, skip: skipReason);

    test(
        'settleAuthorHelpOfferSubmitted marks already-settled unseen receipt seen',
        () async {
      await dispatch.record(
        await intents.helpOfferSubmitted(
          beaconId: _beaconId,
          helpOffererId: _reviewer2,
          authorId: _authorId,
          sourceEventKey: 'help_offer:presettle',
        ),
      );
      await writer.execute('''
UPDATE public.notification_outbox AS outbox
SET
  settlement_kind = 'resolved',
  settled_at = '2026-07-17T09:00:00Z'::timestamptz
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND occ.event_type = 'helpOfferSubmitted'
  AND outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND outbox.target_entity_id = '$_reviewer2'
''');

      final updated = await systemSettlement.settleAuthorHelpOfferSubmitted(
        beaconId: _beaconId,
        authorAccountId: _authorId,
        helpOffererUserId: _reviewer2,
      );
      expect(updated, 1);

      final helpRows = await writer.execute('''
SELECT settlement_kind, settled_at, seen_at
FROM public.notification_outbox outbox
JOIN public.attention_occurrence occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND outbox.target_entity_id = '$_reviewer2'
  AND occ.event_type = 'helpOfferSubmitted'
''');
      expect(helpRows.single[0], 'resolved');
      expect(
        DateTime.parse(helpRows.single[1]!.toString()).toUtc(),
        DateTime.utc(2026, 7, 17, 9),
      );
      expect(helpRows.single[2], isNotNull);
    }, skip: skipReason);

    test('settlement preserves seen_at and read_at', () async {
      await _dispatchReviewOpened(dispatch, intents);
      await writer.execute('''
UPDATE public.notification_outbox
SET
  seen_at = '2026-07-17T10:00:00Z'::timestamptz,
  read_at = '2026-07-17T11:00:00Z'::timestamptz
WHERE beacon_id = '$_beaconId'
  AND account_id = '$_reviewer1'
''');

      await finalizationCase.closeAndFinalize(
        _beaconId,
        reason: BeaconLifecycleChangeReason.reviewExpired,
        actorUserId: _authorId,
      );

      final rows = await writer.execute('''
SELECT seen_at, read_at, settlement_kind
FROM public.notification_outbox
WHERE account_id = '$_reviewer1'
  AND beacon_id = '$_beaconId'
''');
      expect(rows.single[0], isNotNull);
      expect(rows.single[1], isNotNull);
      expect(rows.single[2], 'expired');
    }, skip: skipReason);
  }, skip: skipReason);
}

EvaluationCase _buildEvaluationCase(
  TenturaDb database,
  Env env,
  Logger logger,
  EvaluationRepository evalRepo,
  AttentionIntentCase intents,
  AttentionDispatchRepository dispatch,
  MutatingUnitOfWork unitOfWork,
  ReviewFinalizationCase finalizationCase,
  AttentionSystemSettlementPort systemSettlement,
) {
  final beacons = BeaconRepository(database);
  final transactional = TransactionalAttentionCase(unitOfWork, dispatch);
  final expirySweep = AttentionExpirySweepCase(
    _NoopAttentionExpiryRepository(),
    finalizationCase,
    intents,
    transactional,
  );
  return EvaluationCase(
    beacons,
    FakeForwardEdges(),
    evalRepo,
    _StubUserProfileBatchLookup(),
    EvaluationParticipantGraphBuilder(
      CommitmentRepository(database),
      HelpOfferRepository(database),
      FakeForwardEdges(),
      _StubUserRepository(),
    ),
    EvaluationDraftPurger(evalRepo),
    CommitmentQueryCase(
      CommitmentRepository(database),
      HelpOfferRepository(database),
      env: env,
      logger: logger,
    ),
    CommitmentRepository(database),
    HelpOfferRepository(database),
    FakeBeaconHierarchyRepository(),
    buildLifecycleEffectsCase(),
    attentionIntents: intents,
    attention: transactional,
    attentionExpirySweep: expirySweep,
    attentionSystemSettlement: systemSettlement,
    reviewFinalization: finalizationCase,
    env: env,
    logger: logger,
  );
}

Future<void> _dispatchReviewOpened(
  AttentionDispatchRepository dispatch,
  AttentionIntentCase intents,
) async {
  await dispatch.record(
    await intents.reviewOpened(
      beaconId: _beaconId,
      beaconTitle: 'Review obligation fixture',
      recipientUserIds: {_reviewer1, _reviewer2},
      actorUserId: _authorId,
      sourceEventKey: 'review_opened:Broblgfixture',
    ),
  );
}

Future<int> _obligationEndedOccurrenceCount(Connection writer) async {
  final rows = await writer.execute('''
SELECT count(*) FROM public.attention_occurrence
WHERE event_type = 'obligationEnded'
''');
  return (rows.single[0]! as int).toInt();
}

Future<int> _obligationEndedReceiptCount(
  Connection writer,
  String accountId,
) async {
  final rows = await writer.execute('''
SELECT count(*)
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE occ.event_type = 'obligationEnded'
  AND outbox.account_id = '$accountId'
''');
  return (rows.single[0]! as int).toInt();
}

Future<String> _obligationEndedBody(Connection writer) async {
  final rows = await writer.execute('''
SELECT outbox.body
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE occ.event_type = 'obligationEnded'
LIMIT 1
''');
  return rows.single[0]! as String;
}

Future<String?> _settlementKind(Connection writer, String accountId) async {
  final rows = await writer.execute('''
SELECT settlement_kind
FROM public.notification_outbox
WHERE beacon_id = '$_beaconId'
  AND account_id = '$accountId'
  AND requires_action
ORDER BY created_at DESC
LIMIT 1
''');
  if (rows.isEmpty) return null;
  return rows.single[0] as String?;
}

Future<String?> _reviewReceiptId(Connection writer, String accountId) async {
  final rows = await writer.execute('''
SELECT outbox.id
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$accountId'
  AND occ.event_type = 'reviewOpened'
  AND outbox.requires_action
  AND outbox.settlement_kind IS NULL
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
  public.beacon_evaluation_ack_tag,
  public.beacon_evaluation,
  public.beacon_evaluation_visibility,
  public.beacon_evaluation_participant,
  public.beacon_review_status,
  public.beacon_review_window,
  public.beacon,
  public."user"
CASCADE
''');

  for (final id in [_authorId, _reviewer1, _reviewer2, _subjectId]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'key-$id')
''');
  }

  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('$_beaconId', '$_authorId', 'Obligation beacon', 'desc', ${BeaconStatus.reviewOpen.smallintValue})
''');

  await writer.execute('''
INSERT INTO public.beacon_review_window (
  beacon_id, opened_at, closes_at, status, extensions_used
) VALUES (
  '$_beaconId',
  now() - interval '1 day',
  now() + interval '1 day',
  0,
  0
)
''');

  for (final (uid, role) in [
    (_authorId, EvaluationParticipantRole.author),
    (_reviewer1, EvaluationParticipantRole.committer),
    (_reviewer2, EvaluationParticipantRole.committer),
    (_subjectId, EvaluationParticipantRole.committer),
  ]) {
    await writer.execute('''
INSERT INTO public.beacon_evaluation_participant (
  beacon_id, user_id, role, contribution_summary, causal_hint
) VALUES (
  '$_beaconId', '$uid', ${role.dbValue}, 'helped', 'hint'
)
''');
    if (role != EvaluationParticipantRole.author) {
      await writer.execute('''
INSERT INTO public.beacon_evaluation_visibility (
  beacon_id, evaluator_id, participant_id
) VALUES ('$_beaconId', '$uid', '$_subjectId')
''');
      await writer.execute('''
INSERT INTO public.beacon_review_status (beacon_id, user_id, status)
VALUES ('$_beaconId', '$uid', 0)
''');
    }
  }
}

final class _NoopAttentionExpiryRepository extends Fake
    implements AttentionExpiryRepositoryPort {
  @override
  Future<List<String>> lockExpiredReviewWindowBeaconIds(DateTime now) async =>
      [];
}

/// Delegates every settlement but the package-send one, which fails: proves
/// the source mutation and the settlement share one transaction boundary.
final class _FailingPackageSendSettlement
    implements AttentionSystemSettlementPort {
  const _FailingPackageSendSettlement(this._delegate);

  final AttentionSystemSettlementPort _delegate;

  @override
  Future<int> settleReviewerObligationOnPackageSend({
    required String beaconId,
    required String reviewerAccountId,
  }) async => throw StateError('injected settlement failure');

  @override
  Future<int> settleReviewObligationsAfterWindowClose(String beaconId) =>
      _delegate.settleReviewObligationsAfterWindowClose(beaconId);

  @override
  Future<int> supersedeReviewObligationsOnReopen(String beaconId) =>
      _delegate.supersedeReviewObligationsOnReopen(beaconId);

  @override
  Future<List<String>> listExpiredReviewObligationAccountIds(
    String beaconId,
  ) => _delegate.listExpiredReviewObligationAccountIds(beaconId);

  @override
  Future<int> settleAuthorHelpOfferSubmitted({
    required String beaconId,
    required String authorAccountId,
    required String helpOffererUserId,
  }) => _delegate.settleAuthorHelpOfferSubmitted(
    beaconId: beaconId,
    authorAccountId: authorAccountId,
    helpOffererUserId: helpOffererUserId,
  );

  @override
  Future<int> supersedeAuthorHelpOfferSubmitted({
    required String beaconId,
    required String authorAccountId,
    required String helpOffererUserId,
  }) => _delegate.supersedeAuthorHelpOfferSubmitted(
    beaconId: beaconId,
    authorAccountId: authorAccountId,
    helpOffererUserId: helpOffererUserId,
  );

  @override
  Future<int> supersedeAuthorHelpOfferObligationsOnBeaconClose(
    String beaconId,
  ) => _delegate.supersedeAuthorHelpOfferObligationsOnBeaconClose(beaconId);

  @override
  Future<List<String>> listBeaconIdsWithClosedReviewWindows() =>
      _delegate.listBeaconIdsWithClosedReviewWindows();
}

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _StubUserRepository extends Fake
    implements UserRepositoryPort {
  @override
  Future<UserEntity> getById(String id) async =>
      UserEntity(id: id, displayName: id);
}

final class _StubUserProfileBatchLookup extends Fake
    implements UserProfileBatchLookup {
  @override
  Future<Map<String, String>> displayNamesForIds(Iterable<String> ids) async =>
      {for (final id in ids) id: id};
}

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
        Platform.environment['TENTURA_REVIEW_OBLIGATION_TEST_DB'] ??
        'tentura_test_review_obl_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_REVIEW_OBLIGATION_TEST_DB',
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
    } finally {
      await connection.close();
    }
  }
}
