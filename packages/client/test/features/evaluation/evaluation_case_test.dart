import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/beacon_close_result.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_summary.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/evaluation/domain/use_case/evaluation_case.dart';

void main() {
  late FakeEvaluationRepository repository;
  late EvaluationCase case_;

  const beaconId = 'B-eval-001';
  const evaluatedUserId = 'U-evaluated1';

  setUp(() {
    repository = FakeEvaluationRepository();
    case_ = EvaluationCase(
      repository,
      env: const Env(),
      logger: Logger('test'),
    );
  });

  group('fetchReviewWindowStatus', () {
    test('returns repository review window info', () async {
      final window = _reviewWindow(beaconId: beaconId);
      repository.reviewWindowResult = window;

      final result = await case_.fetchReviewWindowStatus(beaconId);

      expect(result, window);
      expect(repository.lastReviewWindowBeaconId, beaconId);
    });
  });

  group('fetchParticipants', () {
    test('returns repository participant list', () async {
      final participants = [_participant(userId: evaluatedUserId)];
      repository.participantsResult = participants;

      final result = await case_.fetchParticipants(beaconId);

      expect(result, participants);
      expect(repository.lastParticipantsBeaconId, beaconId);
    });
  });

  group('fetchSummary', () {
    test('returns repository evaluation summary', () async {
      final summary = _summary();
      repository.summaryResult = summary;

      final result = await case_.fetchSummary(beaconId);

      expect(result, summary);
      expect(repository.lastSummaryBeaconId, beaconId);
    });
  });

  group('fetchDraftModeBootstrap', () {
    test('returns repository draft bootstrap bundle', () async {
      final bootstrap = (
        window: _reviewWindow(beaconId: beaconId, beaconTitle: 'Draft beacon'),
        participants: [_participant(userId: evaluatedUserId)],
      );
      repository.draftBootstrapResult = bootstrap;

      final result = await case_.fetchDraftModeBootstrap(beaconId);

      expect(result, bootstrap);
      expect(repository.lastDraftBootstrapBeaconId, beaconId);
    });
  });

  group('fetchDraftParticipants', () {
    test('returns repository draft participant list', () async {
      final participants = [_participant(userId: evaluatedUserId)];
      repository.draftParticipantsResult = participants;

      final result = await case_.fetchDraftParticipants(beaconId);

      expect(result, participants);
      expect(repository.lastDraftParticipantsBeaconId, beaconId);
    });
  });

  group('draftSave', () {
    test('forwards draft save args to repository', () async {
      await case_.draftSave(
        beaconId: beaconId,
        evaluatedUserId: evaluatedUserId,
        value: 1,
        reasonTags: const ['helpful'],
        note: 'Thanks',
      );

      expect(repository.draftSaveCalls, 1);
      expect(repository.lastDraftSave?.beaconId, beaconId);
      expect(repository.lastDraftSave?.evaluatedUserId, evaluatedUserId);
      expect(repository.lastDraftSave?.value, 1);
      expect(repository.lastDraftSave?.reasonTags, ['helpful']);
      expect(repository.lastDraftSave?.note, 'Thanks');
    });
  });

  group('submit', () {
    test('forwards submit args including acknowledged help tags', () async {
      await case_.submit(
        beaconId: beaconId,
        evaluatedUserId: evaluatedUserId,
        value: 2,
        reasonTags: const ['fast'],
        note: 'Great',
        acknowledgedHelpTags: const ['coordination'],
      );

      expect(repository.submitCalls, 1);
      expect(repository.lastSubmit?.beaconId, beaconId);
      expect(repository.lastSubmit?.evaluatedUserId, evaluatedUserId);
      expect(repository.lastSubmit?.value, 2);
      expect(repository.lastSubmit?.reasonTags, ['fast']);
      expect(repository.lastSubmit?.note, 'Great');
      expect(repository.lastSubmit?.acknowledgedHelpTags, ['coordination']);
    });
  });

  group('finalize', () {
    test('delegates finalize to repository', () async {
      await case_.finalize(beaconId);

      expect(repository.finalizeCalls, 1);
      expect(repository.lastFinalizeBeaconId, beaconId);
    });
  });

  group('skip', () {
    test('delegates skip to repository', () async {
      await case_.skip(beaconId);

      expect(repository.skipCalls, 1);
      expect(repository.lastSkipBeaconId, beaconId);
    });
  });

  group('beaconClose', () {
    test('forwards expected review-window flag and returns result', () async {
      final closeResult = BeaconCloseResult(
        beaconId: beaconId,
        state: 2,
        requiresReviewWindow: true,
      );
      repository.beaconCloseResult = closeResult;

      final result = await case_.beaconClose(
        beaconId: beaconId,
        expectedRequiresReviewWindow: true,
      );

      expect(result, closeResult);
      expect(repository.lastBeaconClose?.beaconId, beaconId);
      expect(repository.lastBeaconClose?.expectedRequiresReviewWindow, isTrue);
    });
  });

  group('beacon lifecycle mutations', () {
    test('beaconCancel delegates to repository', () async {
      final mutation = BeaconLifecycleMutationResult(
        beaconId: beaconId,
        state: 3,
      );
      repository.beaconCancelResult = mutation;

      final result = await case_.beaconCancel(beaconId);

      expect(result, mutation);
      expect(repository.lastBeaconCancelId, beaconId);
    });

    test('beaconExtendReview delegates to repository', () async {
      final extendResult = BeaconExtendReviewResult(
        beaconId: beaconId,
        closesAt: '2099-01-01T00:00:00.000Z',
        extensionsRemaining: 1,
      );
      repository.beaconExtendReviewResult = extendResult;

      final result = await case_.beaconExtendReview(beaconId);

      expect(result, extendResult);
      expect(repository.lastBeaconExtendReviewId, beaconId);
    });

    test('beaconReopen delegates to repository', () async {
      final mutation = BeaconLifecycleMutationResult(
        beaconId: beaconId,
        state: 1,
      );
      repository.beaconReopenResult = mutation;

      final result = await case_.beaconReopen(beaconId);

      expect(result, mutation);
      expect(repository.lastBeaconReopenId, beaconId);
    });

    test('beaconCloseNow delegates to repository', () async {
      final mutation = BeaconLifecycleMutationResult(
        beaconId: beaconId,
        state: 2,
      );
      repository.beaconCloseNowResult = mutation;

      final result = await case_.beaconCloseNow(beaconId);

      expect(result, mutation);
      expect(repository.lastBeaconCloseNowId, beaconId);
    });
  });

  group('repository error propagation', () {
    test('submit propagates repository failures unchanged', () async {
      repository.submitError = Exception('network');

      await expectLater(
        () => case_.submit(
          beaconId: beaconId,
          evaluatedUserId: evaluatedUserId,
          value: 0,
        ),
        throwsA(isA<Exception>()),
      );
      expect(repository.submitCalls, 1);
    });
  });
}

ReviewWindowInfo _reviewWindow({
  required String beaconId,
  String beaconTitle = 'Beacon',
}) =>
    ReviewWindowInfo(
      beaconId: beaconId,
      hasWindow: true,
      beaconTitle: beaconTitle,
      openedAt: '2026-06-01T00:00:00.000Z',
      closesAt: '2026-06-08T00:00:00.000Z',
      reviewedCount: 1,
      totalCount: 3,
    );

EvaluationParticipant _participant({required String userId}) =>
    EvaluationParticipant(
      userId: userId,
      displayName: 'Participant',
      role: EvaluationParticipantRole.committer,
      contributionSummary: 'Helped',
      causalHint: 'Direct',
      currentValue: EvaluationValue.pos1,
    );

EvaluationSummary _summary() => const EvaluationSummary(
      suppressed: false,
      tone: 'positive',
      message: 'Strong support',
      topReasonTags: ['helpful'],
      pos1: 2,
    );

class FakeEvaluationRepository implements EvaluationRepository {
  ReviewWindowInfo reviewWindowResult = ReviewWindowInfo(
    beaconId: '',
    hasWindow: false,
  );
  List<EvaluationParticipant> participantsResult = const [];
  EvaluationSummary summaryResult = const EvaluationSummary(
    suppressed: false,
    tone: '',
    message: '',
  );
  ({ReviewWindowInfo window, List<EvaluationParticipant> participants})
      draftBootstrapResult = (
    window: ReviewWindowInfo(beaconId: '', hasWindow: false),
    participants: const [],
  );
  List<EvaluationParticipant> draftParticipantsResult = const [];

  BeaconCloseResult beaconCloseResult =
      BeaconCloseResult(beaconId: '', state: 0);
  BeaconLifecycleMutationResult beaconCancelResult =
      BeaconLifecycleMutationResult(beaconId: '', state: 0);
  BeaconExtendReviewResult beaconExtendReviewResult =
      BeaconExtendReviewResult(beaconId: '', closesAt: '');
  BeaconLifecycleMutationResult beaconReopenResult =
      BeaconLifecycleMutationResult(beaconId: '', state: 0);
  BeaconLifecycleMutationResult beaconCloseNowResult =
      BeaconLifecycleMutationResult(beaconId: '', state: 0);

  String? lastReviewWindowBeaconId;
  String? lastParticipantsBeaconId;
  String? lastSummaryBeaconId;
  String? lastDraftBootstrapBeaconId;
  String? lastDraftParticipantsBeaconId;

  int draftSaveCalls = 0;
  ({
    String beaconId,
    String evaluatedUserId,
    int value,
    List<String> reasonTags,
    String note,
  })? lastDraftSave;

  int submitCalls = 0;
  Exception? submitError;
  ({
    String beaconId,
    String evaluatedUserId,
    int value,
    List<String> reasonTags,
    String note,
    List<String>? acknowledgedHelpTags,
  })? lastSubmit;

  int finalizeCalls = 0;
  String? lastFinalizeBeaconId;

  int skipCalls = 0;
  String? lastSkipBeaconId;

  ({String beaconId, bool expectedRequiresReviewWindow})? lastBeaconClose;
  String? lastBeaconCancelId;
  String? lastBeaconExtendReviewId;
  String? lastBeaconReopenId;
  String? lastBeaconCloseNowId;

  @override
  Future<ReviewWindowInfo> fetchReviewWindowStatus(String beaconId) async {
    lastReviewWindowBeaconId = beaconId;
    return reviewWindowResult;
  }

  @override
  Future<List<EvaluationParticipant>> fetchParticipants(String beaconId) async {
    lastParticipantsBeaconId = beaconId;
    return participantsResult;
  }

  @override
  Future<EvaluationSummary> fetchSummary(String beaconId) async {
    lastSummaryBeaconId = beaconId;
    return summaryResult;
  }

  @override
  Future<({ReviewWindowInfo window, List<EvaluationParticipant> participants})>
      fetchDraftModeBootstrap(String beaconId) async {
    lastDraftBootstrapBeaconId = beaconId;
    return draftBootstrapResult;
  }

  @override
  Future<List<EvaluationParticipant>> fetchDraftParticipants(
    String beaconId,
  ) async {
    lastDraftParticipantsBeaconId = beaconId;
    return draftParticipantsResult;
  }

  @override
  Future<void> draftSave({
    required String beaconId,
    required String evaluatedUserId,
    required int value,
    List<String> reasonTags = const [],
    String note = '',
  }) async {
    draftSaveCalls++;
    lastDraftSave = (
      beaconId: beaconId,
      evaluatedUserId: evaluatedUserId,
      value: value,
      reasonTags: reasonTags,
      note: note,
    );
  }

  @override
  Future<void> submit({
    required String beaconId,
    required String evaluatedUserId,
    required int value,
    List<String> reasonTags = const [],
    String note = '',
    List<String>? acknowledgedHelpTags,
  }) async {
    submitCalls++;
    if (submitError != null) {
      throw submitError!;
    }
    lastSubmit = (
      beaconId: beaconId,
      evaluatedUserId: evaluatedUserId,
      value: value,
      reasonTags: reasonTags,
      note: note,
      acknowledgedHelpTags: acknowledgedHelpTags,
    );
  }

  @override
  Future<void> finalize(String beaconId) async {
    finalizeCalls++;
    lastFinalizeBeaconId = beaconId;
  }

  @override
  Future<void> skip(String beaconId) async {
    skipCalls++;
    lastSkipBeaconId = beaconId;
  }

  @override
  Future<BeaconCloseResult> beaconClose({
    required String beaconId,
    required bool expectedRequiresReviewWindow,
  }) async {
    lastBeaconClose = (
      beaconId: beaconId,
      expectedRequiresReviewWindow: expectedRequiresReviewWindow,
    );
    return beaconCloseResult;
  }

  @override
  Future<BeaconLifecycleMutationResult> beaconCancel(String beaconId) async {
    lastBeaconCancelId = beaconId;
    return beaconCancelResult;
  }

  @override
  Future<BeaconExtendReviewResult> beaconExtendReview(String beaconId) async {
    lastBeaconExtendReviewId = beaconId;
    return beaconExtendReviewResult;
  }

  @override
  Future<BeaconLifecycleMutationResult> beaconReopen(String beaconId) async {
    lastBeaconReopenId = beaconId;
    return beaconReopenResult;
  }

  @override
  Future<BeaconLifecycleMutationResult> beaconCloseNow(String beaconId) async {
    lastBeaconCloseNowId = beaconId;
    return beaconCloseNowResult;
  }
}
