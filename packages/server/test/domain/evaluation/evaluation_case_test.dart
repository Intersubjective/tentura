import 'package:drift_postgres/drift_postgres.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/evaluation_repository.dart';
import 'package:tentura_server/data/repository/fcm_remote_repository.dart';
import 'package:tentura_server/data/repository/fcm_token_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/evaluation_case.dart';

class MockBeaconRepository extends Mock implements BeaconRepository {}

class MockCommitmentRepository extends Mock implements CommitmentRepository {}

class MockForwardEdgeRepository extends Mock implements ForwardEdgeRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockFcmRemoteRepository extends Mock implements FcmRemoteRepository {}

class MockFcmTokenRepository extends Mock implements FcmTokenRepository {}

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
class _FakeEvaluationRepository implements EvaluationRepository {
  _FakeEvaluationRepository();

  BeaconReviewWindow? reviewWindowResult;
  int? reviewUserStatusResult;
  List<BeaconEvaluationParticipant> participantsResult = [];
  List<BeaconEvaluationVisibilityData> visibilityResult = [];
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
  Future<BeaconEvaluation?> getEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) async =>
      null;

  @override
  Future<BeaconReviewWindow?> getReviewWindow(String beaconId) async =>
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
  Future<List<BeaconEvaluation>> listEvaluationsForEvaluatedUser({
    required String beaconId,
    required String evaluatedUserId,
  }) async =>
      [];

  @override
  Future<List<BeaconEvaluationParticipant>> listParticipants(
    String beaconId,
  ) async =>
      participantsResult;

  @override
  Future<List<BeaconEvaluationVisibilityData>> listVisibilityForEvaluator(
    String beaconId,
    String evaluatorId,
  ) async =>
      visibilityResult;

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
  }) async {}
}

void main() {
  const beaconId = 'beacon1';
  const userId = 'user1';

  late _FakeEvaluationRepository evalRepo;
  late EvaluationCase evaluationCase;

  BeaconReviewWindow openWindow({
    String id = beaconId,
    DateTime? closesAt,
  }) {
    final now = DateTime.timestamp();
    return BeaconReviewWindow(
      beaconId: id,
      openedAt: PgDateTime(now.subtract(const Duration(hours: 1))),
      closesAt: PgDateTime(closesAt ?? now.add(const Duration(days: 7))),
      status: 0,
      createdAt: PgDateTime(now),
      updatedAt: PgDateTime(now),
    );
  }

  setUp(() {
    evalRepo = _FakeEvaluationRepository();
    evaluationCase = EvaluationCase(
      MockBeaconRepository(),
      MockCommitmentRepository(),
      MockForwardEdgeRepository(),
      evalRepo,
      MockUserRepository(),
      MockFcmRemoteRepository(),
      MockFcmTokenRepository(),
    );
  });

  group('evaluationFinalize', () {
    test('returns true without updating status when already finalized (2)', () async {
      evalRepo.reviewWindowResult = openWindow();
      evalRepo.reviewUserStatusResult = 2;

      expect(await evaluationCase.evaluationFinalize(beaconId: beaconId, userId: userId), isTrue);
      expect(evalRepo.setReviewUserStatusCalls, isEmpty);
    });

    test('returns true without updating status when user skipped (3)', () async {
      evalRepo.reviewWindowResult = openWindow();
      evalRepo.reviewUserStatusResult = 3;

      expect(await evaluationCase.evaluationFinalize(beaconId: beaconId, userId: userId), isTrue);
      expect(evalRepo.setReviewUserStatusCalls, isEmpty);
    });

    test('sets status to 2 when user was in progress (1)', () async {
      evalRepo.reviewWindowResult = openWindow();
      evalRepo.reviewUserStatusResult = 1;

      expect(await evaluationCase.evaluationFinalize(beaconId: beaconId, userId: userId), isTrue);
      expect(
        evalRepo.setReviewUserStatusCalls,
        const [_SetStatusCall(beaconId, userId, 2)],
      );
    });

    test('sets status to 2 when user never saved a rating (0)', () async {
      evalRepo.reviewWindowResult = openWindow();
      evalRepo.reviewUserStatusResult = 0;

      expect(await evaluationCase.evaluationFinalize(beaconId: beaconId, userId: userId), isTrue);
      expect(
        evalRepo.setReviewUserStatusCalls,
        const [_SetStatusCall(beaconId, userId, 2)],
      );
    });

    test('throws notEligible when user has no review row', () async {
      evalRepo.reviewWindowResult = openWindow();
      evalRepo.reviewUserStatusResult = null;

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
      evalRepo.reviewWindowResult = BeaconReviewWindow(
        beaconId: beaconId,
        openedAt: PgDateTime(now.subtract(const Duration(days: 8))),
        closesAt: PgDateTime(now.subtract(const Duration(days: 1))),
        status: 1,
        createdAt: PgDateTime(now.subtract(const Duration(days: 8))),
        updatedAt: PgDateTime(now),
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
      evalRepo.reviewWindowResult = openWindow(
        closesAt: now.subtract(const Duration(days: 1)),
      );
      evalRepo.visibilityResult = [
        BeaconEvaluationVisibilityData(
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

      evalRepo.reviewWindowResult = openWindow();
      evalRepo.reviewUserStatusResult = 0;
      evalRepo.visibilityResult = [
        BeaconEvaluationVisibilityData(
          beaconId: beaconId,
          evaluatorId: evaluatorId,
          participantId: evaluatedId,
        ),
      ];
      evalRepo.participantsResult = [
        BeaconEvaluationParticipant(
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

      evalRepo.reviewWindowResult = openWindow();
      evalRepo.reviewUserStatusResult = 1;
      evalRepo.visibilityResult = [
        BeaconEvaluationVisibilityData(
          beaconId: beaconId,
          evaluatorId: evaluatorId,
          participantId: evaluatedId,
        ),
      ];
      evalRepo.participantsResult = [
        BeaconEvaluationParticipant(
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
}
