import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/attention_expiry_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';
import 'package:tentura_server/domain/port/person_capability_event_repository_port.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/attention_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_draft_purger.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_participant_graph_builder.dart';
import 'package:tentura_server/domain/use_case/evaluation_case.dart';

import 'evaluation_graph_test_repos.dart';
import '../../support/test_attention_harness.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

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

  @override
  Future<List<ForwardReasonRow>> fetchForwardReasonsByBeaconId({
    required String beaconId,
    required String viewerId,
  }) async => [];

  @override
  Future<Map<String, List<String>>> fetchTopCapabilitiesBatch({
    required String viewerId,
    required List<String> subjectIds,
    int limit = 2,
    List<String> prioritizeSlugs = const [],
  }) async => {};

  @override
  Future<List<FriendContextRow>> fetchFriendContextsBatch({
    required String viewerId,
    required List<String> friendIds,
  }) async => [];
}

class _NoopAttentionExpiryRepository extends Fake
    implements AttentionExpiryRepositoryPort {
  @override
  Future<List<String>> lockExpiredReviewWindowBeaconIds(DateTime now) async =>
      const [];
}

class MockBeaconRepository extends Mock implements BeaconRepositoryPort {}

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
  _TransactionStubBeaconRepo(this.lockedBeacon);

  final BeaconEntity lockedBeacon;
  final statusTransitions = <_StatusTransitionCall>[];

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

/// Configurable fake for [EvaluationCase] unit tests.
class _FakeEvaluationRepository implements EvaluationRepositoryPort {
  _FakeEvaluationRepository();

  BeaconReviewWindowRecord? reviewWindowResult;
  int? reviewUserStatusResult;
  List<BeaconEvaluationParticipantRecord> participantsResult = [];
  List<BeaconEvaluationVisibilityRecord> visibilityResult = [];
  List<BeaconEvaluationRecord> listEvaluationsForEvaluatorResult = [];
  final List<_SetStatusCall> setReviewUserStatusCalls = [];
  int downgradeSubmittedCalls = 0;
  int deleteScaffoldingCalls = 0;
  int insertReviewWindowCalls = 0;
  Map<String, int> reviewStatusesResult = {};
  DateTime extendReviewResult = DateTime.utc(2025, 1, 8);
  final closeBeaconReviewWindowCalls =
      <({String beaconId, String reason, String? actorUserId})>[];

  @override
  Future<void> closeExpiredWindows() async {}

  @override
  Future<int> countDistinctEvaluatorsForEvaluated({
    required String beaconId,
    required String evaluatedUserId,
  }) async => 0;

  @override
  Future<BeaconEvaluationRecord?> getEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) async => null;

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
  }) async => [];

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
  Future<void> closeBeaconReviewWindow(
    String beaconId, {
    required String reason,
    String? actorUserId,
  }) async {
    closeBeaconReviewWindowCalls.add(
      (beaconId: beaconId, reason: reason, actorUserId: actorUserId),
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
  }) async {}
}

void main() {
  const beaconId = 'beacon1';
  const userId = 'user1';

  late _FakeEvaluationRepository evalRepo;
  late EvaluationCase evaluationCase;
  late TestAttentionHarness attention;

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

  setUp(() {
    evalRepo = _FakeEvaluationRepository();
    attention = TestAttentionHarness();
    final helpOfferRepo = EmptyGraphHelpOfferRepository();
    final forwardRepo = EmptyGraphForwardEdgeRepository();
    final userRepo = StubUserRepository('User');
    final userProfileBatchLookup = StubUserProfileBatchLookup('User');

    final graphBuilder = EvaluationParticipantGraphBuilder(
      helpOfferRepo,
      EmptyGraphCoordinationRepository(),
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
      userProfileBatchLookup,
      MockBeaconRoomNotificationPort(),
      graphBuilder,
      draftPurger,
      noopCapabilityCase,
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: Env(environment: Environment.test),
      logger: Logger('EvaluationCaseTest'),
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
      'returns true without updating status when user skipped (3)',
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
        expect(evalRepo.setReviewUserStatusCalls, isEmpty);
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

    test('throws reviewWindowExpired when window is missing', () async {
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
              EvaluationExceptionCode.reviewWindowExpired,
            ).codeNumber,
          ),
        ),
      );
    });

    test(
      'throws reviewWindowExpired when window already closed (status 1)',
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
                EvaluationExceptionCode.reviewWindowExpired,
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
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.notEligible,
            ).codeNumber,
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
        helpOfferRepo,
        EmptyGraphCoordinationRepository(),
        forwardRepo,
        userRepo,
      );
      evaluationCase = EvaluationCase(
        beaconRepo,
        forwardRepo,
        evalRepo,
        userProfileBatchLookup,
        MockBeaconRoomNotificationPort(),
        graphBuilder,
        EvaluationDraftPurger(evalRepo),
        CapabilityCase(
          _NoopCapabilityEventRepo(),
          env: Env(environment: Environment.test),
          logger: Logger('EvaluationCaseTest'),
        ),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: Env(environment: Environment.test),
        logger: Logger('EvaluationCaseTest'),
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
      final coordinationRepo = _SingleCommitterCoordinationRepo(
        CoordinationResponseType.useful.smallintValue,
      );
      final forwardRepo = EmptyGraphForwardEdgeRepository();
      final userRepo = StubUserRepository('User');
      final userProfileBatchLookup = StubUserProfileBatchLookup('User');
      final graphBuilder = EvaluationParticipantGraphBuilder(
        helpOfferRepo,
        coordinationRepo,
        forwardRepo,
        userRepo,
      );
      evaluationCase = EvaluationCase(
        beaconRepo,
        forwardRepo,
        evalRepo,
        userProfileBatchLookup,
        _NoopBeaconRoomNotificationPort(),
        graphBuilder,
        EvaluationDraftPurger(evalRepo),
        CapabilityCase(
          _NoopCapabilityEventRepo(),
          env: Env(environment: Environment.test),
          logger: Logger('EvaluationCaseTest'),
        ),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: Env(environment: Environment.test),
        logger: Logger('EvaluationCaseTest'),
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
        EmptyGraphHelpOfferRepository(),
        EmptyGraphCoordinationRepository(),
        EmptyGraphForwardEdgeRepository(),
        StubUserRepository('User'),
      );
      evaluationCase = EvaluationCase(
        beaconRepo,
        EmptyGraphForwardEdgeRepository(),
        evalRepo,
        StubUserProfileBatchLookup('User'),
        _NoopBeaconRoomNotificationPort(),
        graphBuilder,
        EvaluationDraftPurger(evalRepo),
        CapabilityCase(
          _NoopCapabilityEventRepo(),
          env: Env(environment: Environment.test),
          logger: Logger('EvaluationCaseTest'),
        ),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: Env(environment: Environment.test),
        logger: Logger('EvaluationCaseTest'),
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
    late _RecordingReviewOpenedNotificationPort roomPush;

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
      final graphBuilder = EvaluationParticipantGraphBuilder(
        helpOfferRepo,
        _SingleCommitterCoordinationRepo(
          CoordinationResponseType.useful.smallintValue,
        ),
        EmptyGraphForwardEdgeRepository(),
        StubUserRepository('User'),
      );
      roomPush = _RecordingReviewOpenedNotificationPort();
      evaluationCase = EvaluationCase(
        beaconRepo,
        EmptyGraphForwardEdgeRepository(),
        evalRepo,
        StubUserProfileBatchLookup('User'),
        roomPush,
        graphBuilder,
        EvaluationDraftPurger(evalRepo),
        CapabilityCase(
          _NoopCapabilityEventRepo(),
          env: Env(environment: Environment.test),
          logger: Logger('EvaluationCaseTest'),
        ),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: Env(environment: Environment.test),
        logger: Logger('EvaluationCaseTest'),
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
      expect(attention.recorded, hasLength(1));
      final notification = attention.recorded.single;
      expect(notification.eventType, AttentionEventType.reviewOpened);
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
      final graphBuilder = EvaluationParticipantGraphBuilder(
        helpOfferRepo,
        _SingleCommitterCoordinationRepo(
          CoordinationResponseType.useful.smallintValue,
        ),
        EmptyGraphForwardEdgeRepository(),
        StubUserRepository('User'),
      );
      evaluationCase = EvaluationCase(
        beaconRepo,
        EmptyGraphForwardEdgeRepository(),
        evalRepo,
        StubUserProfileBatchLookup('User'),
        _NoopBeaconRoomNotificationPort(),
        graphBuilder,
        EvaluationDraftPurger(evalRepo),
        CapabilityCase(
          _NoopCapabilityEventRepo(),
          env: Env(environment: Environment.test),
          logger: Logger('EvaluationCaseTest'),
        ),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: Env(environment: Environment.test),
        logger: Logger('EvaluationCaseTest'),
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
          EmptyGraphHelpOfferRepository(),
          EmptyGraphCoordinationRepository(),
          EmptyGraphForwardEdgeRepository(),
          StubUserRepository('User'),
        );
        evaluationCase = EvaluationCase(
          beaconRepo,
          EmptyGraphForwardEdgeRepository(),
          evalRepo,
          StubUserProfileBatchLookup('User'),
          _NoopBeaconRoomNotificationPort(),
          graphBuilder,
          EvaluationDraftPurger(evalRepo),
          CapabilityCase(
            _NoopCapabilityEventRepo(),
            env: Env(environment: Environment.test),
            logger: Logger('EvaluationCaseTest'),
          ),
          attentionIntents: attention.intents,
          attention: attention.transactional,
          env: Env(environment: Environment.test),
          logger: Logger('EvaluationCaseTest'),
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
        evalRepo,
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
        EmptyGraphHelpOfferRepository(),
        EmptyGraphCoordinationRepository(),
        EmptyGraphForwardEdgeRepository(),
        StubUserRepository('User'),
      );
      evaluationCase = EvaluationCase(
        beaconRepo,
        EmptyGraphForwardEdgeRepository(),
        evalRepo,
        StubUserProfileBatchLookup('User'),
        _NoopBeaconRoomNotificationPort(),
        graphBuilder,
        EvaluationDraftPurger(evalRepo),
        CapabilityCase(
          _NoopCapabilityEventRepo(),
          env: Env(environment: Environment.test),
          logger: Logger('EvaluationCaseTest'),
        ),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        attentionExpirySweep: expirySweep,
        env: Env(environment: Environment.test),
        logger: Logger('EvaluationCaseTest'),
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
      final graphBuilder = EvaluationParticipantGraphBuilder(
        EmptyGraphHelpOfferRepository(),
        EmptyGraphCoordinationRepository(),
        EmptyGraphForwardEdgeRepository(),
        StubUserRepository('User'),
      );
      return EvaluationCase(
        beaconRepo,
        EmptyGraphForwardEdgeRepository(),
        evalRepo,
        StubUserProfileBatchLookup('User'),
        _NoopBeaconRoomNotificationPort(),
        graphBuilder,
        EvaluationDraftPurger(evalRepo),
        CapabilityCase(
          _NoopCapabilityEventRepo(),
          env: Env(environment: Environment.test),
          logger: Logger('EvaluationCaseTest'),
        ),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: Env(environment: Environment.test),
        logger: Logger('EvaluationCaseTest'),
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

    test('closes early when required reviewers finished or skipped', () async {
      evalRepo.reviewStatusesResult = {
        userId: 2,
        helperId: 3,
      };

      final result = await evaluationCase.closeNow(
        beaconId: beaconId,
        userId: userId,
      );

      expect(result.status, BeaconStatus.closed.smallintValue);
      expect(evalRepo.closeBeaconReviewWindowCalls, [
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
      expect(evalRepo.closeBeaconReviewWindowCalls, isEmpty);
    });

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
  });
}

class MockBeaconRoomNotificationPort extends Mock
    implements BeaconRoomNotificationPort {}

class _NoopBeaconRoomNotificationPort extends Fake
    implements BeaconRoomNotificationPort {
  @override
  Future<void> notifyReviewOpened({
    required String beaconId,
    required String beaconTitle,
    required Set<String> recipientUserIds,
    required String actorUserId,
  }) async {}
}

class _RecordingReviewOpenedNotificationPort extends Fake
    implements BeaconRoomNotificationPort {
  final calls =
      <
        ({
          String beaconId,
          String beaconTitle,
          Set<String> recipientUserIds,
          String actorUserId,
        })
      >[];

  @override
  Future<void> notifyReviewOpened({
    required String beaconId,
    required String beaconTitle,
    required Set<String> recipientUserIds,
    required String actorUserId,
  }) async {
    calls.add((
      beaconId: beaconId,
      beaconTitle: beaconTitle,
      recipientUserIds: recipientUserIds,
      actorUserId: actorUserId,
    ));
  }
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
  }) => throw UnimplementedError();

  @override
  Future<void> withdraw({
    required String beaconId,
    required String userId,
    required String withdrawReason,
    String message = '',
  }) => throw UnimplementedError();

  @override
  Future<List<HelpOfferEntity>> fetchAllByBeaconId(String beaconId) =>
      throw UnimplementedError();

  @override
  Future<List<HelpOfferEntity>> fetchByUserId(String userId) =>
      throw UnimplementedError();

  @override
  Future<bool> hasActiveHelpOffer({
    required String beaconId,
    required String userId,
  }) => throw UnimplementedError();
}

final class _SingleCommitterCoordinationRepo
    implements CoordinationRepositoryPort {
  _SingleCommitterCoordinationRepo(this._responseType);

  final int _responseType;

  @override
  Future<Map<String, int>> coordinationResponseTypeByOfferUserId(
    String beaconId,
  ) async => {'helper1': _responseType};

  @override
  Future<void> deleteForCommit({
    required String beaconId,
    required String userId,
  }) => throw UnimplementedError();

  @override
  Future<void> upsertResponse({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
    required int responseType,
  }) => throw UnimplementedError();

  @override
  Future<({BeaconStatus status, DateTime? statusChangedAt})> acceptHelpOffer({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
  }) => throw UnimplementedError();

  @override
  Future<({BeaconStatus status, DateTime? statusChangedAt})> declineHelpOffer({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String reason,
  }) => throw UnimplementedError();

  @override
  Future<({BeaconStatus status, DateTime? statusChangedAt})> removeFromRoom({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String reason,
  }) => throw UnimplementedError();

  @override
  Future<({BeaconStatus status, DateTime? statusChangedAt})>
  beaconStatusSnapshot(
    String beaconId,
  ) async => (status: BeaconStatus.open, statusChangedAt: null);

  @override
  Future<List<HelpOfferWithCoordinationRow>> helpOffersWithCoordination(
    String beaconId, {
    required String viewerId,
  }) => throw UnimplementedError();
}
