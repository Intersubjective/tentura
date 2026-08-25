import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
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
    'draft noBasis is ready and shows draft privacy, not live privacy',
    (tester) async {
      final result = await pump(tester, draft: true);
      expect(find.text('Draft privacy'), findsOneWidget);
      expect(
        find.textContaining('These are private draft notes'),
        findsNothing,
      );
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('These are private draft notes'),
        findsWidgets,
      );
      expect(find.text('Review privacy'), findsNothing);
      expect(
        find.textContaining('Reviews are pairwise-private'),
        findsNothing,
      );
      expect(find.text('0 of 1 reviewed'), findsNothing);
      expect(find.text('1 of 1 reviewed'), findsOneWidget);
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
        findsNothing,
      );
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Reviews are pairwise-private'),
        findsWidgets,
      );
      expect(
        find.byKey(TestIds.key(TestIds.evaluationCannotEvaluate('u1'))),
        findsOneWidget,
      );
      expect(
        tester.widget(
          find.byKey(TestIds.key(TestIds.evaluationCannotEvaluate('u1'))),
        ),
        isA<SwitchListTile>(),
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(TestIds.key(TestIds.evaluationCannotEvaluate('u1'))),
            )
            .value,
        isFalse,
      );
      await result.$3.close();
    },
  );

  testWidgets(
    'Cannot evaluate cancel causes no submit; confirm clears note and sends noBasis',
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
      expect(repository.lastSubmit?.note, '');
      expect(cubit.state.participants.single.isSubmitted, isTrue);
      expect(cubit.state.participants.single.note, '');
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
    expect(tester.widget<SwitchListTile>(action).onChanged, isNull);

    repository.submitGate!.complete();
    await test.pumpAndSettle();
    expect(repository.submitCalls, 1);
    expect(test.widget<ListTile>(participantTile).onTap, isNotNull);
    expect(tester.widget<SwitchListTile>(action).onChanged, isNotNull);
    repository.submitError = null;
    await test.tap(action);
    await test.pumpAndSettle();
    await test.tap(find.text('Cannot evaluate').last);
    await test.pumpAndSettle();
    expect(repository.submitCalls, 2);
    expect(repository.lastSubmit?.value, EvaluationValue.noBasis.wire);
    expect(repository.lastSubmit?.reasonTags, isNull);
    expect(repository.lastSubmit?.acknowledgedHelpTags, isEmpty);
    expect(repository.lastSubmit?.note, '');
    expect(
      cubit.state.participants.single.currentValue,
      EvaluationValue.noBasis,
    );
    expect(cubit.state.participants.single.note, '');
    expect(test.widget<ListTile>(participantTile).onTap, isNull);
    expect(tester.widget<SwitchListTile>(action).onChanged, isNotNull);
    expect(tester.widget<SwitchListTile>(action).value, isTrue);
    await cubit.close();
  });

  testWidgets('CTA stays disabled until every card is ready', (tester) async {
    final (_, _, cubit) = await pump(tester);
    final submit = tester.widget<FilledButton>(
      find.byKey(TestIds.key(TestIds.evaluationSubmit)),
    );
    expect(submit.onPressed, isNull);
    expect(
      find.textContaining('Send stays unavailable'),
      findsOneWidget,
    );
    await cubit.close();
  });

  testWidgets('Cannot evaluate toggle OFF clears the card', (tester) async {
    final repository = FakeEvaluationRepository()
      ..participantsResult = [
        participant.copyWith(
          currentValue: EvaluationValue.noBasis,
          isSubmitted: true,
        ),
      ];
    final (test, _, cubit) = await pump(tester, repositoryArg: repository);
    final action = find.byKey(
      TestIds.key(TestIds.evaluationCannotEvaluate('u1')),
    );
    expect(tester.widget<SwitchListTile>(action).value, isTrue);
    await test.tap(action);
    await test.pumpAndSettle();
    expect(repository.draftDeleteCalls, 1);
    expect(cubit.state.participants.single.currentValue, isNull);
    expect(cubit.state.participants.single.isSubmitted, isFalse);
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
      findsNothing,
    );
    expect(find.text('Review privacy'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
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
