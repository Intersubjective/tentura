import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/person_capability_event_repository_port.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_draft_purger.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_participant_graph_builder.dart';
import 'package:tentura_server/domain/use_case/evaluation_case.dart';

import 'evaluation_graph_test_repos.dart';

/// No-op stub for [PersonCapabilityEventRepositoryPort] used only to construct
/// a [CapabilityCase] in evaluation unit tests.
class _NoopCapabilityEventRepo implements PersonCapabilityEventRepositoryPort {
  @override
  Future<void> upsertPrivateLabels({
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) async {}

  @override
  Future<List<String>> fetchPrivateLabels({
    required String observerId,
    required String subjectId,
  }) async => [];

  @override
  Future<void> insertForwardReasons({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required List<String> slugs,
    String note = '',
  }) async {}

  @override
  Future<void> insertCommitRole({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required String slug,
  }) async {}

  @override
  Future<void> insertCloseAcknowledgements({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required List<String> slugs,
  }) async {}

  @override
  Future<PersonCapabilityCuesRow> fetchCues({
    required String viewerId,
    required String subjectId,
  }) async => const PersonCapabilityCuesRow(
    privateLabels: [],
    forwardReasonsByMe: [],
    commitRoles: [],
    closeAckByMe: [],
    closeAckAboutMe: [],
  );

  @override
  Future<void> insertTombstone({
    required String observerId,
    required String subjectId,
    required String slug,
  }) async {}

  @override
  Future<void> deleteTombstone({
    required String observerId,
    required String subjectId,
    required String slug,
  }) async {}

  @override
  Future<List<ViewerVisibleCapabilityRow>> fetchDeduplicatedCapabilities({
    required String viewerId,
    required String subjectId,
  }) async => [];
}

class MockBeaconRepository extends Mock implements BeaconRepositoryPort {}

class MockFcmRemoteRepository extends Mock implements FcmRemoteRepositoryPort {}

class MockFcmTokenRepository extends Mock implements FcmTokenRepositoryPort {}

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

/// Configurable fake for [EvaluationCase] unit tests.
class _FakeEvaluationRepository implements EvaluationRepositoryPort {
  _FakeEvaluationRepository();

  BeaconReviewWindowRecord? reviewWindowResult;
  int? reviewUserStatusResult;
  List<BeaconEvaluationParticipantRecord> participantsResult = [];
  List<BeaconEvaluationVisibilityRecord> visibilityResult = [];
  List<BeaconEvaluationRecord> listEvaluationsForEvaluatorResult = [];
  final List<_SetStatusCall> setReviewUserStatusCalls = [];

  @override
  Future<void> closeExpiredWindows() async {}

  @override
  Future<int> countDistinctEvaluatorsForEvaluated({
    required String beaconId,
    required String evaluatedUserId,
  }) async =>
      0;

  @override
  Future<BeaconEvaluationRecord?> getEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) async =>
      null;

  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluator({
    required String beaconId,
    required String evaluatorId,
  }) async =>
      listEvaluationsForEvaluatorResult
          .where(
            (e) =>
                e.beaconId == beaconId && e.evaluatorId == evaluatorId,
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
  }) async {}

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
  }) async =>
      [];

  @override
  Future<List<BeaconEvaluationParticipantRecord>> listParticipants(
    String beaconId,
  ) async =>
      participantsResult;

  @override
  Future<List<BeaconEvaluationVisibilityRecord>> listVisibilityForEvaluator(
    String beaconId,
    String evaluatorId,
  ) async =>
      visibilityResult;

  @override
  Future<List<BeaconEvaluationVisibilityRecord>> listAllVisibility(
    String beaconId,
  ) async =>
      visibilityResult;

  @override
  Future<List<BeaconEvaluationRecord>> listDraftRowsForBeacon(
    String beaconId,
  ) async =>
      [];

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
  }) async {}
}

void main() {
  const beaconId = 'beacon1';
  const userId = 'user1';

  late _FakeEvaluationRepository evalRepo;
  late EvaluationCase evaluationCase;

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
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() {
    evalRepo = _FakeEvaluationRepository();
    final commitmentRepo = EmptyGraphCommitmentRepository();
    final forwardRepo = EmptyGraphForwardEdgeRepository();
    final userRepo = StubUserRepository('User');

    final graphBuilder = EvaluationParticipantGraphBuilder(
      commitmentRepo,
      forwardRepo,
      userRepo,
    );
    final draftPurger = EvaluationDraftPurger(evalRepo);

    final noopCapabilityCase = CapabilityCase(
      _NoopCapabilityEventRepo(),
      env: Env(environment: Environment.test),
      logger: Logger('EvaluationCaseTest'),
    );

    evaluationCase = EvaluationCase(
      MockBeaconRepository(),
      forwardRepo,
      evalRepo,
      userRepo,
      MockFcmRemoteRepository(),
      MockFcmTokenRepository(),
      graphBuilder,
      draftPurger,
      noopCapabilityCase,
      env: Env(environment: Environment.test),
      logger: Logger('EvaluationCaseTest'),
    );
  });

  group('evaluationFinalize', () {
    test('returns true without updating status when already finalized (2)', () async {
      evalRepo
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = 2;

      expect(await evaluationCase.evaluationFinalize(beaconId: beaconId, userId: userId), isTrue);
      expect(evalRepo.setReviewUserStatusCalls, isEmpty);
    });

    test('returns true without updating status when user skipped (3)', () async {
      evalRepo
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = 3;

      expect(await evaluationCase.evaluationFinalize(beaconId: beaconId, userId: userId), isTrue);
      expect(evalRepo.setReviewUserStatusCalls, isEmpty);
    });

    test('sets status to 2 when user was in progress (1)', () async {
      evalRepo
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = 1;

      expect(await evaluationCase.evaluationFinalize(beaconId: beaconId, userId: userId), isTrue);
      expect(
        evalRepo.setReviewUserStatusCalls,
        const [_SetStatusCall(beaconId, userId, 2)],
      );
    });

    test('sets status to 2 when user never saved a rating (0)', () async {
      evalRepo
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = 0;

      expect(await evaluationCase.evaluationFinalize(beaconId: beaconId, userId: userId), isTrue);
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
        () => evaluationCase.evaluationFinalize(beaconId: beaconId, userId: userId),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(EvaluationExceptionCode.notEligible).codeNumber,
          ),
        ),
      );
    });

    test('throws reviewWindowExpired when window is missing', () async {
      evalRepo.reviewWindowResult = null;

      expect(
        () => evaluationCase.evaluationFinalize(beaconId: beaconId, userId: userId),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(EvaluationExceptionCode.reviewWindowExpired).codeNumber,
          ),
        ),
      );
    });

    test('throws reviewWindowExpired when window already closed (status 1)', () async {
      final now = DateTime.timestamp();
      evalRepo.reviewWindowResult = BeaconReviewWindowRecord(
        beaconId: beaconId,
        openedAt: now.subtract(const Duration(days: 8)),
        closesAt: now.subtract(const Duration(days: 1)),
        status: 1,
        createdAt: now.subtract(const Duration(days: 8)),
        updatedAt: now,
      );

      expect(
        () => evaluationCase.evaluationFinalize(beaconId: beaconId, userId: userId),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(EvaluationExceptionCode.reviewWindowExpired).codeNumber,
          ),
        ),
      );
    });

  });

  group('evaluationSubmit', () {
    test('throws reviewWindowExpired when review deadline has passed', () async {
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
            const EvaluationExceptionCodes(EvaluationExceptionCode.reviewWindowExpired).codeNumber,
          ),
        ),
      );
    });

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

    test('does not set review user status when already past first submit (1)', () async {
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
    });
  });

  group('evaluationSkip', () {
    test('throws notEligible when user has no review row', () async {
      evalRepo
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = null;

      expect(
        () => evaluationCase.evaluationSkip(beaconId: beaconId, userId: userId),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(EvaluationExceptionCode.notEligible).codeNumber,
          ),
        ),
      );
    });

    test('sets skipped status when user is eligible', () async {
      evalRepo
        ..reviewWindowResult = openWindow()
        ..reviewUserStatusResult = 0;

      expect(
        await evaluationCase.evaluationSkip(beaconId: beaconId, userId: userId),
        isTrue,
      );
      expect(
        evalRepo.setReviewUserStatusCalls,
        const [_SetStatusCall(beaconId, userId, 3)],
      );
    });
  });
}
