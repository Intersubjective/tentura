import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/evaluation/domain/use_case/evaluation_case.dart';
import 'package:tentura/features/evaluation/ui/bloc/evaluation_cubit.dart';
import 'package:tentura/features/evaluation/ui/screen/review_contributions_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'evaluation_case_test.dart' show FakeEvaluationRepository;
import 'evaluation_sheet_test_support.dart' show MockProfileCubit;

class _Effects implements UiEffectPort {
  @override
  Stream<UiEffect> get effects => const Stream.empty();

  @override
  void emit(UiEffect effect) {}
}

class _HarnessRouter extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;
}

class _ControllableEvaluationRepository extends FakeEvaluationRepository {
  Completer<void>? submitGate;

  @override
  Future<void> submit({
    required String beaconId,
    required String evaluatedUserId,
    required int value,
    List<String>? reasonTags,
    String note = '',
    List<String>? acknowledgedHelpTags,
  }) async {
    final gate = submitGate;
    if (gate != null) {
      await gate.future;
      submitGate = null;
    }
    await super.submit(
      beaconId: beaconId,
      evaluatedUserId: evaluatedUserId,
      value: value,
      reasonTags: reasonTags,
      note: note,
      acknowledgedHelpTags: acknowledgedHelpTags,
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

  Future<(WidgetTester, FakeEvaluationRepository, EvaluationCubit)> pump(
    WidgetTester tester, {
    bool draft = false,
    FakeEvaluationRepository? repositoryArg,
    Size? surfaceSize,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    if (surfaceSize != null) {
      await tester.binding.setSurfaceSize(surfaceSize);
    }
    final draftParticipants = [
      if (draft)
        participant.copyWith(currentValue: EvaluationValue.noBasis)
      else
        participant,
    ];
    final repository = repositoryArg ?? FakeEvaluationRepository();
    repository
      ..draftBootstrapResult = (
        window: const ReviewWindowInfo(beaconId: 'b1', hasWindow: true),
        participants: draftParticipants,
      )
      ..draftParticipantsResult = draftParticipants
      ..reviewWindowResult = const ReviewWindowInfo(
        beaconId: 'b1',
        hasWindow: true,
        closesAt: '2026-08-30T12:00:00Z',
      );
    if (repositoryArg == null) {
      repository.participantsResult = draftParticipants;
    }
    final evaluationCase = EvaluationCase(
      repository,
      env: const Env(),
      logger: Logger('screen-test'),
    );
    final cubit = EvaluationCubit(
      evaluationCase,
      beaconId: 'b1',
      isDraftMode: draft,
      effects: _Effects(),
    );
    final router = _HarnessRouter();
    await tester.pumpWidget(
      RouterScope(
        controller: router,
        stateHash: 0,
        inheritableObserversBuilder: () => const [],
        child: StackRouterScope(
          controller: router,
          stateHash: 0,
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            theme: TenturaTheme.light(),
            home: MultiBlocProvider(
              providers: [
                BlocProvider<EvaluationCubit>.value(value: cubit),
                BlocProvider<ProfileCubit>.value(value: MockProfileCubit()),
              ],
              child: MediaQuery(
                data: MediaQueryData(textScaler: textScaler),
                child: ReviewContributionsScreen(id: 'b1', draft: draft),
              ),
            ),
          ),
        ),
      ),
    );
    await cubit.loadParticipantsOnly();
    await tester.pumpAndSettle();
    return (tester, repository, cubit);
  }

  testWidgets(
    'draft value is visibly draft and cannot masquerade as submitted',
    (tester) async {
      final result = await pump(tester, draft: true);
      expect(find.text('Draft review'), findsOneWidget);
      expect(find.text('Draft privacy'), findsOneWidget);
      expect(
        find.textContaining('These are private draft notes'),
        findsOneWidget,
      );
      expect(find.text('Review privacy'), findsNothing);
      expect(
        find.textContaining('Reviews are pairwise-private'),
        findsNothing,
      );
      expect(find.text('0 of 1 reviewed'), findsOneWidget);
      expect(find.textContaining('Review closes'), findsNothing);
      await result.$3.close();
    },
  );

  testWidgets(
    'live list discloses pairwise privacy beside untouched Cannot evaluate',
    (tester) async {
      final result = await pump(tester);
      expect(find.text('Review privacy'), findsOneWidget);
      expect(
        find.textContaining('Reviews are pairwise-private'),
        findsOneWidget,
      );
      expect(
        find.byKey(TestIds.key(TestIds.evaluationCannotEvaluate('u1'))),
        findsOneWidget,
      );
      await result.$3.close();
    },
  );

  testWidgets(
    'Cannot evaluate cancel causes no submit; confirm sends noBasis and empty ack',
    (tester) async {
      final (test, repository, cubit) = await pump(tester);
      final action = find.byKey(
        TestIds.key(TestIds.evaluationCannotEvaluate('u1')),
      );
      await test.tap(action);
      await test.pumpAndSettle();
      expect(repository.submitCalls, 1);

      repository.participantsResult = const [
        EvaluationParticipant(
          userId: 'u1',
          displayName: 'Alice',
          role: EvaluationParticipantRole.committer,
          contributionSummary: 'Helped',
          causalHint: '',
          currentValue: EvaluationValue.pos1,
          isSubmitted: true,
          note: 'Keep this note',
        ),
      ];
      await cubit.loadParticipantsOnly();
      await test.pumpAndSettle();
      await test.tap(action);
      await test.pumpAndSettle();
      await test.tap(find.text('Cancel'));
      await test.pumpAndSettle();
      expect(repository.submitCalls, 1);
      await test.tap(action);
      await test.pumpAndSettle();
      await test.tap(find.text('Cannot evaluate').last);
      await test.pumpAndSettle();
      expect(repository.submitCalls, 2);
      expect(repository.lastSubmit?.value, EvaluationValue.noBasis.wire);
      expect(repository.lastSubmit?.reasonTags, isNull);
      expect(repository.lastSubmit?.acknowledgedHelpTags, isEmpty);
      expect(cubit.state.participants.single.isSubmitted, isTrue);
      await cubit.close();
    },
  );

  testWidgets('Cannot evaluate failure preserves prior card and allows retry', (
    tester,
  ) async {
    final repository = _ControllableEvaluationRepository()
      ..participantsResult = [
        participant.copyWith(
          currentValue: EvaluationValue.pos1,
          isSubmitted: true,
          note: 'kept note',
        ),
      ];
    final (test, _, cubit) = await pump(tester, repositoryArg: repository);
    final action = find.byKey(
      TestIds.key(TestIds.evaluationCannotEvaluate('u1')),
    );
    repository.submitGate = Completer<void>();
    repository.submitError = Exception('first submit failed');
    await test.tap(action);
    await test.pumpAndSettle();
    await test.tap(find.text('Cannot evaluate').last);
    await test.pump();
    expect(repository.submitCalls, 0);
    final participantTile = find.byKey(
      TestIds.key(TestIds.evaluationParticipant('u1')),
    );
    expect(test.widget<ListTile>(participantTile).onTap, isNull);
    await test.tap(participantTile, warnIfMissed: false);
    expect(repository.submitCalls, 0);
    expect(cubit.state.participants.single.currentValue, EvaluationValue.pos1);
    expect(cubit.state.participants.single.isSubmitted, isTrue);
    expect(cubit.state.participants.single.note, 'kept note');
    expect(tester.widget<TextButton>(action).onPressed, isNull);

    expect(repository.submitCalls, 0);
    expect(tester.widget<TextButton>(action).onPressed, isNull);
    repository.submitGate!.complete();
    await test.pumpAndSettle();
    expect(repository.submitCalls, 1);
    expect(test.widget<ListTile>(participantTile).onTap, isNotNull);
    expect(tester.widget<TextButton>(action).onPressed, isNotNull);
    repository.submitError = null;
    repository.participantsResult = [
      participant.copyWith(
        currentValue: EvaluationValue.noBasis,
        isSubmitted: true,
        note: 'kept note',
      ),
    ];
    await test.tap(action);
    await test.pumpAndSettle();
    await test.tap(find.text('Cannot evaluate').last);
    await test.pumpAndSettle();
    expect(repository.submitCalls, 2);
    expect(repository.lastSubmit?.value, EvaluationValue.noBasis.wire);
    expect(repository.lastSubmit?.reasonTags, isNull);
    expect(repository.lastSubmit?.acknowledgedHelpTags, isEmpty);
    expect(repository.lastSubmit?.note, 'kept note');
    expect(
      cubit.state.participants.single.currentValue,
      EvaluationValue.noBasis,
    );
    expect(cubit.state.participants.single.note, 'kept note');
    await cubit.close();
  });

  testWidgets('live review renders deterministic deadline', (tester) async {
    final (_, _, cubit) = await pump(tester);
    expect(find.textContaining('Review closes'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('narrow large text keeps submitted status below divider', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeEvaluationRepository()
      ..participantsResult = [
        participant.copyWith(
          currentValue: EvaluationValue.pos1,
          isSubmitted: true,
        ),
      ];
    final (test, _, cubit) = await pump(
      tester,
      repositoryArg: repository,
      surfaceSize: const Size(320, 700),
      textScaler: const TextScaler.linear(2),
    );
    expect(
      find.textContaining('Reviews are pairwise-private'),
      findsOneWidget,
    );
    await test.scrollUntilVisible(
      find.text('Helped somewhat'),
      400,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Helped somewhat'), findsOneWidget);
    expect(find.text('Cannot evaluate'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await cubit.close();
  });

  testWidgets('compact untouched participant shows Not reviewed in subtitle', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeEvaluationRepository()
      ..participantsResult = [participant];
    final (test, _, cubit) = await pump(
      tester,
      repositoryArg: repository,
      surfaceSize: const Size(320, 700),
    );
    await test.scrollUntilVisible(
      find.byKey(TestIds.key(TestIds.evaluationParticipant('u1'))),
      300,
      scrollable: find.byType(Scrollable),
    );
    final tile = test.widget<ListTile>(
      find.byKey(TestIds.key(TestIds.evaluationParticipant('u1'))),
    );
    expect(tile.trailing, isNull);
    expect(find.text('Not reviewed'), findsOneWidget);
    expect(test.takeException(), isNull);
    await cubit.close();
  });
}
