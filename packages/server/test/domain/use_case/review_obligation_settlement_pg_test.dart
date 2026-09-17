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
  AttentionSystemSettlementRepository systemSettlement,
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
