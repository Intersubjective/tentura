import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/evaluation/domain/evaluation_exception.dart';
import 'package:tentura/features/evaluation/domain/review_package_state.dart';
import 'package:tentura/features/evaluation/domain/use_case/evaluation_case.dart';
import 'package:tentura/features/evaluation/ui/bloc/evaluation_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'evaluation_case_test.dart' show FakeEvaluationRepository;

class _Effects implements UiEffectPort {
  final emitted = <UiEffect>[];

  @override
  Stream<UiEffect> get effects => const Stream.empty();

  @override
  void emit(UiEffect effect) => emitted.add(effect);
}

class _RefreshFailingRepository extends FakeEvaluationRepository {
  bool failRefresh = false;

  @override
  Future<ReviewWindowInfo> fetchReviewWindowStatus(String beaconId) async {
    if (failRefresh) {
      throw Exception('window refresh failed');
    }
    return super.fetchReviewWindowStatus(beaconId);
  }
}

class _LifecycleRepository extends FakeEvaluationRepository {
  Exception? participantsError;
  Exception? windowError;
  int participantsCalls = 0;
  int windowCalls = 0;
  Exception? finalizeError;

  @override
  Future<void> finalize(String beaconId) async {
    final error = finalizeError;
    if (error != null) throw error;
    return super.finalize(beaconId);
  }

  @override
  Future<List<EvaluationParticipant>> fetchParticipants(String beaconId) async {
    participantsCalls++;
    final error = participantsError;
    if (error != null) throw error;
    return super.fetchParticipants(beaconId);
  }

  @override
  Future<ReviewWindowInfo> fetchReviewWindowStatus(String beaconId) async {
    windowCalls++;
    final error = windowError;
    if (error != null) throw error;
    return super.fetchReviewWindowStatus(beaconId);
  }
}

class _GatedDraftSaveRepository extends FakeEvaluationRepository {
  Completer<void>? draftSaveGate;

  @override
  Future<void> draftSave({
    required String beaconId,
    required String evaluatedUserId,
    required int value,
    List<String>? reasonTags,
    String note = '',
  }) async {
    final gate = draftSaveGate;
    if (gate != null) {
      await gate.future;
      draftSaveGate = null;
    }
    await super.draftSave(
      beaconId: beaconId,
      evaluatedUserId: evaluatedUserId,
      value: value,
      reasonTags: reasonTags,
      note: note,
    );
  }
}

void main() {
  const participant = EvaluationParticipant(
    userId: 'u1',
    displayName: 'Alice',
    role: EvaluationParticipantRole.committer,
    contributionSummary: 'Helped',
    causalHint: '',
  );

  test('draftSave completion after dispose does not emit', () async {
    final repository = _GatedDraftSaveRepository()
      ..draftParticipantsResult = [
        participant.copyWith(currentValue: EvaluationValue.pos1),
      ];
    final effects = _Effects();
    final cubit = EvaluationCubit(
      EvaluationCase(
        repository,
        env: const Env(),
        logger: Logger('evaluation-cubit-lifecycle'),
      ),
      beaconId: 'b1',
      isDraftMode: true,
      effects: effects,
    );
    repository.draftSaveGate = Completer<void>();

    final pending = cubit.submitOne(
      evaluatedUserId: 'u1',
      value: EvaluationValue.pos1,
    );
    await cubit.close();
    repository.draftSaveGate!.complete();

    expect(await pending, isTrue);
    expect(cubit.isClosed, isTrue);
    expect(repository.draftSaveCalls, 1);
    expect(effects.emitted, isEmpty);
  });

  EvaluationCubit buildLiveCubit(
    FakeEvaluationRepository repository,
    _Effects effects,
  ) => EvaluationCubit(
    EvaluationCase(
      repository,
      env: const Env(),
      logger: Logger('evaluation-cubit-lifecycle'),
    ),
    beaconId: 'b1',
    effects: effects,
  );

  test('live finalize stays on screen and refreshes the package', () async {
    final repository = _RefreshFailingRepository()
      ..participantsResult = [participant.copyWith(rowStatus: 1)]
      ..reviewWindowResult = const ReviewWindowInfo(
        beaconId: 'b1',
        hasWindow: true,
        userReviewStatus: 1,
        totalCount: 1,
        requiredTotal: 1,
      );
    final effects = _Effects();
    final cubit = buildLiveCubit(repository, effects);
    await cubit.loadParticipantsOnly();

    repository
      ..participantsResult = [
        participant.copyWith(rowStatus: 2, isSubmitted: true),
      ]
      ..reviewWindowResult = ReviewWindowInfo(
        beaconId: 'b1',
        hasWindow: true,
        userReviewStatus: 2,
        totalCount: 1,
        requiredTotal: 1,
        sentAt: DateTime.utc(2026, 9, 18),
      );
    await cubit.finalize();

    expect(repository.finalizeCalls, 1);
    expect(effects.emitted.whereType<NavigateBack>(), isEmpty);
    expect(cubit.state.windowInfo?.userReviewStatus, 2);
    expect(cubit.state.packageState, ReviewPackageState.sent);
    await cubit.close();
  });

  test('refresh failure after a successful send keeps the package sent', () async {
    final repository = _RefreshFailingRepository()
      ..participantsResult = [participant.copyWith(rowStatus: 1)]
      ..reviewWindowResult = const ReviewWindowInfo(
        beaconId: 'b1',
        hasWindow: true,
        userReviewStatus: 1,
        totalCount: 1,
        requiredTotal: 1,
      );
    final effects = _Effects();
    final cubit = buildLiveCubit(repository, effects);
    await cubit.loadParticipantsOnly();
    final before = cubit.state.participants;

    repository.failRefresh = true;
    await cubit.finalize();

    expect(repository.finalizeCalls, 1);
    expect(effects.emitted.whereType<NavigateBack>(), isEmpty);
    expect(effects.emitted.whereType<ShowError>(), hasLength(1));
    expect(cubit.state.participants, before);
    expect(cubit.state.windowInfo?.userReviewStatus, 2);
    expect(cubit.state.windowInfo?.sentAt, isNotNull);
    expect(cubit.state.packageState, ReviewPackageState.sent);
    expect(cubit.state.isLoading, isFalse);
    await cubit.close();
  });

  test('draft finalize still navigates back', () async {
    final repository = FakeEvaluationRepository()
      ..draftParticipantsResult = [
        participant.copyWith(currentValue: EvaluationValue.pos1),
      ]
      ..draftBootstrapResult = (
        window: const ReviewWindowInfo(beaconId: 'b1', hasWindow: true),
        participants: [participant.copyWith(currentValue: EvaluationValue.pos1)],
      );
    final effects = _Effects();
    final cubit = EvaluationCubit(
      EvaluationCase(
        repository,
        env: const Env(),
        logger: Logger('evaluation-cubit-lifecycle'),
      ),
      beaconId: 'b1',
      isDraftMode: true,
      effects: effects,
    );
    await cubit.loadParticipantsOnly();
    await cubit.finalize();

    expect(effects.emitted.whereType<NavigateBack>(), hasLength(1));
    await cubit.close();
  });

  test('packageState derives from the window and the required rows', () async {
    final repository = FakeEvaluationRepository()
      ..participantsResult = [
        participant.copyWith(rowStatus: -1),
        participant.copyWith(userId: 'u2', isOptional: true, rowStatus: -1),
      ]
      ..reviewWindowResult = const ReviewWindowInfo(
        beaconId: 'b1',
        hasWindow: true,
        userReviewStatus: 1,
        totalCount: 2,
        requiredTotal: 1,
      );
    final cubit = buildLiveCubit(repository, _Effects());
    await cubit.loadParticipantsOnly();
    expect(cubit.state.packageState, ReviewPackageState.inProgress);

    repository.participantsResult = [
      participant.copyWith(rowStatus: 1),
      participant.copyWith(userId: 'u2', isOptional: true, rowStatus: -1),
    ];
    await cubit.loadParticipantsOnly();
    expect(cubit.state.packageState, ReviewPackageState.readyToSend);

    repository.reviewWindowResult = ReviewWindowInfo(
      beaconId: 'b1',
      hasWindow: true,
      userReviewStatus: 1,
      totalCount: 2,
      requiredTotal: 1,
      sentAt: DateTime.utc(2026, 9, 18),
    );
    await cubit.loadParticipantsOnly();
    expect(cubit.state.packageState, ReviewPackageState.changedNotSent);

    expect(cubit.state.beaconIsInReview, isTrue);
    expect(cubit.state.beaconIsClosed, isFalse);
    await cubit.close();
  });

  group('lifecycle classification (D12)', () {
    const openWindow = ReviewWindowInfo(
      beaconId: 'b1',
      hasWindow: true,
      userReviewStatus: 1,
      totalCount: 1,
      requiredTotal: 1,
    );

    Future<(EvaluationCubit, _LifecycleRepository, _Effects)> loaded() async {
      final repository = _LifecycleRepository()
        ..participantsResult = [participant.copyWith(rowStatus: 1)]
        ..reviewWindowResult = openWindow;
      final effects = _Effects();
      final cubit = buildLiveCubit(repository, effects);
      await cubit.loadParticipantsOnly();
      expect(cubit.state.packageState, ReviewPackageState.readyToSend);
      return (cubit, repository, effects);
    }

    test('submitOne on a vanished window yields paused, not a snackbar',
        () async {
      final (cubit, repository, effects) = await loaded();
      final participantsBefore = repository.participantsCalls;
      final windowBefore = repository.windowCalls;
      repository
        ..submitError = const EvaluationReviewWindowNotOpenException()
        ..reviewWindowResult = const ReviewWindowInfo(
          beaconId: 'b1',
          hasWindow: false,
        );

      final ok = await cubit.submitOne(
        evaluatedUserId: 'u1',
        value: EvaluationValue.pos1,
      );

      expect(ok, isFalse);
      expect(cubit.state.packageState, ReviewPackageState.paused);
      expect(cubit.state.isLoading, isFalse);
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
      expect(repository.participantsCalls, participantsBefore);
      expect(repository.windowCalls, windowBefore + 1);
      await cubit.close();
    });

    test('a completed window with sentAt yields closed', () async {
      final (cubit, repository, effects) = await loaded();
      final participantsBefore = repository.participantsCalls;
      repository
        ..submitError = const EvaluationReviewWindowNotOpenException()
        ..reviewWindowResult = ReviewWindowInfo(
          beaconId: 'b1',
          hasWindow: true,
          windowComplete: true,
          userReviewStatus: 2,
          sentAt: DateTime.utc(2026, 9, 18),
        );

      await cubit.submitOne(evaluatedUserId: 'u1', value: EvaluationValue.pos1);

      expect(cubit.state.packageState, ReviewPackageState.closed);
      expect(cubit.state.beaconIsClosed, isTrue);
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
      expect(repository.participantsCalls, participantsBefore);
      await cubit.close();
    });

    test('a completed window without sentAt yields closedUnsent', () async {
      final (cubit, repository, effects) = await loaded();
      final participantsBefore = repository.participantsCalls;
      repository
        ..participantsError = const EvaluationReviewWindowExpiredException()
        ..reviewWindowResult = const ReviewWindowInfo(
          beaconId: 'b1',
          hasWindow: true,
          windowComplete: true,
          userReviewStatus: 4,
        );

      await cubit.loadParticipantsOnly();

      expect(cubit.state.packageState, ReviewPackageState.closedUnsent);
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
      // Only the failing participants read; classify does not refetch them.
      expect(repository.participantsCalls, participantsBefore + 1);
      await cubit.close();
    });

    test('a failing classification read keeps the previous state and shows '
        'the error', () async {
      final (cubit, repository, effects) = await loaded();
      final before = cubit.state;
      const original = EvaluationReviewWindowNotOpenException();
      repository
        ..submitError = original
        ..windowError = Exception('classify read failed');

      await cubit.submitOne(evaluatedUserId: 'u1', value: EvaluationValue.pos1);

      final errors = effects.emitted.whereType<ShowError>().toList();
      expect(errors, hasLength(1));
      expect(errors.single.error, same(original));
      expect(cubit.state.windowInfo, before.windowInfo);
      expect(cubit.state.participants, before.participants);
      expect(cubit.state.packageState, ReviewPackageState.readyToSend);
      expect(cubit.state.isLoading, isFalse);
      await cubit.close();
    });

    test('the stale participant list is not rebuilt in paused', () async {
      final (cubit, repository, effects) = await loaded();
      final before = cubit.state.participants;
      final participantsBefore = repository.participantsCalls;
      repository
        ..reviewWindowResult = const ReviewWindowInfo(
          beaconId: 'b1',
          hasWindow: false,
        )
        ..participantsResult = [
          participant.copyWith(userId: 'other', rowStatus: -1),
        ];
      // finalize itself fails with 1401 after the author reopened.
      repository.finalizeError = const EvaluationReviewWindowNotOpenException();

      await cubit.finalize();

      expect(cubit.state.packageState, ReviewPackageState.paused);
      expect(cubit.state.participants, before);
      expect(repository.participantsCalls, participantsBefore);
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
      await cubit.close();
    });
  });
}
