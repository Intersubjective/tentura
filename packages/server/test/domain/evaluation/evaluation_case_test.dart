import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/attention_expiry_repository_port.dart';
import 'package:tentura_server/domain/entity/review_finalization_result.dart';
import 'package:tentura_server/domain/port/review_finalization_port.dart';
import 'package:tentura_server/domain/entity/review_close_snapshot.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/entity/evaluation/cross_beacon_evaluation_record.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/entity/gql_public/evaluation_received_result.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/attention_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_draft_purger.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_participant_graph_builder.dart';
import 'package:tentura_server/domain/use_case/evaluation_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';

import '../../support/recording_commitment_repository.dart';
import 'evaluation_graph_test_repos.dart';
import '../../support/test_attention_harness.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

class _NoopAttentionExpiryRepository extends Fake
    implements AttentionExpiryRepositoryPort {
  @override
  Future<List<String>> lockExpiredReviewWindowBeaconIds(DateTime now) async =>
      const [];
}

class MockBeaconRepository extends Mock implements BeaconRepositoryPort {}

class _StubBeaconRepository implements BeaconRepositoryPort {
  _StubBeaconRepository(this._beacon);

  final BeaconEntity _beacon;

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async =>
      _beacon;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StatusTransitionCall {
  const _StatusTransitionCall({
    required this.beaconId,
    required this.fromStatus,
    required this.toStatus,
    required this.reason,
    this.actorId,
  });

  final String beaconId;
  final BeaconStatus fromStatus;
  final BeaconStatus toStatus;
  final String reason;
  final String? actorId;

  @override
  bool operator ==(Object other) =>
      other is _StatusTransitionCall &&
      other.beaconId == beaconId &&
      other.fromStatus == fromStatus &&
      other.toStatus == toStatus &&
      other.reason == reason &&
      other.actorId == actorId;

  @override
  int get hashCode =>
      Object.hash(beaconId, fromStatus, toStatus, reason, actorId);
}

class _TransactionStubBeaconRepo implements BeaconRepositoryPort {
  _TransactionStubBeaconRepo(this.lockedBeacon, {int reviewReopenCount = 0})
    : _storedReviewReopenCount = reviewReopenCount;

  final BeaconEntity lockedBeacon;
  final statusTransitions = <_StatusTransitionCall>[];
  int _storedReviewReopenCount;

  int get storedReviewReopenCount => _storedReviewReopenCount;

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) => fn(lockedBeacon);

  @override
  Future<void> recordBeaconStatusTransition({
    required String beaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required String reason,
    String? actorId,
  }) async {
    statusTransitions.add(
      _StatusTransitionCall(
        beaconId: beaconId,
        fromStatus: fromStatus,
        toStatus: toStatus,
        reason: reason,
        actorId: actorId,
      ),
    );
  }

  @override
  Future<int> reviewReopenCount(String beaconId) async =>
      _storedReviewReopenCount;

  @override
  Future<void> incrementReviewReopenCount(String beaconId) async {
    _storedReviewReopenCount++;
  }

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async =>
      lockedBeacon;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MutableTransactionStubBeaconRepo implements BeaconRepositoryPort {
  _MutableTransactionStubBeaconRepo(this._beacon);

  final BeaconEntity Function() _beacon;

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) => fn(_beacon());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

EvaluationCase buildTestEvaluationCase({
  required BeaconRepositoryPort beaconRepo,
  required ForwardEdgeRepositoryPort forwardRepo,
  required EvaluationRepositoryPort evalRepo,
  required UserProfileBatchLookup userProfileBatchLookup,
  required EvaluationParticipantGraphBuilder graphBuilder,
  required TestAttentionHarness attention,
  required AttentionExpirySweepCase expirySweep,
  CommitmentRepositoryPort? commitmentRepo,
  HelpOfferRepositoryPort? helpOfferRepo,
  ReviewFinalizationPort? reviewFinalization,
}) {
  final commitment = commitmentRepo ?? NoOpCommitmentRepository();
  final offers = helpOfferRepo ?? EmptyGraphHelpOfferRepository();
  return EvaluationCase(
    beaconRepo,
    forwardRepo,
    evalRepo,
    userProfileBatchLookup,
    graphBuilder,
    EvaluationDraftPurger(evalRepo),
    CommitmentQueryCase(
      commitment,
      offers,
      env: Env(environment: Environment.test),
      logger: Logger('EvaluationCaseTest'),
    ),
    commitment,
    offers,
    attentionIntents: attention.intents,
    attention: attention.transactional,
    attentionExpirySweep: expirySweep,
    reviewFinalization: reviewFinalization,
    env: Env(environment: Environment.test),
    logger: Logger('EvaluationCaseTest'),
  );
}

@immutable
class _SetStatusCall {
  const _SetStatusCall(this.beaconId, this.userId, this.status);

  final String beaconId;
  final String userId;
  final int status;

  @override
  bool operator ==(Object other) =>
      other is _SetStatusCall &&
      other.beaconId == beaconId &&
      other.userId == userId &&
      other.status == status;

  @override
  int get hashCode => Object.hash(beaconId, userId, status);
}

@immutable
class _SubmitAtomicCall {
  const _SubmitAtomicCall({
    required this.beaconId,
    required this.evaluatorId,
    required this.evaluatedUserId,
    required this.value,
    required this.reasonTags,
    required this.note,
    required this.ackTags,
  });

  final String beaconId;
  final String evaluatorId;
  final String evaluatedUserId;
  final int value;
  final List<String> reasonTags;
  final String note;
  final List<String> ackTags;
}

/// Configurable fake for [EvaluationCase] unit tests.
class _FakeEvaluationRepository implements EvaluationRepositoryPort {
  _FakeEvaluationRepository();

  BeaconReviewWindowRecord? reviewWindowResult;
  int? reviewUserStatusResult;
  List<BeaconEvaluationParticipantRecord> participantsResult = [];
  List<BeaconEvaluationVisibilityRecord> visibilityResult = [];
  List<BeaconEvaluationRecord> listEvaluationsForEvaluatorResult = [];
  final List<_SetStatusCall> setReviewUserStatusCalls = [];
  final List<_SubmitAtomicCall> submitEvaluationAtomicCalls = [];
  StateError? submitEvaluationAtomicError;
  int downgradeSubmittedCalls = 0;
  int deleteScaffoldingCalls = 0;
  int insertReviewWindowCalls = 0;
  Map<String, int> reviewStatusesResult = {};
  DateTime extendReviewResult = DateTime.utc(2025, 1, 8);
  final closeReviewWindowCalls =
      <({String beaconId, String reason, String? actorUserId})>[];
  List<BeaconEvaluationRecord> listEvaluationsForEvaluatedUserResult = [];
  List<CrossBeaconEvaluationRecord> listFinalizedEvaluationsBetweenResult = [];
  BeaconEvaluationRecord? evaluationResult;
  bool mutateEvaluationOnSubmit = false;

  @override
  Future<BeaconEvaluationRecord?> getEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) async => evaluationResult;

  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluator({
    required String beaconId,
    required String evaluatorId,
  }) async => listEvaluationsForEvaluatorResult
      .where(
        (e) => e.beaconId == beaconId && e.evaluatorId == evaluatorId,
      )
      .toList();

  @override
  Future<BeaconReviewWindowRecord?> getReviewWindow(String beaconId) async =>
      reviewWindowResult;

  @override
  Future<int?> getReviewUserStatus(String beaconId, String userId) async =>
      reviewUserStatusResult;

  @override
  Future<void> insertParticipant({
    required String beaconId,
    required String userId,
    required int role,
    required String contributionSummary,
    required String causalHint,
  }) async {}

  @override
  Future<void> insertReviewStatus({
    required String beaconId,
    required String userId,
    int status = 0,
  }) async {}

  @override
  Future<void> insertReviewWindow({
    required String beaconId,
    required DateTime openedAt,
    required DateTime closesAt,
  }) async {
    insertReviewWindowCalls++;
  }

  @override
  Future<void> insertVisibility({
    required String beaconId,
    required String evaluatorId,
    required String participantId,
  }) async {}

  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluatedUser({
    required String beaconId,
    required String evaluatedUserId,
  }) async => listEvaluationsForEvaluatedUserResult
      .where(
        (e) =>
            e.beaconId == beaconId && e.evaluatedUserId == evaluatedUserId,
      )
      .toList();

  @override
  Future<List<CrossBeaconEvaluationRecord>> listFinalizedEvaluationsBetween({
    required String evaluatorId,
    required String evaluatedUserId,
  }) async =>
      listFinalizedEvaluationsBetweenResult
          .where(
            (r) =>
                r.evaluatorId == evaluatorId &&
                r.evaluatedUserId == evaluatedUserId,
          )
          .toList();

  @override
  Future<List<BeaconEvaluationParticipantRecord>> listParticipants(
    String beaconId,
  ) async => participantsResult;

  @override
  Future<List<BeaconEvaluationVisibilityRecord>> listVisibilityForEvaluator(
    String beaconId,
    String evaluatorId,
  ) async => visibilityResult;

  @override
  Future<List<BeaconEvaluationVisibilityRecord>> listAllVisibility(
    String beaconId,
  ) async => visibilityResult;

  @override
  Future<List<BeaconEvaluationRecord>> listDraftRowsForBeacon(
    String beaconId,
  ) async => [];

  @override
  Future<void> deleteEvaluationRow({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) async {}

  @override
  Future<void> finalizeSubmittedEvaluationsForBeacon(String beaconId) async {}

  @override
  Future<void> deleteDraftEvaluationsForBeacon(String beaconId) async {}

  @override
  Future<Map<String, int>> listReviewStatusesForBeacon(String beaconId) async =>
      reviewStatusesResult;

  @override
  Future<void> downgradeSubmittedReviewsToDraft(String beaconId) async {
    downgradeSubmittedCalls++;
  }

  @override
  Future<void> deleteReviewScaffoldingForBeacon(String beaconId) async {
    deleteScaffoldingCalls++;
    reviewWindowResult = null;
  }

  @override
  Future<DateTime> extendReviewWindow(String beaconId) async =>
      extendReviewResult;

  @override
  Future<ReviewCloseSnapshot?> closeReviewWindow(
    String beaconId, {
    required String reason,
    String? actorUserId,
  }) async {
    closeReviewWindowCalls.add(
      (beaconId: beaconId, reason: reason, actorUserId: actorUserId),
    );
    return ReviewCloseSnapshot(
      beaconId: beaconId,
      beaconAuthorId: actorUserId ?? 'author',
      beaconTitle: 'Test request',
      windowOpenedAt: DateTime.utc(2026, 1, 1),
      finalizedEvaluations: const [],
    );
  }

  @override
  Future<void> setReviewUserStatus({
    required String beaconId,
    required String userId,
    required int status,
  }) async {
    setReviewUserStatusCalls.add(_SetStatusCall(beaconId, userId, status));
  }

  @override
  Future<void> upsertEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required String reasonTagsCsv,
    required String note,
    int status = BeaconEvaluationRowStatus.submitted,
    EvaluationWriteResolver? resolve,
  }) async {
    await resolve?.call(evaluationResult);
  }

  @override
  Future<void> submitEvaluationAtomic({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required List<String> reasonTags,
    required String note,
    required List<String> ackTags,
    EvaluationWriteResolver? resolve,
  }) async {
    final error = submitEvaluationAtomicError;
    if (error != null) {
      throw error;
    }
    final command = await resolve?.call(evaluationResult);
    submitEvaluationAtomicCalls.add(
      _SubmitAtomicCall(
        beaconId: beaconId,
        evaluatorId: evaluatorId,
        evaluatedUserId: evaluatedUserId,
        value: command?.value ?? value,
        reasonTags: command?.reasonTags ?? reasonTags,
        note: command?.note ?? note,
        ackTags: command?.ackTags ?? ackTags,
      ),
    );
    if (mutateEvaluationOnSubmit) {
      final now = DateTime.timestamp();
      evaluationResult = BeaconEvaluationRecord(
        beaconId: beaconId,
        evaluatorId: evaluatorId,
        evaluatedUserId: evaluatedUserId,
        value: command?.value ?? value,
        reasonTags: (command?.reasonTags ?? reasonTags).join(','),
        ackTags: command?.ackTags ?? ackTags,
        note: command?.note ?? note,
        status: BeaconEvaluationRowStatus.draft,
        createdAt: now,
        updatedAt: now,
      );
    }
  }
}

class _FakeReviewFinalization implements ReviewFinalizationPort {
  final closeAndFinalizeCalls =
      <({String beaconId, String reason, String? actorUserId})>[];

  ReviewFinalizationResult result = const ReviewFinalizationResult(
    didClose: true,
  );

  @override
  Future<ReviewFinalizationResult> closeAndFinalize(
    String beaconId, {
    required String reason,
    String? actorUserId,
  }) async {
    closeAndFinalizeCalls.add(
      (beaconId: beaconId, reason: reason, actorUserId: actorUserId),
    );
    return result;
  }
}

final class _CausalEvaluationRepository extends _FakeEvaluationRepository {
  final rows = <String, BeaconEvaluationRecord>{};

  String _key(String evaluatorId, String evaluatedUserId) =>
      '$evaluatorId:$evaluatedUserId';

  @override
  Future<BeaconEvaluationRecord?> getEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) async => rows[_key(evaluatorId, evaluatedUserId)];

  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluator({
    required String beaconId,
    required String evaluatorId,
  }) async => rows.values
      .where((row) => row.beaconId == beaconId && row.evaluatorId == evaluatorId)
      .toList();

  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluatedUser({
    required String beaconId,
    required String evaluatedUserId,
  }) async => rows.values
      .where(
        (row) =>
            row.beaconId == beaconId &&
            row.evaluatedUserId == evaluatedUserId &&
            row.status == BeaconEvaluationRowStatus.final_,
      )
      .toList();

  @override
  Future<void> upsertEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required String reasonTagsCsv,
    required String note,
    int status = BeaconEvaluationRowStatus.submitted,
    EvaluationWriteResolver? resolve,
  }) async {
    final command = await resolve?.call(rows[_key(evaluatorId, evaluatedUserId)]);
    final now = DateTime.timestamp();
    rows[_key(evaluatorId, evaluatedUserId)] = BeaconEvaluationRecord(
      beaconId: beaconId,
      evaluatorId: evaluatorId,
      evaluatedUserId: evaluatedUserId,
      value: command?.value ?? value,
      reasonTags: command?.reasonTags.join(',') ?? reasonTagsCsv,
      note: command?.note ?? note,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> submitEvaluationAtomic({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required List<String> reasonTags,
    required String note,
    required List<String> ackTags,
    EvaluationWriteResolver? resolve,
  }) async {
    final command = await resolve?.call(rows[_key(evaluatorId, evaluatedUserId)]);
    final now = DateTime.timestamp();
    rows[_key(evaluatorId, evaluatedUserId)] = BeaconEvaluationRecord(
      beaconId: beaconId,
      evaluatorId: evaluatorId,
      evaluatedUserId: evaluatedUserId,
      value: command?.value ?? value,
      reasonTags: (command?.reasonTags ?? reasonTags).join(','),
      ackTags: command?.ackTags ?? ackTags,
      note: command?.note ?? note,
      status: BeaconEvaluationRowStatus.draft,
      createdAt: now,
      updatedAt: now,
    );
  }

  void finalizeSubmitted(String beaconId) {
    for (final entry in rows.entries) {
      final row = entry.value;
      if (row.beaconId == beaconId &&
          (row.status == BeaconEvaluationRowStatus.submitted ||
              row.status == BeaconEvaluationRowStatus.draft)) {
        rows[entry.key] = BeaconEvaluationRecord(
          beaconId: row.beaconId,
          evaluatorId: row.evaluatorId,
          evaluatedUserId: row.evaluatedUserId,
          value: row.value,
          reasonTags: row.reasonTags,
          ackTags: row.ackTags,
          note: row.note,
          status: BeaconEvaluationRowStatus.final_,
          createdAt: row.createdAt,
          updatedAt: DateTime.timestamp(),
        );
      }
    }
  }
}

final class _CausalBeaconRepository extends Fake
    implements BeaconRepositoryPort {
  _CausalBeaconRepository(this.current);

  BeaconEntity current;

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async => current;

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) => fn(current);

  @override
  Future<void> recordBeaconStatusTransition({
    required String beaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required String reason,
    String? actorId,
  }) async {
    current = current.copyWith(status: toStatus);
  }
}

final class _CausalReviewFinalization implements ReviewFinalizationPort {
  _CausalReviewFinalization(this.repository, this.beaconRepository);

  final _CausalEvaluationRepository repository;
  final _CausalBeaconRepository beaconRepository;

  @override
  Future<ReviewFinalizationResult> closeAndFinalize(
    String beaconId, {
    required String reason,
    String? actorUserId,
  }) async {
    repository.finalizeSubmitted(beaconId);
    beaconRepository.current = beaconRepository.current.copyWith(
      status: BeaconStatus.closed,
    );
    return const ReviewFinalizationResult(didClose: true);
  }
}

void main() {
  const beaconId = 'beacon1';
  const userId = 'user1';

  late _FakeEvaluationRepository evalRepo;
  late _FakeReviewFinalization reviewFinalization;
  late EvaluationCase evaluationCase;
  late TestAttentionHarness attention;
  late AttentionExpirySweepCase expirySweep;

  BeaconReviewWindowRecord openWindow({
    String id = beaconId,
    DateTime? closesAt,
  }) {
    final now = DateTime.timestamp();
    final opened = now.subtract(const Duration(hours: 1));
    final closes = closesAt ?? now.add(const Duration(days: 7));
    return BeaconReviewWindowRecord(
      beaconId: id,
      openedAt: opened,
      closesAt: closes,
      status: 0,
      extensionsUsed: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  BeaconEntity defaultReviewBeacon({
    BeaconStatus status = BeaconStatus.reviewOpen,
  }) =>
      BeaconEntity(
        id: beaconId,
        title: 't',
        author: UserEntity(id: userId),
        createdAt: DateTime.timestamp(),
        updatedAt: DateTime.timestamp(),
        status: status,
      );

  setUp(() {
    evalRepo = _FakeEvaluationRepository();
    reviewFinalization = _FakeReviewFinalization();
    attention = TestAttentionHarness();
    expirySweep = AttentionExpirySweepCase(
      _NoopAttentionExpiryRepository(),
      reviewFinalization,
      attention.intents,
      attention.transactional,
    );
    final helpOfferRepo = EmptyGraphHelpOfferRepository();
    final forwardRepo = EmptyGraphForwardEdgeRepository();
    final userRepo = StubUserRepository('User');
    final userProfileBatchLookup = StubUserProfileBatchLookup('User');

    final graphBuilder = EvaluationParticipantGraphBuilder(
      NoOpCommitmentRepository(),
      helpOfferRepo,
      forwardRepo,
      userRepo,
    );
    evaluationCase = buildTestEvaluationCase(
      beaconRepo: _TransactionStubBeaconRepo(defaultReviewBeacon()),
      forwardRepo: forwardRepo,
      evalRepo: evalRepo,
      userProfileBatchLookup: userProfileBatchLookup,
      graphBuilder: graphBuilder,
      attention: attention,
      expirySweep: expirySweep,
      commitmentRepo: NoOpCommitmentRepository(),
      helpOfferRepo: helpOfferRepo,
      reviewFinalization: reviewFinalization,
    );
  });

  group('evaluationFinalize', () {
    test(
      'returns true without updating status when already finalized (2)',
      () async {
        evalRepo
          ..reviewWindowResult = openWindow()
          ..reviewUserStatusResult = 2;

        expect(
          await evaluationCase.evaluationFinalize(
            beaconId: beaconId,
            userId: userId,
          ),
          isTrue,
        );
        expect(evalRepo.setReviewUserStatusCalls, isEmpty);
      },
    );

    test(
      'sets status to 2 when legacy skipped status (3) sends package',
      () async {
        evalRepo
          ..reviewWindowResult = openWindow()
          ..reviewUserStatusResult = 3;

        expect(
          await evaluationCase.evaluationFinalize(
            beaconId: beaconId,
            userId: userId,
          ),
          isTrue,
        );
        expect(
          evalRepo.setReviewUserStatusCalls,
          const [_SetStatusCall(beaconId, userId, 2)],
        );
      },
    );

    test('sets status to 2 when user was in progress (1)', () async {
      evalRepo
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = 1;

      expect(
        await evaluationCase.evaluationFinalize(
          beaconId: beaconId,
          userId: userId,
        ),
        isTrue,
      );
      expect(
        evalRepo.setReviewUserStatusCalls,
        const [_SetStatusCall(beaconId, userId, 2)],
      );
    });

    test('sets status to 2 when user never saved a rating (0)', () async {
      evalRepo
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = 0;

      expect(
        await evaluationCase.evaluationFinalize(
          beaconId: beaconId,
          userId: userId,
        ),
        isTrue,
      );
      expect(
        evalRepo.setReviewUserStatusCalls,
        const [_SetStatusCall(beaconId, userId, 2)],
      );
    });

    test('throws notEligible when user has no review row', () async {
      evalRepo
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = null;

      expect(
        () => evaluationCase.evaluationFinalize(
          beaconId: beaconId,
          userId: userId,
        ),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.notEligible,
            ).codeNumber,
          ),
        ),
      );
    });

    test('throws reviewWindowNotOpen when window is missing', () async {
      evalRepo.reviewWindowResult = null;

      expect(
        () => evaluationCase.evaluationFinalize(
          beaconId: beaconId,
          userId: userId,
        ),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.reviewWindowNotOpen,
            ).codeNumber,
          ),
        ),
      );
    });

    test(
      'throws reviewWindowNotOpen when window already closed (status 1)',
      () async {
        final now = DateTime.timestamp();
        evalRepo.reviewWindowResult = BeaconReviewWindowRecord(
          beaconId: beaconId,
          openedAt: now.subtract(const Duration(days: 8)),
          closesAt: now.subtract(const Duration(days: 1)),
          status: 1,
          extensionsUsed: 0,
          createdAt: now.subtract(const Duration(days: 8)),
          updatedAt: now,
        );

        expect(
          () => evaluationCase.evaluationFinalize(
            beaconId: beaconId,
            userId: userId,
          ),
          throwsA(
            isA<EvaluationException>().having(
              (e) => e.code.codeNumber,
              'codeNumber',
              const EvaluationExceptionCodes(
                EvaluationExceptionCode.reviewWindowNotOpen,
              ).codeNumber,
            ),
          ),
        );
      },
    );
  });

  group('evaluationSubmit', () {
    test(
      'throws reviewWindowExpired when review deadline has passed',
      () async {
        const evaluatorId = 'eval1';
        const evaluatedId = 'author1';
        final now = DateTime.timestamp();
        evalRepo
          ..reviewWindowResult = openWindow(
            closesAt: now.subtract(const Duration(days: 1)),
          )
          ..visibilityResult = [
            const BeaconEvaluationVisibilityRecord(
              beaconId: beaconId,
              evaluatorId: evaluatorId,
              participantId: evaluatedId,
            ),
          ];

        expect(
          () => evaluationCase.evaluationSubmit(
            beaconId: beaconId,
            evaluatorId: evaluatorId,
            evaluatedUserId: evaluatedId,
            value: BeaconEvaluationValue.zero,
            reasonTags: const [],
            note: '',
          ),
          throwsA(
            isA<EvaluationException>().having(
              (e) => e.code.codeNumber,
              'codeNumber',
              const EvaluationExceptionCodes(
                EvaluationExceptionCode.reviewWindowExpired,
              ).codeNumber,
            ),
          ),
        );
      },
    );

    test('first submit moves review user status from 0 to 1', () async {
      const evaluatorId = 'eval1';
      const evaluatedId = 'author1';

      evalRepo
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = 0
        ..visibilityResult = [
          const BeaconEvaluationVisibilityRecord(
            beaconId: beaconId,
            evaluatorId: evaluatorId,
            participantId: evaluatedId,
          ),
        ]
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: evaluatorId,
            role: 1,
            contributionSummary: 'e',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: evaluatedId,
            role: 0,
            contributionSummary: 's',
            causalHint: 'h',
          ),
        ];

      expect(
        await evaluationCase.evaluationSubmit(
          beaconId: beaconId,
          evaluatorId: evaluatorId,
          evaluatedUserId: evaluatedId,
          value: BeaconEvaluationValue.zero,
          reasonTags: const [],
          note: '',
        ),
        isTrue,
      );

      expect(
        evalRepo.setReviewUserStatusCalls,
        const [_SetStatusCall(beaconId, evaluatorId, 1)],
      );
    });

    test(
      'does not set review user status when already past first submit (1)',
      () async {
        const evaluatorId = 'eval1';
        const evaluatedId = 'author1';

        evalRepo
          ..reviewWindowResult = openWindow()
          ..reviewUserStatusResult = 1
          ..visibilityResult = [
            const BeaconEvaluationVisibilityRecord(
              beaconId: beaconId,
              evaluatorId: evaluatorId,
              participantId: evaluatedId,
            ),
          ]
          ..participantsResult = [
            const BeaconEvaluationParticipantRecord(
              beaconId: beaconId,
              userId: evaluatorId,
              role: 1,
              contributionSummary: 'e',
              causalHint: 'h',
            ),
            const BeaconEvaluationParticipantRecord(
              beaconId: beaconId,
              userId: evaluatedId,
              role: 0,
              contributionSummary: 's',
              causalHint: 'h',
            ),
          ];

        expect(
          await evaluationCase.evaluationSubmit(
            beaconId: beaconId,
            evaluatorId: evaluatorId,
            evaluatedUserId: evaluatedId,
            value: BeaconEvaluationValue.zero,
            reasonTags: const [],
            note: '',
          ),
          isTrue,
        );

        expect(evalRepo.setReviewUserStatusCalls, isEmpty);
      },
    );

    test('forwarder save is rejected as notEligible', () async {
      const evaluatorId = 'forwarder1';
      const evaluatedId = 'author1';

      evalRepo
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = 0
        ..visibilityResult = [
          const BeaconEvaluationVisibilityRecord(
            beaconId: beaconId,
            evaluatorId: evaluatorId,
            participantId: evaluatedId,
          ),
        ]
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: evaluatorId,
            role: 2,
            contributionSummary: 'f',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: evaluatedId,
            role: 0,
            contributionSummary: 'a',
            causalHint: 'h',
          ),
        ];

      expect(
        () => evaluationCase.evaluationSubmit(
          beaconId: beaconId,
          evaluatorId: evaluatorId,
          evaluatedUserId: evaluatedId,
          value: BeaconEvaluationValue.zero,
          reasonTags: const [],
          note: '',
          acknowledgedHelpTags: const [],
        ),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.notEligible,
            ).codeNumber,
          ),
        ),
      );
      expect(evalRepo.submitEvaluationAtomicCalls, isEmpty);
    });

    test('forwarder with ack tags is rejected as notEligible', () async {
      const evaluatorId = 'forwarder1';
      const evaluatedId = 'author1';
      final beaconRepo = _StubBeaconRepository(
        BeaconEntity(
          id: beaconId,
          title: 't',
          author: UserEntity(id: evaluatedId, displayName: 'Author'),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          status: BeaconStatus.reviewOpen,
          needs: const {'transport'},
        ),
      );

      evalRepo
        ..reviewWindowResult = openWindow()
        ..visibilityResult = [
          const BeaconEvaluationVisibilityRecord(
            beaconId: beaconId,
            evaluatorId: evaluatorId,
            participantId: evaluatedId,
          ),
        ]
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: evaluatorId,
            role: 2,
            contributionSummary: 'f',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: evaluatedId,
            role: 0,
            contributionSummary: 'a',
            causalHint: 'h',
          ),
        ];

      final localCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: EmptyGraphForwardEdgeRepository(),
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: EvaluationParticipantGraphBuilder(
          NoOpCommitmentRepository(),
          EmptyGraphHelpOfferRepository(),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        ),
        attention: attention,
        expirySweep: expirySweep,
      );

      expect(
        () => localCase.evaluationSubmit(
          beaconId: beaconId,
          evaluatorId: evaluatorId,
          evaluatedUserId: evaluatedId,
          value: BeaconEvaluationValue.zero,
          reasonTags: const [],
          note: '',
          acknowledgedHelpTags: const ['transport'],
        ),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.notEligible,
            ).codeNumber,
          ),
        ),
      );
      expect(evalRepo.submitEvaluationAtomicCalls, isEmpty);
    });

    test('invalid ack slug is rejected before atomic submit', () async {
      const evaluatorId = 'committer1';
      const evaluatedId = 'author1';
      final beaconRepo = _StubBeaconRepository(
        BeaconEntity(
          id: beaconId,
          title: 't',
          author: UserEntity(id: evaluatedId, displayName: 'Author'),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          status: BeaconStatus.reviewOpen,
          needs: const {'transport'},
        ),
      );

      evalRepo
        ..reviewWindowResult = openWindow()
        ..visibilityResult = [
          const BeaconEvaluationVisibilityRecord(
            beaconId: beaconId,
            evaluatorId: evaluatorId,
            participantId: evaluatedId,
          ),
        ]
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: evaluatorId,
            role: 1,
            contributionSummary: 'c',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: evaluatedId,
            role: 0,
            contributionSummary: 'a',
            causalHint: 'h',
          ),
        ];

      final helpOfferRepo = ConfigurableGraphHelpOfferRepository(const []);

      final localCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: EmptyGraphForwardEdgeRepository(),
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: EvaluationParticipantGraphBuilder(
          NoOpCommitmentRepository(),
          helpOfferRepo,
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        ),
        attention: attention,
        expirySweep: expirySweep,
        helpOfferRepo: helpOfferRepo,
      );

      expect(
        () => localCase.evaluationSubmit(
          beaconId: beaconId,
          evaluatorId: evaluatorId,
          evaluatedUserId: evaluatedId,
          value: BeaconEvaluationValue.zero,
          reasonTags: const [],
          note: '',
          acknowledgedHelpTags: const ['pets'],
        ),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.invalidAckTagSlug,
            ).codeNumber,
          ),
        ),
      );
      expect(evalRepo.submitEvaluationAtomicCalls, isEmpty);
    });

    test('maps ack tag cap StateError to EvaluationException', () async {
      const evaluatorId = 'committer1';
      const evaluatedId = 'author1';
      final beaconRepo = _StubBeaconRepository(
        BeaconEntity(
          id: beaconId,
          title: 't',
          author: UserEntity(id: evaluatedId, displayName: 'Author'),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          status: BeaconStatus.reviewOpen,
          needs: const {'transport', 'pets', 'manual_labour'},
        ),
      );

      evalRepo
        ..reviewWindowResult = openWindow()
        ..visibilityResult = [
          const BeaconEvaluationVisibilityRecord(
            beaconId: beaconId,
            evaluatorId: evaluatorId,
            participantId: evaluatedId,
          ),
        ]
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: evaluatorId,
            role: 1,
            contributionSummary: 'c',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: evaluatedId,
            role: 0,
            contributionSummary: 'a',
            causalHint: 'h',
          ),
        ]
        ..submitEvaluationAtomicError = StateError('Ack tag cap exceeded');

      final localCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: EmptyGraphForwardEdgeRepository(),
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: EvaluationParticipantGraphBuilder(
          NoOpCommitmentRepository(),
          EmptyGraphHelpOfferRepository(),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        ),
        attention: attention,
        expirySweep: expirySweep,
      );

      expect(
        () => localCase.evaluationSubmit(
          beaconId: beaconId,
          evaluatorId: evaluatorId,
          evaluatedUserId: evaluatedId,
          value: BeaconEvaluationValue.zero,
          reasonTags: const [],
          note: '',
          acknowledgedHelpTags: const ['transport', 'pets', 'manual_labour'],
        ),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.ackTagCapExceeded,
            ).codeNumber,
          ),
        ),
      );
    });
  });

  group('live review guard', () {
    test('evaluationSubmit rejects when request is not wrapping up', () async {
      const evaluatorId = 'eval1';
      const evaluatedId = 'author1';
      evalRepo
        ..reviewWindowResult = openWindow()
        ..visibilityResult = [
          const BeaconEvaluationVisibilityRecord(
            beaconId: beaconId,
            evaluatorId: evaluatorId,
            participantId: evaluatedId,
          ),
        ];

      final localCase = buildTestEvaluationCase(
        beaconRepo: _TransactionStubBeaconRepo(
          defaultReviewBeacon(status: BeaconStatus.enoughHelp),
        ),
        forwardRepo: EmptyGraphForwardEdgeRepository(),
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: EvaluationParticipantGraphBuilder(
          NoOpCommitmentRepository(),
          EmptyGraphHelpOfferRepository(),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        ),
        attention: attention,
        expirySweep: expirySweep,
      );

      expect(
        () => localCase.evaluationSubmit(
          beaconId: beaconId,
          evaluatorId: evaluatorId,
          evaluatedUserId: evaluatedId,
          value: BeaconEvaluationValue.zero,
          reasonTags: const [],
          note: '',
        ),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.reviewWindowNotOpen,
            ).codeNumber,
          ),
        ),
      );
    });

    test('evaluationFinalize rejects when review window is complete', () async {
      evalRepo
        ..reviewWindowResult = BeaconReviewWindowRecord(
          beaconId: beaconId,
          openedAt: DateTime.timestamp().subtract(const Duration(days: 8)),
          closesAt: DateTime.timestamp().subtract(const Duration(days: 1)),
          status: 1,
          extensionsUsed: 0,
          createdAt: DateTime.timestamp(),
          updatedAt: DateTime.timestamp(),
        )
        ..reviewUserStatusResult = 0;

      expect(
        () => evaluationCase.evaluationFinalize(
          beaconId: beaconId,
          userId: userId,
        ),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.reviewWindowNotOpen,
            ).codeNumber,
          ),
        ),
      );
    });
  });

  group('evaluationSubmit reason-tag tri-state', () {
    ({_FakeEvaluationRepository repo, EvaluationCase case_}) fixture({
      BeaconEvaluationRecord? existing,
    }) {
      final localRepo = _FakeEvaluationRepository()
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = 1
        ..evaluationResult = existing
        ..visibilityResult = [
          const BeaconEvaluationVisibilityRecord(
            beaconId: beaconId,
            evaluatorId: 'evaluator',
            participantId: 'subject',
          ),
        ]
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: 'evaluator',
            role: 1,
            contributionSummary: 'evaluator',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: 'subject',
            role: 0,
            contributionSummary: 'subject',
            causalHint: 'h',
          ),
        ];
      final localCase = buildTestEvaluationCase(
        beaconRepo: _StubBeaconRepository(
          BeaconEntity(
            id: beaconId,
            title: 't',
            author: const UserEntity(id: 'subject'),
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            status: BeaconStatus.reviewOpen,
          ),
        ),
        forwardRepo: EmptyGraphForwardEdgeRepository(),
        evalRepo: localRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: EvaluationParticipantGraphBuilder(
          NoOpCommitmentRepository(),
          EmptyGraphHelpOfferRepository(),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        ),
        attention: attention,
        expirySweep: expirySweep,
      );
      return (repo: localRepo, case_: localCase);
    }

    BeaconEvaluationRecord existing(String tags) => BeaconEvaluationRecord(
      beaconId: beaconId,
      evaluatorId: 'evaluator',
      evaluatedUserId: 'subject',
      value: BeaconEvaluationValue.pos1,
      reasonTags: tags,
      note: 'old',
      status: BeaconEvaluationRowStatus.submitted,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    Future<void> submit(
      ({_FakeEvaluationRepository repo, EvaluationCase case_}) fixture, {
      required int value,
      List<String>? reasonTags,
    }) async {
      await fixture.case_.evaluationSubmit(
        beaconId: beaconId,
        evaluatorId: 'evaluator',
        evaluatedUserId: 'subject',
        value: value,
        reasonTags: reasonTags,
        note: 'new',
      );
    }

    test('new omitted reasons are empty', () async {
      final f = fixture();
      await submit(f, value: BeaconEvaluationValue.pos1);
      expect(f.repo.submitEvaluationAtomicCalls.single.reasonTags, isEmpty);
    });

    test('NO_BASIS live promotion remains valid with empty reasons', () async {
      final f = fixture();
      await submit(f, value: BeaconEvaluationValue.noBasis);
      expect(
        f.repo.submitEvaluationAtomicCalls.single.value,
        BeaconEvaluationValue.noBasis,
      );
      expect(f.repo.submitEvaluationAtomicCalls.single.reasonTags, isEmpty);
    });

    test('unchanged compatible reasons are preserved', () async {
      final f = fixture(existing: existing('clear_request'));
      await submit(f, value: BeaconEvaluationValue.pos1);
      expect(
        f.repo.submitEvaluationAtomicCalls.single.reasonTags,
        ['clear_request'],
      );
    });

    test('compatible value transition preserves reasons', () async {
      final f = fixture(existing: existing('clear_request'));
      await submit(f, value: BeaconEvaluationValue.pos2);
      expect(
        f.repo.submitEvaluationAtomicCalls.single.reasonTags,
        ['clear_request'],
      );
    });

    test('incompatible value transition clears reasons', () async {
      final f = fixture(existing: existing('clear_request'));
      await submit(f, value: BeaconEvaluationValue.neg1);
      expect(f.repo.submitEvaluationAtomicCalls.single.reasonTags, isEmpty);
    });

    test('explicit empty reasons clear persisted reasons', () async {
      final f = fixture(existing: existing('clear_request'));
      await submit(f, value: BeaconEvaluationValue.pos1, reasonTags: const []);
      expect(f.repo.submitEvaluationAtomicCalls.single.reasonTags, isEmpty);
    });

    test('valid explicit reasons replace persisted reasons', () async {
      final f = fixture(existing: existing('clear_request'));
      await submit(
        f,
        value: BeaconEvaluationValue.pos1,
        reasonTags: const ['fair_closure'],
      );
      expect(
        f.repo.submitEvaluationAtomicCalls.single.reasonTags,
        ['fair_closure'],
      );
    });

    test('invalid explicit reasons are rejected', () async {
      final f = fixture(existing: existing('clear_request'));
      await expectLater(
        () => submit(
          f,
          value: BeaconEvaluationValue.pos1,
          reasonTags: const ['unclear_request'],
        ),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.invalidReasonTags,
            ).codeNumber,
          ),
        ),
      );
      expect(f.repo.submitEvaluationAtomicCalls, isEmpty);
    });

    test(
      'persisted-only acknowledgement is retained then removed and cannot re-add',
      () async {
        final f = fixture(
          existing: BeaconEvaluationRecord(
            beaconId: beaconId,
            evaluatorId: 'evaluator',
            evaluatedUserId: 'subject',
            value: BeaconEvaluationValue.pos1,
            reasonTags: 'clear_request',
            ackTags: const ['legacy'],
            note: 'old',
            status: BeaconEvaluationRowStatus.submitted,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        f.repo.mutateEvaluationOnSubmit = true;
        await f.case_.evaluationSubmit(
          beaconId: beaconId,
          evaluatorId: 'evaluator',
          evaluatedUserId: 'subject',
          value: BeaconEvaluationValue.pos1,
          reasonTags: const [],
          note: 'retain',
          acknowledgedHelpTags: const ['legacy'],
        );
        expect(f.repo.evaluationResult?.ackTags, ['legacy']);
        await f.case_.evaluationSubmit(
          beaconId: beaconId,
          evaluatorId: 'evaluator',
          evaluatedUserId: 'subject',
          value: BeaconEvaluationValue.pos1,
          reasonTags: const [],
          note: 'remove',
          acknowledgedHelpTags: const [],
        );
        await expectLater(
          () => f.case_.evaluationSubmit(
            beaconId: beaconId,
            evaluatorId: 'evaluator',
            evaluatedUserId: 'subject',
            value: BeaconEvaluationValue.pos1,
            reasonTags: const [],
            note: 're-add',
            acknowledgedHelpTags: const ['legacy'],
          ),
          throwsA(isA<EvaluationException>()),
        );
      },
    );
  });

  group('evaluationSkip', () {
    test('throws notEligible because skip is removed', () async {
      evalRepo
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = 0;

      expect(
        () => evaluationCase.evaluationSkip(beaconId: beaconId, userId: userId),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.notEligible,
            ).codeNumber,
          ),
        ),
      );
      expect(evalRepo.setReviewUserStatusCalls, isEmpty);
    });
  });

  group('reopenFromReview', () {
    late _TransactionStubBeaconRepo beaconRepo;

    setUp(() {
      evalRepo = _FakeEvaluationRepository();
      beaconRepo = _TransactionStubBeaconRepo(
        BeaconEntity(
          id: beaconId,
          title: 't',
          author: UserEntity(id: userId),
          createdAt: DateTime.timestamp(),
          updatedAt: DateTime.timestamp(),
          status: BeaconStatus.reviewOpen,
        ),
      );
      final helpOfferRepo = EmptyGraphHelpOfferRepository();
      final forwardRepo = EmptyGraphForwardEdgeRepository();
      final userRepo = StubUserRepository('User');
      final userProfileBatchLookup = StubUserProfileBatchLookup('User');
      final graphBuilder = EvaluationParticipantGraphBuilder(
        NoOpCommitmentRepository(),
        helpOfferRepo,
        forwardRepo,
        userRepo,
      );
      evaluationCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        evalRepo: evalRepo,
        userProfileBatchLookup: userProfileBatchLookup,
        graphBuilder: graphBuilder,
        attention: attention,
        expirySweep: expirySweep,
      );
    });

    test('downgrades submitted reviews and clears scaffolding only', () async {
      evalRepo.reviewWindowResult = openWindow();

      final result = await evaluationCase.reopenFromReview(
        beaconId: beaconId,
        userId: userId,
      );

      expect(result.status, 0);
      expect(evalRepo.downgradeSubmittedCalls, 1);
      expect(evalRepo.deleteScaffoldingCalls, 1);
      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.reviewOpen,
          toStatus: BeaconStatus.open,
          reason: BeaconLifecycleChangeReason.reopenedFromReview,
          actorId: userId,
        ),
      ]);
      expect(beaconRepo.storedReviewReopenCount, 1);
    });

    test('throws when reopen limit reached', () async {
      evalRepo.reviewWindowResult = openWindow();
      beaconRepo = _TransactionStubBeaconRepo(
        BeaconEntity(
          id: beaconId,
          title: 't',
          author: UserEntity(id: userId),
          createdAt: DateTime.timestamp(),
          updatedAt: DateTime.timestamp(),
          status: BeaconStatus.reviewOpen,
        ),
        reviewReopenCount: 1,
      );
      final helpOfferRepo = EmptyGraphHelpOfferRepository();
      final forwardRepo = EmptyGraphForwardEdgeRepository();
      evaluationCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: EvaluationParticipantGraphBuilder(
          NoOpCommitmentRepository(),
          helpOfferRepo,
          forwardRepo,
          StubUserRepository('User'),
        ),
        attention: attention,
        expirySweep: expirySweep,
      );

      expect(
        () => evaluationCase.reopenFromReview(
          beaconId: beaconId,
          userId: userId,
        ),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.description,
            'description',
            'Reopen limit reached',
          ),
        ),
      );
    });
  });

  group('beaconClose review cycle reset', () {
    late _TransactionStubBeaconRepo beaconRepo;

    setUp(() {
      evalRepo = _FakeEvaluationRepository();
      beaconRepo = _TransactionStubBeaconRepo(
        BeaconEntity(
          id: beaconId,
          title: 't',
          author: UserEntity(id: userId),
          createdAt: DateTime.timestamp(),
          updatedAt: DateTime.timestamp(),
          status: BeaconStatus.open,
        ),
      );
      final now = DateTime.utc(2025);
      final helpOfferRepo = _SingleCommitterHelpOfferRepo(
        HelpOfferEntity(
          beaconId: beaconId,
          userId: 'helper1',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final commitmentRepo = acknowledgedCommitterCommitmentRepo(
        beaconId: beaconId,
        helperId: 'helper1',
        authorId: userId,
        baseTime: now,
      );
      final forwardRepo = EmptyGraphForwardEdgeRepository();
      final userRepo = StubUserRepository('User');
      final userProfileBatchLookup = StubUserProfileBatchLookup('User');
      final graphBuilder = EvaluationParticipantGraphBuilder(
        commitmentRepo,
        helpOfferRepo,
        forwardRepo,
        userRepo,
      );
      evaluationCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        evalRepo: evalRepo,
        userProfileBatchLookup: userProfileBatchLookup,
        graphBuilder: graphBuilder,
        attention: attention,
        expirySweep: expirySweep,
        commitmentRepo: commitmentRepo,
        helpOfferRepo: helpOfferRepo,
      );
    });

    test(
      'resets stale scaffolding instead of throwing review exists',
      () async {
        evalRepo.reviewWindowResult = openWindow();

        final result = await evaluationCase.beaconClose(
          beaconId: beaconId,
          userId: userId,
          expectedRequiresReviewWindow: true,
        );

        expect(result.status, BeaconStatus.reviewOpen.smallintValue);
        expect(evalRepo.downgradeSubmittedCalls, 1);
        expect(evalRepo.deleteScaffoldingCalls, 1);
        expect(evalRepo.insertReviewWindowCalls, 1);
      },
    );

    test(
      'refuses wrap-up when completed review episode exists on open request',
      () async {
        final now = DateTime.utc(2025);
        evalRepo.reviewWindowResult = BeaconReviewWindowRecord(
          beaconId: beaconId,
          openedAt: now.subtract(const Duration(days: 8)),
          closesAt: now.subtract(const Duration(days: 1)),
          status: 1,
          extensionsUsed: 0,
          createdAt: now.subtract(const Duration(days: 8)),
          updatedAt: now,
        );

        await expectLater(
          () => evaluationCase.beaconClose(
            beaconId: beaconId,
            userId: userId,
            expectedRequiresReviewWindow: true,
          ),
          throwsA(
            isA<EvaluationException>().having(
              (e) => e.code.codeNumber,
              'codeNumber',
              const EvaluationExceptionCodes(
                EvaluationExceptionCode.reviewAlreadyClosed,
              ).codeNumber,
            ),
          ),
        );

        expect(evalRepo.insertReviewWindowCalls, 0);
      },
    );
  });

  group('beaconClose direct close', () {
    late _TransactionStubBeaconRepo beaconRepo;

    setUp(() {
      evalRepo = _FakeEvaluationRepository();
      beaconRepo = _TransactionStubBeaconRepo(
        BeaconEntity(
          id: beaconId,
          title: 't',
          author: UserEntity(id: userId),
          createdAt: DateTime.timestamp(),
          updatedAt: DateTime.timestamp(),
          status: BeaconStatus.open,
        ),
      );
      final graphBuilder = EvaluationParticipantGraphBuilder(
        NoOpCommitmentRepository(),
        EmptyGraphHelpOfferRepository(),
        EmptyGraphForwardEdgeRepository(),
        StubUserRepository('User'),
      );
      final forwardRepo = EmptyGraphForwardEdgeRepository();
      final helpOfferRepo = EmptyGraphHelpOfferRepository();
      evaluationCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: graphBuilder,
        attention: attention,
        expirySweep: expirySweep,
        helpOfferRepo: helpOfferRepo,
      );
    });

    test('closes directly without review window when no committers', () async {
      final result = await evaluationCase.beaconClose(
        beaconId: beaconId,
        userId: userId,
        expectedRequiresReviewWindow: false,
      );

      expect(result.status, BeaconStatus.closed.smallintValue);
      expect(result.closesAt, isNull);
      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.open,
          toStatus: BeaconStatus.closed,
          reason: BeaconLifecycleChangeReason.directClose,
          actorId: userId,
        ),
      ]);
      expect(evalRepo.insertReviewWindowCalls, 0);
      expect(evalRepo.downgradeSubmittedCalls, 0);
      expect(evalRepo.deleteScaffoldingCalls, 0);
    });
  });

  group('beaconClose review-open path', () {
    late _TransactionStubBeaconRepo beaconRepo;

    setUp(() {
      evalRepo = _FakeEvaluationRepository();
      beaconRepo = _TransactionStubBeaconRepo(
        BeaconEntity(
          id: beaconId,
          title: 't',
          author: UserEntity(id: userId),
          createdAt: DateTime.timestamp(),
          updatedAt: DateTime.timestamp(),
          status: BeaconStatus.open,
        ),
      );
      final now = DateTime.utc(2025);
      final helpOfferRepo = _SingleCommitterHelpOfferRepo(
        HelpOfferEntity(
          beaconId: beaconId,
          userId: 'helper1',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final commitmentRepo = acknowledgedCommitterCommitmentRepo(
        beaconId: beaconId,
        helperId: 'helper1',
        authorId: userId,
        baseTime: now,
      );
      final graphBuilder = EvaluationParticipantGraphBuilder(
        commitmentRepo,
        helpOfferRepo,
        EmptyGraphForwardEdgeRepository(),
        StubUserRepository('User'),
      );
      final forwardRepo = EmptyGraphForwardEdgeRepository();
      evaluationCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: graphBuilder,
        attention: attention,
        expirySweep: expirySweep,
        commitmentRepo: commitmentRepo,
        helpOfferRepo: helpOfferRepo,
      );
    });

    test('opens review window when committers exist', () async {
      final result = await evaluationCase.beaconClose(
        beaconId: beaconId,
        userId: userId,
        expectedRequiresReviewWindow: true,
      );

      expect(result.status, BeaconStatus.reviewOpen.smallintValue);
      expect(result.closesAt, isNotNull);
      expect(evalRepo.downgradeSubmittedCalls, 1);
      expect(evalRepo.deleteScaffoldingCalls, 1);
      expect(evalRepo.insertReviewWindowCalls, 1);
      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.open,
          toStatus: BeaconStatus.reviewOpen,
          reason: BeaconLifecycleChangeReason.reviewWindowOpened,
          actorId: userId,
        ),
      ]);
      expect(attention.recorded, hasLength(2));
      expect(
        attention.recorded.map((n) => n.eventType),
        containsAll([
          AttentionEventType.requestStatusChanged,
          AttentionEventType.reviewOpened,
        ]),
      );
      final notification = attention.recorded.singleWhere(
        (n) => n.eventType == AttentionEventType.reviewOpened,
      );
      expect(notification.beaconId, beaconId);
      expect(notification.kind.name, 'reviewReady');
      expect(notification.actionUrl, '/#/beacon/review/$beaconId');
      expect(
        notification.recipients.map((recipient) => recipient.recipientId),
        ['helper1'],
      );
      expect(notification.actorUserId, userId);
    });
  });

  group('beaconClose validation', () {
    late _TransactionStubBeaconRepo beaconRepo;

    setUp(() {
      evalRepo = _FakeEvaluationRepository();
      beaconRepo = _TransactionStubBeaconRepo(
        BeaconEntity(
          id: beaconId,
          title: 't',
          author: UserEntity(id: userId),
          createdAt: DateTime.timestamp(),
          updatedAt: DateTime.timestamp(),
          status: BeaconStatus.open,
        ),
      );
      final now = DateTime.utc(2025);
      final helpOfferRepo = _SingleCommitterHelpOfferRepo(
        HelpOfferEntity(
          beaconId: beaconId,
          userId: 'helper1',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final commitmentRepo = acknowledgedCommitterCommitmentRepo(
        beaconId: beaconId,
        helperId: 'helper1',
        authorId: userId,
        baseTime: now,
      );
      final graphBuilder = EvaluationParticipantGraphBuilder(
        commitmentRepo,
        helpOfferRepo,
        EmptyGraphForwardEdgeRepository(),
        StubUserRepository('User'),
      );
      final forwardRepo = EmptyGraphForwardEdgeRepository();
      evaluationCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: graphBuilder,
        attention: attention,
        expirySweep: expirySweep,
        commitmentRepo: commitmentRepo,
        helpOfferRepo: helpOfferRepo,
      );
    });

    test(
      'throws closeBranchConflict when expected review flag is stale',
      () async {
        expect(
          () => evaluationCase.beaconClose(
            beaconId: beaconId,
            userId: userId,
            expectedRequiresReviewWindow: false,
          ),
          throwsA(
            isA<EvaluationException>().having(
              (e) => e.code.codeNumber,
              'codeNumber',
              const EvaluationExceptionCodes(
                EvaluationExceptionCode.closeBranchConflict,
              ).codeNumber,
            ),
          ),
        );
      },
    );

    test('throws notEligible when caller is not the author', () async {
      expect(
        () => evaluationCase.beaconClose(
          beaconId: beaconId,
          userId: 'other-user',
          expectedRequiresReviewWindow: true,
        ),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.notEligible,
            ).codeNumber,
          ),
        ),
      );
    });

    test(
      'throws beaconNotClosable when beacon is not in open family',
      () async {
        beaconRepo = _TransactionStubBeaconRepo(
          BeaconEntity(
            id: beaconId,
            title: 't',
            author: UserEntity(id: userId),
            createdAt: DateTime.timestamp(),
            updatedAt: DateTime.timestamp(),
            status: BeaconStatus.closed,
          ),
        );
        final graphBuilder = EvaluationParticipantGraphBuilder(
          NoOpCommitmentRepository(),
          EmptyGraphHelpOfferRepository(),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        );
        final forwardRepo = EmptyGraphForwardEdgeRepository();
        final helpOfferRepo = EmptyGraphHelpOfferRepository();
        evaluationCase = buildTestEvaluationCase(
          beaconRepo: beaconRepo,
          forwardRepo: forwardRepo,
          evalRepo: evalRepo,
          userProfileBatchLookup: StubUserProfileBatchLookup('User'),
          graphBuilder: graphBuilder,
          attention: attention,
          expirySweep: expirySweep,
          helpOfferRepo: helpOfferRepo,
        );

        expect(
          () => evaluationCase.beaconClose(
            beaconId: beaconId,
            userId: userId,
            expectedRequiresReviewWindow: false,
          ),
          throwsA(
            isA<EvaluationException>().having(
              (e) => e.code.codeNumber,
              'codeNumber',
              const EvaluationExceptionCodes(
                EvaluationExceptionCode.beaconNotClosable,
              ).codeNumber,
            ),
          ),
        );
      },
    );
  });

  group('beaconClose everHadCommitter review window', () {
    late _TransactionStubBeaconRepo beaconRepo;

    setUp(() {
      evalRepo = _FakeEvaluationRepository();
      beaconRepo = _TransactionStubBeaconRepo(
        BeaconEntity(
          id: beaconId,
          title: 't',
          author: UserEntity(id: userId),
          createdAt: DateTime.timestamp(),
          updatedAt: DateTime.timestamp(),
          status: BeaconStatus.open,
        ),
      );
      final now = DateTime.utc(2025);
      const helperId = 'helper1';
      final withdrawnOffer = HelpOfferEntity(
        beaconId: beaconId,
        userId: helperId,
        createdAt: now,
        updatedAt: now.add(const Duration(hours: 31)),
        status: 1,
        message: 'helped out',
      );
      final helpOfferRepo = ConfigurableGraphHelpOfferRepository([withdrawnOffer]);
      final commitmentRepo = acknowledgedCommitterCommitmentRepo(
        beaconId: beaconId,
        helperId: helperId,
        authorId: userId,
        baseTime: now,
        withdrawAfterAck: const Duration(hours: 30),
      );
      final forwardRepo = EmptyGraphForwardEdgeRepository();
      final graphBuilder = EvaluationParticipantGraphBuilder(
        commitmentRepo,
        helpOfferRepo,
        forwardRepo,
        StubUserRepository('User'),
      );
      evaluationCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: graphBuilder,
        attention: attention,
        expirySweep: expirySweep,
        commitmentRepo: commitmentRepo,
        helpOfferRepo: helpOfferRepo,
      );
    });

    test(
      'opens review window when helper withdrew after grace without current committer',
      () async {
        final result = await evaluationCase.beaconClose(
          beaconId: beaconId,
          userId: userId,
          // Client-shaped expected after P3.11: everAcknowledgedCommitterCount > 0.
          expectedRequiresReviewWindow: true,
        );

        expect(result.status, BeaconStatus.reviewOpen.smallintValue);
        expect(evalRepo.insertReviewWindowCalls, 1);
      },
    );

    test(
      'does not throw closeBranchConflict when client sends DTO-shaped expected',
      () async {
        await expectLater(
          evaluationCase.beaconClose(
            beaconId: beaconId,
            userId: userId,
            expectedRequiresReviewWindow: true,
          ),
          completes,
        );
      },
    );
  });

  group('beaconClose unansweredAtClose events', () {
    late _TransactionStubBeaconRepo beaconRepo;

    setUp(() {
      evalRepo = _FakeEvaluationRepository();
      beaconRepo = _TransactionStubBeaconRepo(
        BeaconEntity(
          id: beaconId,
          title: 't',
          author: UserEntity(id: userId),
          createdAt: DateTime.timestamp(),
          updatedAt: DateTime.timestamp(),
          status: BeaconStatus.open,
        ),
      );
    });

    test('records unansweredAtClose for active normal unanswered offer', () async {
      final now = DateTime.utc(2025);
      const unansweredHelper = 'helper-unanswered';
      final commitmentRepo = RecordingCommitmentRepository(
        eventsByPair: {
          commitmentPairKey(beaconId, unansweredHelper): [
            CommitmentEvent(
              id: 'CE-offered',
              seq: 1,
              beaconId: beaconId,
              userId: unansweredHelper,
              actorUserId: unansweredHelper,
              kind: CommitmentEventKind.offered,
              createdAt: now,
            ),
          ],
        },
      );
      final helpOfferRepo = ConfigurableGraphHelpOfferRepository([
        HelpOfferEntity(
          beaconId: beaconId,
          userId: unansweredHelper,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final forwardRepo = EmptyGraphForwardEdgeRepository();
      evaluationCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: EvaluationParticipantGraphBuilder(
          commitmentRepo,
          helpOfferRepo,
          forwardRepo,
          StubUserRepository('User'),
        ),
        attention: attention,
        expirySweep: expirySweep,
        commitmentRepo: commitmentRepo,
        helpOfferRepo: helpOfferRepo,
      );

      await evaluationCase.beaconClose(
        beaconId: beaconId,
        userId: userId,
        expectedRequiresReviewWindow: false,
      );

      expect(commitmentRepo.recordCalls, hasLength(1));
      expect(commitmentRepo.recordCalls.single.kind,
          CommitmentEventKind.unansweredAtClose);
      expect(commitmentRepo.recordCalls.single.userId, unansweredHelper);
      expect(commitmentRepo.recordCalls.single.actorUserId, userId);
    });

    test('does not record unansweredAtClose for backup offers', () async {
      final now = DateTime.utc(2025);
      const backupHelper = 'backup-helper';
      final commitmentRepo = RecordingCommitmentRepository();
      final helpOfferRepo = ConfigurableGraphHelpOfferRepository([
        HelpOfferEntity(
          beaconId: beaconId,
          userId: backupHelper,
          createdAt: now,
          updatedAt: now,
          offerKind: 1,
        ),
      ]);
      final forwardRepo = EmptyGraphForwardEdgeRepository();
      evaluationCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: EvaluationParticipantGraphBuilder(
          commitmentRepo,
          helpOfferRepo,
          forwardRepo,
          StubUserRepository('User'),
        ),
        attention: attention,
        expirySweep: expirySweep,
        commitmentRepo: commitmentRepo,
        helpOfferRepo: helpOfferRepo,
      );

      await evaluationCase.beaconClose(
        beaconId: beaconId,
        userId: userId,
        expectedRequiresReviewWindow: false,
      );

      expect(commitmentRepo.recordCalls, isEmpty);
    });
  });

  group('extendReviewWindow', () {
    late _TransactionStubBeaconRepo beaconRepo;

    setUp(() {
      final now = DateTime.utc(2025);
      evalRepo = _FakeEvaluationRepository()
        ..reviewWindowResult = BeaconReviewWindowRecord(
          beaconId: beaconId,
          openedAt: now.subtract(const Duration(days: 1)),
          closesAt: now.add(const Duration(days: 6)),
          status: 0,
          extensionsUsed: 0,
          createdAt: now.subtract(const Duration(days: 1)),
          updatedAt: now,
        )
        ..extendReviewResult = now.add(const Duration(days: 13));
      final expirySweep = AttentionExpirySweepCase(
        _NoopAttentionExpiryRepository(),
        reviewFinalization,
        attention.intents,
        attention.transactional,
      );
      beaconRepo = _TransactionStubBeaconRepo(
        BeaconEntity(
          id: beaconId,
          title: 't',
          author: const UserEntity(id: userId),
          createdAt: now,
          updatedAt: now,
          status: BeaconStatus.reviewOpen,
        ),
      );
      final graphBuilder = EvaluationParticipantGraphBuilder(
        NoOpCommitmentRepository(),
        EmptyGraphHelpOfferRepository(),
        EmptyGraphForwardEdgeRepository(),
        StubUserRepository('User'),
      );
      final forwardRepo = EmptyGraphForwardEdgeRepository();
      final helpOfferRepo = EmptyGraphHelpOfferRepository();
      evaluationCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: graphBuilder,
        attention: attention,
        expirySweep: expirySweep,
        helpOfferRepo: helpOfferRepo,
        reviewFinalization: reviewFinalization,
      );
    });

    test(
      'returns the dedicated extension result and remaining count',
      () async {
        final result = await evaluationCase.extendReviewWindow(
          beaconId: beaconId,
          userId: userId,
        );

        expect(result.id, beaconId);
        expect(result.closesAt, evalRepo.extendReviewResult);
        expect(result.extensionsRemaining, 1);
      },
    );

    test('decrements remaining count after the first extension', () async {
      final window = evalRepo.reviewWindowResult!;
      evalRepo.reviewWindowResult = BeaconReviewWindowRecord(
        beaconId: window.beaconId,
        openedAt: window.openedAt,
        closesAt: window.closesAt,
        status: window.status,
        extensionsUsed: 1,
        createdAt: window.createdAt,
        updatedAt: window.updatedAt,
      );

      final result = await evaluationCase.extendReviewWindow(
        beaconId: beaconId,
        userId: userId,
      );

      expect(result.extensionsRemaining, 0);
    });
  });

  group('closeNow', () {
    late _TransactionStubBeaconRepo beaconRepo;
    const helperId = 'helper1';

    EvaluationCase buildCase() {
      final forwardRepo = EmptyGraphForwardEdgeRepository();
      final helpOfferRepo = EmptyGraphHelpOfferRepository();
      final graphBuilder = EvaluationParticipantGraphBuilder(
        NoOpCommitmentRepository(),
        helpOfferRepo,
        forwardRepo,
        StubUserRepository('User'),
      );
      return buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: graphBuilder,
        attention: attention,
        expirySweep: expirySweep,
        helpOfferRepo: helpOfferRepo,
        reviewFinalization: reviewFinalization,
      );
    }

    setUp(() {
      evalRepo = _FakeEvaluationRepository()
        ..reviewWindowResult = openWindow()
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: userId,
            role: 0,
            contributionSummary: 'author',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: helperId,
            role: 1,
            contributionSummary: 'helper',
            causalHint: 'h',
          ),
        ];
      beaconRepo = _TransactionStubBeaconRepo(
        BeaconEntity(
          id: beaconId,
          title: 't',
          author: UserEntity(id: userId),
          createdAt: DateTime.timestamp(),
          updatedAt: DateTime.timestamp(),
          status: BeaconStatus.reviewOpen,
        ),
      );
      evaluationCase = buildCase();
    });

    test('closes early when required reviewers have sent', () async {
      evalRepo.reviewStatusesResult = {
        userId: 2,
        helperId: 2,
      };

      final result = await evaluationCase.closeNow(
        beaconId: beaconId,
        userId: userId,
      );

      expect(result.status, BeaconStatus.closed.smallintValue);
      expect(reviewFinalization.closeAndFinalizeCalls, [
        (
          beaconId: beaconId,
          reason: BeaconLifecycleChangeReason.authorCloseNow,
          actorUserId: userId,
        ),
      ]);
    });

    test('throws notEligible when required reviewers are incomplete', () async {
      evalRepo.reviewStatusesResult = {
        userId: 2,
        helperId: 1,
      };

      expect(
        () => evaluationCase.closeNow(beaconId: beaconId, userId: userId),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.notEligible,
            ).codeNumber,
          ),
        ),
      );
      expect(reviewFinalization.closeAndFinalizeCalls, isEmpty);
    });

    test('throws notEligible when a required reviewer only skipped', () async {
      evalRepo.reviewStatusesResult = {
        userId: 2,
        helperId: 3,
      };

      expect(
        () => evaluationCase.closeNow(beaconId: beaconId, userId: userId),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.notEligible,
            ).codeNumber,
          ),
        ),
      );
      expect(reviewFinalization.closeAndFinalizeCalls, isEmpty);
    });

    test(
      'does not block closeNow when former committer review is incomplete',
      () async {
        evalRepo.participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: userId,
            role: 0,
            contributionSummary: 'author',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: 'former-helper',
            role: 3,
            contributionSummary: 'former',
            causalHint: 'h',
          ),
        ];
        evalRepo.reviewStatusesResult = {
          userId: 2,
          'former-helper': 1,
        };

        final result = await evaluationCase.closeNow(
          beaconId: beaconId,
          userId: userId,
        );

        expect(result.status, BeaconStatus.closed.smallintValue);
        expect(reviewFinalization.closeAndFinalizeCalls, isNotEmpty);
      },
    );

    test(
      'throws reviewWindowNotOpen when review window already closed',
      () async {
        final now = DateTime.timestamp();
        evalRepo.reviewWindowResult = BeaconReviewWindowRecord(
          beaconId: beaconId,
          openedAt: now.subtract(const Duration(days: 8)),
          closesAt: now.subtract(const Duration(days: 1)),
          status: 1,
          extensionsUsed: 0,
          createdAt: now.subtract(const Duration(days: 8)),
          updatedAt: now,
        );

        expect(
          () => evaluationCase.closeNow(beaconId: beaconId, userId: userId),
          throwsA(
            isA<EvaluationException>().having(
              (e) => e.code.codeNumber,
              'codeNumber',
              const EvaluationExceptionCodes(
                EvaluationExceptionCode.reviewWindowNotOpen,
              ).codeNumber,
            ),
          ),
        );
      },
    );

    test(
      'records trustGivenChanged and trustReceivedChanged for author, committer, and forwarder pairs',
      () async {
        const committerId = helperId;
        const forwarderId = 'forwarder1';
        evalRepo.reviewStatusesResult = {
          userId: 2,
          committerId: 2,
        };
        reviewFinalization.result = ReviewFinalizationResult(
          didClose: true,
          beaconTitle: 'Collaboration request',
          pairs: [
            const FinalizedTrustPair(
              evaluatorId: userId,
              evaluatedUserId: committerId,
              bin: TrustBin.good,
            ),
            const FinalizedTrustPair(
              evaluatorId: committerId,
              evaluatedUserId: userId,
              bin: TrustBin.bad,
            ),
            const FinalizedTrustPair(
              evaluatorId: forwarderId,
              evaluatedUserId: committerId,
              bin: TrustBin.veryGood,
            ),
          ],
        );

        await evaluationCase.closeNow(beaconId: beaconId, userId: userId);

        final given = attention.recorded
            .where((i) => i.eventType == AttentionEventType.trustGivenChanged)
            .toList();
        final received = attention.recorded
            .where((i) => i.eventType == AttentionEventType.trustReceivedChanged)
            .toList();
        expect(given, hasLength(3));
        expect(received, hasLength(3));

        for (final pair in reviewFinalization.result.pairs) {
          expect(
            given.singleWhere(
              (intent) =>
                  intent.recipients.single.recipientId == pair.evaluatorId &&
                  intent.actorUserId == pair.evaluatedUserId,
            ).eventType,
            AttentionEventType.trustGivenChanged,
          );
          expect(
            received.singleWhere(
              (intent) =>
                  intent.recipients.single.recipientId == pair.evaluatedUserId &&
                  intent.actorUserId == pair.evaluatorId,
            ).eventType,
            AttentionEventType.trustReceivedChanged,
          );
        }
      },
    );

    test('skips trust intents for noEffect finalized pairs', () async {
      evalRepo.reviewStatusesResult = {
        userId: 2,
        helperId: 2,
      };
      reviewFinalization.result = ReviewFinalizationResult(
        didClose: true,
        beaconTitle: 'Neutral review',
        pairs: [
          const FinalizedTrustPair(
            evaluatorId: userId,
            evaluatedUserId: helperId,
            bin: TrustBin.noEffect,
          ),
        ],
      );

      await evaluationCase.closeNow(beaconId: beaconId, userId: userId);

      expect(
        attention.recorded.where(
          (i) => i.eventType == AttentionEventType.trustGivenChanged,
        ),
        isEmpty,
      );
      expect(
        attention.recorded.where(
          (i) => i.eventType == AttentionEventType.trustReceivedChanged,
        ),
        isEmpty,
      );
      expect(
        attention.recorded.where(
          (i) => i.eventType == AttentionEventType.requestStatusChanged,
        ),
        hasLength(1),
      );
    });

    test('records trust intents for each non-neutral pair in a mixed close', () async {
      evalRepo.reviewStatusesResult = {
        userId: 2,
        helperId: 2,
      };
      reviewFinalization.result = ReviewFinalizationResult(
        didClose: true,
        beaconTitle: 'Mixed trust close',
        pairs: [
          const FinalizedTrustPair(
            evaluatorId: userId,
            evaluatedUserId: helperId,
            bin: TrustBin.good,
          ),
          const FinalizedTrustPair(
            evaluatorId: helperId,
            evaluatedUserId: userId,
            bin: TrustBin.veryBad,
          ),
          const FinalizedTrustPair(
            evaluatorId: userId,
            evaluatedUserId: helperId,
            bin: TrustBin.noEffect,
          ),
        ],
      );

      await evaluationCase.closeNow(beaconId: beaconId, userId: userId);

      final given = attention.recorded
          .where((i) => i.eventType == AttentionEventType.trustGivenChanged)
          .toList();
      final received = attention.recorded
          .where((i) => i.eventType == AttentionEventType.trustReceivedChanged)
          .toList();
      expect(given, hasLength(2));
      expect(received, hasLength(2));

      expect(
        given.map((intent) => intent.recipients.single.recipientId).toSet(),
        {userId, helperId},
      );
      expect(
        received.map((intent) => intent.recipients.single.recipientId).toSet(),
        {userId, helperId},
      );
      expect(
        given.singleWhere(
          (intent) => intent.recipients.single.recipientId == userId,
        ).eventType,
        AttentionEventType.trustGivenChanged,
      );
      expect(
        received.singleWhere(
          (intent) => intent.recipients.single.recipientId == userId,
        ).eventType,
        AttentionEventType.trustReceivedChanged,
      );
    });
  });

  group('reviewWindowStatuses', () {
    test('empty list returns empty', () async {
      final rows = await evaluationCase.reviewWindowStatuses(
        beaconIds: const [],
        userId: userId,
      );
      expect(rows, isEmpty);
    });

    test('returns canCloseNow for accessible reviewOpen beacon', () async {
      final localEvalRepo = _FakeEvaluationRepository()
        ..reviewWindowResult = openWindow()
        ..reviewStatusesResult = {userId: 2, 'helper1': 2}
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: userId,
            role: 0,
            contributionSummary: 'author',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: 'helper1',
            role: 1,
            contributionSummary: 'helper',
            causalHint: 'h',
          ),
        ];
      final localCase = buildTestEvaluationCase(
        beaconRepo: _TransactionStubBeaconRepo(
          BeaconEntity(
            id: beaconId,
            title: 't',
            author: UserEntity(id: userId),
            createdAt: DateTime.timestamp(),
            updatedAt: DateTime.timestamp(),
            status: BeaconStatus.reviewOpen,
          ),
        ),
        forwardRepo: EmptyGraphForwardEdgeRepository(),
        evalRepo: localEvalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: EvaluationParticipantGraphBuilder(
          NoOpCommitmentRepository(),
          EmptyGraphHelpOfferRepository(),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        ),
        attention: attention,
        expirySweep: expirySweep,
      );
      final rows = await localCase.reviewWindowStatuses(
        beaconIds: [beaconId],
        userId: userId,
      );
      expect(rows, hasLength(1));
      expect(rows.single.beaconId, beaconId);
      expect(rows.single.canCloseNow, isTrue);
    });

    test('returns canReopen false when reopen cap exhausted', () async {
      final localEvalRepo = _FakeEvaluationRepository()
        ..reviewWindowResult = openWindow();
      final localCase = buildTestEvaluationCase(
        beaconRepo: _TransactionStubBeaconRepo(
          defaultReviewBeacon(),
          reviewReopenCount: 1,
        ),
        forwardRepo: EmptyGraphForwardEdgeRepository(),
        evalRepo: localEvalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: EvaluationParticipantGraphBuilder(
          NoOpCommitmentRepository(),
          EmptyGraphHelpOfferRepository(),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        ),
        attention: attention,
        expirySweep: expirySweep,
      );

      final status = await localCase.reviewWindowStatus(
        beaconId: beaconId,
        userId: userId,
      );

      expect(status.canReopen, isFalse);
    });
  });

  group('evaluation participant acknowledgement contract', () {
    BeaconEvaluationRecord row({
      required int status,
      List<String> ackTags = const [],
    }) => BeaconEvaluationRecord(
      beaconId: beaconId,
      evaluatorId: 'evaluator',
      evaluatedUserId: 'subject',
      value: BeaconEvaluationValue.pos1,
      reasonTags: '',
      ackTags: ackTags,
      note: 'note',
      status: status,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    EvaluationCase localCase({
      required int evaluatorRole,
      required BeaconEvaluationRecord evaluation,
    }) {
      final localRepo = _FakeEvaluationRepository()
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = 1
        ..participantsResult = [
          BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: 'evaluator',
            role: evaluatorRole,
            contributionSummary: 'evaluator',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: 'subject',
            role: 1,
            contributionSummary: 'subject',
            causalHint: 'h',
          ),
        ]
        ..visibilityResult = [
          const BeaconEvaluationVisibilityRecord(
            beaconId: beaconId,
            evaluatorId: 'evaluator',
            participantId: 'subject',
          ),
        ]
        ..listEvaluationsForEvaluatorResult = [evaluation];
      return buildTestEvaluationCase(
        beaconRepo: _StubBeaconRepository(
          BeaconEntity(
            id: beaconId,
            title: 't',
            author: const UserEntity(id: userId),
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            status: BeaconStatus.reviewOpen,
            needs: const {'current'},
          ),
        ),
        forwardRepo: EmptyGraphForwardEdgeRepository(),
        evalRepo: localRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: EvaluationParticipantGraphBuilder(
          NoOpCommitmentRepository(),
          EmptyGraphHelpOfferRepository(),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        ),
        attention: attention,
        expirySweep: expirySweep,
      );
    }

    test(
      'eligible participant exposes saved, current, grandfathered, cap and status',
      () async {
        final result =
            await localCase(
              evaluatorRole: EvaluationParticipantRole.author.dbValue,
              evaluation: row(
                status: BeaconEvaluationRowStatus.submitted,
                ackTags: const ['legacy'],
              ),
            ).evaluationParticipants(
              beaconId: beaconId,
              evaluatorId: 'evaluator',
            );
        final participant = result.single;
        expect(participant.acknowledgedHelpTags, ['legacy']);
        expect(participant.acknowledgeableHelpTags, ['current', 'legacy']);
        expect(participant.maxAcknowledgedHelpTags, 3);
        expect(participant.isSubmitted, isTrue);
      },
    );

    test(
      'ineligible participant receives empty acknowledgement surface and cap zero',
      () async {
        final result =
            await localCase(
              evaluatorRole: EvaluationParticipantRole.forwarder.dbValue,
              evaluation: row(
                status: BeaconEvaluationRowStatus.submitted,
                ackTags: const ['legacy'],
              ),
            ).evaluationParticipants(
              beaconId: beaconId,
              evaluatorId: 'evaluator',
            );
        final participant = result.single;
        expect(participant.acknowledgedHelpTags, isEmpty);
        expect(participant.acknowledgeableHelpTags, isEmpty);
        expect(participant.maxAcknowledgedHelpTags, 0);
      },
    );

    test(
      'draft participant is ready (isSubmitted) without persisted acknowledgements',
      () async {
        final result =
            await localCase(
              evaluatorRole: EvaluationParticipantRole.author.dbValue,
              evaluation: row(status: BeaconEvaluationRowStatus.draft),
            ).evaluationParticipants(
              beaconId: beaconId,
              evaluatorId: 'evaluator',
            );
        final participant = result.single;
        expect(participant.isSubmitted, isTrue);
        expect(participant.acknowledgedHelpTags, isEmpty);
      },
    );
  });

  group('causal draft, submission, finalization and receipt', () {
    test(
      'promotes one no-basis draft and reveals only to the evaluated user',
      () async {
        const evaluatedUserId = 'helper1';
        const unrelatedUserId = 'unrelated';
        final now = DateTime.utc(2026, 1, 1);
        final beaconRepo = _CausalBeaconRepository(
          BeaconEntity(
            id: beaconId,
            title: 'Causal request',
            author: const UserEntity(id: userId),
            createdAt: now,
            updatedAt: now,
            status: BeaconStatus.open,
          ),
        );
        final evalRepo = _CausalEvaluationRepository()
          ..reviewWindowResult = openWindow()
          ..reviewUserStatusResult = 1
          ..reviewStatusesResult = {userId: 2, evaluatedUserId: 2}
          ..visibilityResult = [
            const BeaconEvaluationVisibilityRecord(
              beaconId: beaconId,
              evaluatorId: userId,
              participantId: evaluatedUserId,
            ),
          ]
          ..participantsResult = [
            const BeaconEvaluationParticipantRecord(
              beaconId: beaconId,
              userId: userId,
              role: 0,
              contributionSummary: 'author',
              causalHint: 'h',
            ),
            const BeaconEvaluationParticipantRecord(
              beaconId: beaconId,
              userId: evaluatedUserId,
              role: 1,
              contributionSummary: 'helper',
              causalHint: 'h',
            ),
          ];
        final offers = _SingleCommitterHelpOfferRepo(
          HelpOfferEntity(
            beaconId: beaconId,
            userId: evaluatedUserId,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final commitment = acknowledgedCommitterCommitmentRepo(
          beaconId: beaconId,
          helperId: evaluatedUserId,
          authorId: userId,
          baseTime: now,
        );
        final forwardRepo = EmptyGraphForwardEdgeRepository();
        final attention = TestAttentionHarness();
        final expirySweep = AttentionExpirySweepCase(
          _NoopAttentionExpiryRepository(),
          _FakeReviewFinalization(),
          attention.intents,
          attention.transactional,
        );
        final evaluationCase = buildTestEvaluationCase(
          beaconRepo: beaconRepo,
          forwardRepo: forwardRepo,
          evalRepo: evalRepo,
          userProfileBatchLookup: StubUserProfileBatchLookup('User'),
          graphBuilder: EvaluationParticipantGraphBuilder(
            commitment,
            offers,
            forwardRepo,
            StubUserRepository('User'),
          ),
          attention: attention,
          expirySweep: expirySweep,
          commitmentRepo: commitment,
          helpOfferRepo: offers,
          reviewFinalization: _CausalReviewFinalization(evalRepo, beaconRepo),
        );

        await evaluationCase.evaluationDraftSave(
          beaconId: beaconId,
          evaluatorId: userId,
          evaluatedUserId: evaluatedUserId,
          value: BeaconEvaluationValue.noBasis,
          note: 'draft no basis',
        );
        beaconRepo.current = beaconRepo.current.copyWith(
          status: BeaconStatus.reviewOpen,
        );
        final draft = (await evaluationCase.evaluationParticipants(
          beaconId: beaconId,
          evaluatorId: userId,
        )).single;
        expect(draft.isSubmitted, isTrue);
        expect(evalRepo.rows.values.single.status, BeaconEvaluationRowStatus.draft);

        await evaluationCase.evaluationSubmit(
          beaconId: beaconId,
          evaluatorId: userId,
          evaluatedUserId: evaluatedUserId,
          value: BeaconEvaluationValue.noBasis,
          note: 'submitted no basis',
        );
        final submitted = (await evaluationCase.evaluationParticipants(
          beaconId: beaconId,
          evaluatorId: userId,
        )).single;
        expect(submitted.isSubmitted, isTrue);
        expect(
          evalRepo.rows.values.single.status,
          BeaconEvaluationRowStatus.draft,
        );

        await evaluationCase.closeNow(beaconId: beaconId, userId: userId);
        expect(beaconRepo.current.status, BeaconStatus.closed);
        expect(evalRepo.rows.values.single.status, BeaconEvaluationRowStatus.final_);

        final received = await evaluationCase.evaluationReceived(
          beaconId: beaconId,
          userId: evaluatedUserId,
        );
        expect(received.windowClosed, isTrue);
        expect(received.rows, hasLength(1));
        expect(received.rows.single.value, BeaconEvaluationValue.noBasis);
        final unrelated = await evaluationCase.evaluationReceived(
          beaconId: beaconId,
          userId: unrelatedUserId,
        );
        expect(unrelated.rows, isEmpty);
      },
    );
  });

  group('evaluationReceived', () {
    late _TransactionStubBeaconRepo beaconRepo;
    const reviewerId = 'reviewer1';
    const evaluatedId = 'evaluated1';

    EvaluationCase buildCase() {
      final forwardRepo = EmptyGraphForwardEdgeRepository();
      final helpOfferRepo = EmptyGraphHelpOfferRepository();
      final graphBuilder = EvaluationParticipantGraphBuilder(
        NoOpCommitmentRepository(),
        helpOfferRepo,
        forwardRepo,
        StubUserRepository('User'),
      );
      return buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('Reviewer'),
        graphBuilder: graphBuilder,
        attention: attention,
        expirySweep: expirySweep,
        helpOfferRepo: helpOfferRepo,
        reviewFinalization: reviewFinalization,
      );
    }

    BeaconEvaluationRecord evaluationRow({
      required int value,
      int status = BeaconEvaluationRowStatus.final_,
      List<String> ackTags = const [],
    }) {
      final now = DateTime.utc(2026, 3, 1);
      return BeaconEvaluationRecord(
        beaconId: beaconId,
        evaluatorId: reviewerId,
        evaluatedUserId: evaluatedId,
        value: value,
        reasonTags: 'tag_a',
        ackTags: ackTags,
        note: 'note',
        status: status,
        createdAt: now,
        updatedAt: now,
      );
    }

    setUp(() {
      evalRepo = _FakeEvaluationRepository();
      beaconRepo = _TransactionStubBeaconRepo(
        BeaconEntity(
          id: beaconId,
          title: 'Request title',
          author: UserEntity(id: 'author1'),
          createdAt: DateTime.timestamp(),
          updatedAt: DateTime.timestamp(),
          status: BeaconStatus.closed,
        ),
      );
      evaluationCase = buildCase();
    });

    test('returns windowClosed false while review window open', () async {
      beaconRepo = _TransactionStubBeaconRepo(
        BeaconEntity(
          id: beaconId,
          title: 'Request title',
          author: UserEntity(id: 'author1'),
          createdAt: DateTime.timestamp(),
          updatedAt: DateTime.timestamp(),
          status: BeaconStatus.reviewOpen,
        ),
      );
      evaluationCase = buildCase();

      final result = await evaluationCase.evaluationReceived(
        beaconId: beaconId,
        userId: evaluatedId,
      );

      expect(result.windowClosed, isFalse);
      expect(result.rows, isEmpty);
      expect(result.beaconTitle, 'Request title');
    });

    test('returns named rows with reviewer role and tone when closed', () async {
      evalRepo
        ..listEvaluationsForEvaluatedUserResult = [
          evaluationRow(
            value: BeaconEvaluationValue.pos1,
            ackTags: const ['transport'],
          ),
        ]
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: reviewerId,
            role: 2,
            contributionSummary: 'forwarder',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: evaluatedId,
            role: 1,
            contributionSummary: 'committer',
            causalHint: 'h',
          ),
        ];

      final result = await evaluationCase.evaluationReceived(
        beaconId: beaconId,
        userId: evaluatedId,
      );

      expect(result.windowClosed, isTrue);
      expect(result.rows, hasLength(1));
      final row = result.rows.single;
      expect(row.reviewerId, reviewerId);
      expect(row.reviewerDisplayName, 'Reviewer');
      expect(row.reviewerRole, EvaluationParticipantRole.forwarder);
      expect(row.tone, EvaluationReceivedTrustTone.up);
      expect(row.reasonTags, ['tag_a']);
      expect(row.acknowledgedHelpTags, ['transport']);
      expect(row.note, 'note');
    });

    test('returns row when author reviewed committer', () async {
      const authorId = 'author1';
      const committerId = 'committer1';
      evalRepo
        ..listEvaluationsForEvaluatedUserResult = [
          BeaconEvaluationRecord(
            beaconId: beaconId,
            evaluatorId: authorId,
            evaluatedUserId: committerId,
            value: BeaconEvaluationValue.pos1,
            reasonTags: 'tag_a',
            note: 'note',
            status: BeaconEvaluationRowStatus.final_,
            createdAt: DateTime.utc(2026, 3, 1),
            updatedAt: DateTime.utc(2026, 3, 1),
          ),
        ]
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: authorId,
            role: 0,
            contributionSummary: 'author',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: committerId,
            role: 1,
            contributionSummary: 'committer',
            causalHint: 'h',
          ),
        ];

      final result = await evaluationCase.evaluationReceived(
        beaconId: beaconId,
        userId: committerId,
      );

      expect(result.rows, hasLength(1));
      final row = result.rows.single;
      expect(row.reviewerId, authorId);
      expect(row.reviewerRole, EvaluationParticipantRole.author);
      expect(row.tone, EvaluationReceivedTrustTone.up);
    });

    test('returns row when committer reviewed author', () async {
      const authorId = 'author1';
      const committerId = 'committer1';
      evalRepo
        ..listEvaluationsForEvaluatedUserResult = [
          BeaconEvaluationRecord(
            beaconId: beaconId,
            evaluatorId: committerId,
            evaluatedUserId: authorId,
            value: BeaconEvaluationValue.neg1,
            reasonTags: 'tag_a',
            note: 'note',
            status: BeaconEvaluationRowStatus.final_,
            createdAt: DateTime.utc(2026, 3, 1),
            updatedAt: DateTime.utc(2026, 3, 1),
          ),
        ]
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: authorId,
            role: 0,
            contributionSummary: 'author',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: committerId,
            role: 1,
            contributionSummary: 'committer',
            causalHint: 'h',
          ),
        ];

      final result = await evaluationCase.evaluationReceived(
        beaconId: beaconId,
        userId: authorId,
      );

      expect(result.rows, hasLength(1));
      final row = result.rows.single;
      expect(row.reviewerId, committerId);
      expect(row.reviewerRole, EvaluationParticipantRole.committer);
      expect(row.tone, EvaluationReceivedTrustTone.down);
    });

    test('includes noBasis rows with distinct tone', () async {
      evalRepo
        ..listEvaluationsForEvaluatedUserResult = [
          evaluationRow(value: BeaconEvaluationValue.noBasis),
        ]
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: reviewerId,
            role: 3,
            contributionSummary: 'former',
            causalHint: 'h',
          ),
        ];

      final result = await evaluationCase.evaluationReceived(
        beaconId: beaconId,
        userId: evaluatedId,
      );

      expect(result.rows.single.tone, EvaluationReceivedTrustTone.noBasis);
      expect(
        result.rows.single.reviewerRole,
        EvaluationParticipantRole.formerCommitter,
      );
    });

    test('evaluationSummary adapter is not suppressed for one reviewer', () async {
      evalRepo
        ..listEvaluationsForEvaluatedUserResult = [
          evaluationRow(value: BeaconEvaluationValue.pos2),
        ]
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: reviewerId,
            role: 0,
            contributionSummary: 'author',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: evaluatedId,
            role: 1,
            contributionSummary: 'committer',
            causalHint: 'h',
          ),
        ];

      final summary = await evaluationCase.evaluationSummary(
        beaconId: beaconId,
        userId: evaluatedId,
      );

      expect(summary.suppressed, isFalse);
      expect(summary.pos2, 1);
    });
  });

  group('evaluationsWrittenAboutMeBy', () {
    const authorId = 'author-reviewer';
    const viewerId = 'viewer-evaluated';
    final occurredAt = DateTime.utc(2026, 4, 1, 12);

    CrossBeaconEvaluationRecord crossBeaconRow({
      required int value,
      List<String> ackTags = const [],
    }) =>
        CrossBeaconEvaluationRecord(
          evaluatorId: authorId,
          evaluatedUserId: viewerId,
          value: value,
          reasonTags: 'reliable,on_time',
          ackTags: ackTags,
          note: 'Great help',
          occurredAt: occurredAt,
          beaconId: 'beacon-cross-1',
          beaconTitle: 'Move help this weekend',
          beaconClosedAt: DateTime.utc(2026, 3, 31),
        );

    setUp(() {
      evalRepo = _FakeEvaluationRepository();
      evaluationCase = buildTestEvaluationCase(
        beaconRepo: _TransactionStubBeaconRepo(
          BeaconEntity(
            id: beaconId,
            title: 'unused',
            author: UserEntity(id: 'author1'),
            createdAt: DateTime.timestamp(),
            updatedAt: DateTime.timestamp(),
            status: BeaconStatus.closed,
          ),
        ),
        forwardRepo: EmptyGraphForwardEdgeRepository(),
        evalRepo: evalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: EvaluationParticipantGraphBuilder(
          NoOpCommitmentRepository(),
          EmptyGraphHelpOfferRepository(),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        ),
        attention: attention,
        expirySweep: expirySweep,
        helpOfferRepo: EmptyGraphHelpOfferRepository(),
        reviewFinalization: reviewFinalization,
      );
    });

    test('returns empty when repository has no rows', () async {
      final rows = await evaluationCase.evaluationsWrittenAboutMeBy(
        viewerId: viewerId,
        authorOfReviewsId: authorId,
      );
      expect(rows, isEmpty);
    });

    test('maps finalized rows with trust tone including noBasis', () async {
      evalRepo.listFinalizedEvaluationsBetweenResult = [
        crossBeaconRow(value: BeaconEvaluationValue.pos1, ackTags: const ['transport']),
        crossBeaconRow(value: BeaconEvaluationValue.noBasis),
      ];

      final rows = await evaluationCase.evaluationsWrittenAboutMeBy(
        viewerId: viewerId,
        authorOfReviewsId: authorId,
      );

      expect(rows, hasLength(2));
      expect(rows[0].beaconTitle, 'Move help this weekend');
      expect(rows[0].tone, EvaluationReceivedTrustTone.up);
      expect(rows[0].reasonTags, ['reliable', 'on_time']);
      expect(rows[0].acknowledgedHelpTags, ['transport']);
      expect(rows[1].tone, EvaluationReceivedTrustTone.noBasis);
    });

    test('scopes query to author and viewer pair', () async {
      evalRepo.listFinalizedEvaluationsBetweenResult = [
        crossBeaconRow(value: BeaconEvaluationValue.pos1),
        CrossBeaconEvaluationRecord(
          evaluatorId: 'other-author',
          evaluatedUserId: viewerId,
          value: BeaconEvaluationValue.neg1,
          reasonTags: '',
          note: '',
          occurredAt: occurredAt,
          beaconId: 'beacon-other',
          beaconTitle: 'Other',
          beaconClosedAt: null,
        ),
      ];

      final rows = await evaluationCase.evaluationsWrittenAboutMeBy(
        viewerId: viewerId,
        authorOfReviewsId: authorId,
      );

      expect(rows, hasLength(1));
      expect(rows.single.evaluatorId, authorId);
      expect(rows.single.evaluatedUserId, viewerId);
    });
  });

  group('closeNow idempotency', () {
    test('second closeNow throws after window already finalized', () async {
      var beacon = BeaconEntity(
        id: beaconId,
        title: 't',
        author: UserEntity(id: userId),
        createdAt: DateTime.timestamp(),
        updatedAt: DateTime.timestamp(),
        status: BeaconStatus.reviewOpen,
      );
      final beaconRepo = _MutableTransactionStubBeaconRepo(() => beacon);
      final localEvalRepo = _FakeEvaluationRepository()
        ..reviewWindowResult = openWindow()
        ..reviewStatusesResult = {userId: 2, 'helper1': 2}
        ..participantsResult = [
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: userId,
            role: 0,
            contributionSummary: 'author',
            causalHint: 'h',
          ),
          const BeaconEvaluationParticipantRecord(
            beaconId: beaconId,
            userId: 'helper1',
            role: 1,
            contributionSummary: 'helper',
            causalHint: 'h',
          ),
        ];
      final localReviewFinalization = _FakeReviewFinalization();
      final localCase = buildTestEvaluationCase(
        beaconRepo: beaconRepo,
        forwardRepo: EmptyGraphForwardEdgeRepository(),
        evalRepo: localEvalRepo,
        userProfileBatchLookup: StubUserProfileBatchLookup('User'),
        graphBuilder: EvaluationParticipantGraphBuilder(
          NoOpCommitmentRepository(),
          EmptyGraphHelpOfferRepository(),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        ),
        attention: attention,
        expirySweep: expirySweep,
        reviewFinalization: localReviewFinalization,
      );

      await localCase.closeNow(beaconId: beaconId, userId: userId);
      expect(localReviewFinalization.closeAndFinalizeCalls, hasLength(1));
      beacon = beacon.copyWith(status: BeaconStatus.closed);

      await expectLater(
        () => localCase.closeNow(beaconId: beaconId, userId: userId),
        throwsA(isA<EvaluationException>()),
      );
      expect(localReviewFinalization.closeAndFinalizeCalls, hasLength(1));
    });
  });
}

final class _SingleCommitterHelpOfferRepo implements HelpOfferRepositoryPort {
  _SingleCommitterHelpOfferRepo(this._offer);

  final HelpOfferEntity _offer;

  @override
  Future<List<HelpOfferEntity>> fetchByBeaconId(String beaconId) async => [
    _offer,
  ];

  @override
  Future<void> upsert({
    required String beaconId,
    required String userId,
    String message = '',
    List<String>? helpTypes,
    int status = 0,
    int offerKind = 0,
  }) => throw UnimplementedError();

  @override
  Future<void> withdraw({
    required String beaconId,
    required String userId,
    required String withdrawReason,
    String message = '',
  }) => throw UnimplementedError();

  @override
  Future<List<HelpOfferEntity>> fetchAllByBeaconId(String beaconId) async => [
    _offer,
  ];

  @override
  Future<List<HelpOfferEntity>> fetchByUserId(String userId) =>
      throw UnimplementedError();

  @override
  Future<bool> hasActiveHelpOffer({
    required String beaconId,
    required String userId,
  }) => throw UnimplementedError();

  @override
  Future<List<String>> fetchActiveHelpTypes({
    required String beaconId,
    required String userId,
  }) async {
    if (_offer.beaconId != beaconId ||
        _offer.userId != userId ||
        !_offer.isActive) {
      return const [];
    }
    final raw = _offer.helpType;
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    return [raw];
  }
}
