import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/evaluation/domain/review_package_state.dart';
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
  final replaced = <PageRouteInfo<dynamic>>[];

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;

  @override
  Future<T?> replace<T extends Object?>(
    PageRouteInfo<dynamic> route, {
    OnNavigationFailure? onFailure,
  }) async {
    replaced.add(route);
    return null;
  }
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

/// Models the server side of a package send: `finalize` marks the window sent,
/// a later edit demotes it back to "changed, not sent".
class _PackageRepository extends FakeEvaluationRepository {
  ReviewWindowInfo? windowAfterFinalize;
  ReviewWindowInfo? windowAfterSubmit;
  List<EvaluationParticipant>? participantsAfterFinalize;

  @override
  Future<void> finalize(String beaconId) async {
    await super.finalize(beaconId);
    final window = windowAfterFinalize;
    if (window != null) reviewWindowResult = window;
    final participants = participantsAfterFinalize;
    if (participants != null) participantsResult = participants;
  }

  @override
  Future<void> submit({
    required String beaconId,
    required String evaluatedUserId,
    required int value,
    List<String>? reasonTags,
    String note = '',
    List<String>? acknowledgedHelpTags,
  }) async {
    await super.submit(
      beaconId: beaconId,
      evaluatedUserId: evaluatedUserId,
      value: value,
      reasonTags: reasonTags,
      note: note,
      acknowledgedHelpTags: acknowledgedHelpTags,
    );
    final window = windowAfterSubmit;
    if (window != null) reviewWindowResult = window;
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

  late _HarnessRouter lastRouter;

  Future<(WidgetTester, FakeEvaluationRepository, EvaluationCubit)> pump(
    WidgetTester tester, {
    bool draft = false,
    FakeEvaluationRepository? repositoryArg,
    Size? surfaceSize,
    TextScaler textScaler = TextScaler.noScaling,
    ReviewWindowInfo? window,
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
      ..reviewWindowResult =
          window ??
          const ReviewWindowInfo(
            beaconId: 'b1',
            hasWindow: true,
            closesAt: '2026-08-30T12:00:00Z',
            userReviewStatus: 1,
            totalCount: 1,
            requiredTotal: 1,
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
    final router = lastRouter = _HarnessRouter();
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
      // Issue #161: reviewing is the primary card action; opting out is a
      // demoted text action, never a switch.
      expect(find.byType(SwitchListTile), findsNothing);
      expect(
        tester.widget(
          find.byKey(TestIds.key(TestIds.evaluationReviewAction('u1'))),
        ),
        isA<FilledButton>(),
      );
      expect(find.text('Review'), findsOneWidget);
      expect(
        tester.widget(
          find.byKey(TestIds.key(TestIds.evaluationCannotEvaluate('u1'))),
        ),
        isA<TextButton>(),
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
      expect(find.text('Review'), findsOneWidget);
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
          rowStatus: 1,
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
      expect(find.text('Undo'), findsOneWidget);
      expect(
        find.textContaining('No review will be sent and your trust'),
        findsOneWidget,
      );
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
          rowStatus: 1,
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

    repository.submitGate!.complete();
    await test.pumpAndSettle();
    expect(repository.submitCalls, 1);
    expect(test.widget<ListTile>(participantTile).onTap, isNotNull);
    expect(tester.widget<TextButton>(action).onPressed, isNotNull);
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
    expect(
      tester
          .widget<TextButton>(
            find.byKey(
              TestIds.key(TestIds.evaluationUndoCannotEvaluate('u1')),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.text('Undo'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('CTA stays disabled until every card is ready', (tester) async {
    final (_, _, cubit) = await pump(tester);
    final submit = tester.widget<FilledButton>(
      find.byKey(TestIds.key(TestIds.evaluationSubmit)),
    );
    expect(submit.onPressed, isNull);
    // Issue #161: the blocker is stated as remaining work, never as a control
    // the reviewer has to switch off.
    expect(find.textContaining('Left to review: 1.'), findsOneWidget);
    expect(find.textContaining('Send stays unavailable'), findsNothing);
    await cubit.close();
  });

  testWidgets('blocked footer fits narrow large text without overflow', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (_, _, cubit) = await pump(
      tester,
      surfaceSize: const Size(320, 700),
      textScaler: const TextScaler.linear(2),
    );
    expect(find.textContaining('Left to review: 1.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await cubit.close();
  });

  testWidgets('Undo on a Cannot evaluate card clears noBasis', (tester) async {
    final repository = FakeEvaluationRepository()
      ..participantsResult = [
        participant.copyWith(
          currentValue: EvaluationValue.noBasis,
          isSubmitted: true,
          rowStatus: 1,
        ),
      ];
    final (test, _, cubit) = await pump(tester, repositoryArg: repository);
    final undo = find.byKey(
      TestIds.key(TestIds.evaluationUndoCannotEvaluate('u1')),
    );
    expect(find.text('Undo'), findsOneWidget);
    await test.tap(undo);
    await test.pumpAndSettle();
    expect(repository.draftDeleteCalls, 1);
    expect(cubit.state.participants.single.currentValue, isNull);
    expect(cubit.state.participants.single.isSubmitted, isFalse);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Review'), findsOneWidget);
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
          rowStatus: 1,
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
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Helped somewhat'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
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
      scrollable: find.byType(Scrollable).first,
    );
    final tile = test.widget<ListTile>(
      find.byKey(TestIds.key(TestIds.evaluationParticipant('u1'))),
    );
    expect(tile.trailing, isNull);
    expect(find.text('Not reviewed'), findsOneWidget);
    expect(test.takeException(), isNull);
    await cubit.close();
  });

  const liveWindow = ReviewWindowInfo(
    beaconId: 'b1',
    hasWindow: true,
    closesAt: '2026-08-30T12:00:00Z',
    userReviewStatus: 1,
    totalCount: 1,
    requiredTotal: 1,
  );
  final sentWindow = liveWindow.copyWith(
    userReviewStatus: 2,
    sentAt: DateTime.utc(2026, 8, 20),
  );
  const optional = EvaluationParticipant(
    userId: 'u2',
    displayName: 'Bob',
    role: EvaluationParticipantRole.formerCommitter,
    isOptional: true,
  );

  testWidgets('first fill offers Send reviews, not Send changes', (
    tester,
  ) async {
    final repository = FakeEvaluationRepository()
      ..participantsResult = [participant.copyWith(rowStatus: 1)];
    final (_, _, cubit) = await pump(tester, repositoryArg: repository);
    expect(cubit.state.packageState, ReviewPackageState.readyToSend);
    expect(find.text('Send reviews'), findsOneWidget);
    expect(find.text('Send changes'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(TestIds.key(TestIds.evaluationSubmit)))
          .onPressed,
      isNotNull,
    );
    await cubit.close();
  });

  testWidgets('required complete and optional untouched enables the CTA', (
    tester,
  ) async {
    final repository = FakeEvaluationRepository()
      ..participantsResult = [participant.copyWith(rowStatus: 1), optional];
    final (_, _, cubit) = await pump(
      tester,
      repositoryArg: repository,
      window: liveWindow.copyWith(totalCount: 2, optionalTotal: 1),
    );
    expect(cubit.state.packageState, ReviewPackageState.readyToSend);
    expect(
      tester
          .widget<FilledButton>(find.byKey(TestIds.key(TestIds.evaluationSubmit)))
          .onPressed,
      isNotNull,
    );
    expect(find.text('1 of 1 required · 0 of 1 optional'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('after a send the screen stays and shows the sent status', (
    tester,
  ) async {
    final repository = _PackageRepository()
      ..participantsResult = [participant.copyWith(rowStatus: 1)]
      ..windowAfterFinalize = sentWindow
      ..participantsAfterFinalize = [
        participant.copyWith(rowStatus: 2, isSubmitted: true),
      ];
    final (test, _, cubit) = await pump(tester, repositoryArg: repository);
    await test.tap(find.byKey(TestIds.key(TestIds.evaluationSubmit)));
    await test.pumpAndSettle();

    expect(repository.finalizeCalls, 1);
    expect(cubit.state.packageState, ReviewPackageState.sent);
    // The screen stayed: the checklist is still on screen.
    expect(
      find.byKey(TestIds.key(TestIds.evaluationParticipant('u1'))),
      findsOneWidget,
    );
    final submit = find.byKey(TestIds.key(TestIds.evaluationSubmit));
    if (submit.evaluate().isNotEmpty) {
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    }
    expect(
      find.byKey(TestIds.key(TestIds.evaluationPackageStatus)),
      findsOneWidget,
    );
    expect(find.textContaining('Reviews sent'), findsOneWidget);
    expect(find.byKey(TestIds.key(TestIds.evaluationDone)), findsOneWidget);
    await cubit.close();
  });

  testWidgets('Done on a sent package opens the request when nothing can pop', (
    tester,
  ) async {
    final repository = FakeEvaluationRepository()
      ..participantsResult = [
        participant.copyWith(rowStatus: 2, isSubmitted: true),
      ];
    final (test, _, cubit) = await pump(
      tester,
      repositoryArg: repository,
      window: sentWindow,
    );
    await test.tap(find.byKey(TestIds.key(TestIds.evaluationDone)));
    await test.pumpAndSettle();

    expect(lastRouter.replaced, hasLength(1));
    expect(lastRouter.replaced.single, isA<BeaconViewRoute>());
    expect((lastRouter.replaced.single as BeaconViewRoute).args, isNotNull);
    await cubit.close();
  });

  testWidgets('editing a card after a send offers Send changes', (tester) async {
    final repository = _PackageRepository()
      ..participantsResult = [
        participant.copyWith(
          rowStatus: 2,
          isSubmitted: true,
          currentValue: EvaluationValue.pos1,
        ),
      ]
      ..windowAfterSubmit = liveWindow.copyWith(
        userReviewStatus: 1,
        sentAt: DateTime.utc(2026, 8, 20),
      );
    final (test, _, cubit) = await pump(
      tester,
      repositoryArg: repository,
      window: sentWindow,
    );
    expect(cubit.state.packageState, ReviewPackageState.sent);

    await test.tap(find.byKey(TestIds.key(TestIds.evaluationCannotEvaluate('u1'))));
    await test.pumpAndSettle();
    await test.tap(find.text('Cannot evaluate').last);
    await test.pumpAndSettle();

    expect(cubit.state.packageState, ReviewPackageState.changedNotSent);
    expect(find.text('Send changes'), findsOneWidget);
    expect(find.text('Changes not sent'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(TestIds.key(TestIds.evaluationSubmit)))
          .onPressed,
      isNotNull,
    );
    await cubit.close();
  });

  testWidgets('skip hides an optional card without calling the cubit', (
    tester,
  ) async {
    final repository = FakeEvaluationRepository()
      ..participantsResult = [participant.copyWith(rowStatus: 1), optional];
    final (test, _, cubit) = await pump(
      tester,
      repositoryArg: repository,
      window: liveWindow.copyWith(totalCount: 2, optionalTotal: 1),
    );
    expect(
      find.byKey(TestIds.key(TestIds.evaluationParticipant('u2'))),
      findsOneWidget,
    );
    final skip = find.widgetWithText(TextButton, 'Skip');
    await test.ensureVisible(skip);
    await test.pumpAndSettle();
    await test.tap(skip);
    await test.pumpAndSettle();

    expect(
      find.byKey(TestIds.key(TestIds.evaluationParticipant('u2'))),
      findsNothing,
    );
    expect(repository.submitCalls, 0);
    expect(repository.draftDeleteCalls, 0);
    expect(cubit.state.participants, hasLength(2));
    await cubit.close();
  });

  testWidgets('skipping an optional card with a stored row keeps it in the package', (
    tester,
  ) async {
    final repository = FakeEvaluationRepository()
      ..participantsResult = [
        participant.copyWith(rowStatus: 1),
        optional.copyWith(rowStatus: 1, currentValue: EvaluationValue.pos1),
      ];
    final (test, _, cubit) = await pump(
      tester,
      repositoryArg: repository,
      window: liveWindow.copyWith(totalCount: 2, optionalTotal: 1),
    );
    final skip = find.widgetWithText(TextButton, 'Skip');
    await test.ensureVisible(skip);
    await test.pumpAndSettle();
    await test.tap(skip);
    await test.pumpAndSettle();

    expect(
      find.byKey(TestIds.key(TestIds.evaluationParticipant('u2'))),
      findsNothing,
    );
    final stored = cubit.state.participants.firstWhere((p) => p.userId == 'u2');
    expect(stored.rowStatus, 1);
    expect(stored.currentValue, EvaluationValue.pos1);
    expect(repository.submitCalls, 0);
    expect(repository.draftDeleteCalls, 0);
    await cubit.close();
  });

  testWidgets('viewerPackageOptional renders the own-package notice', (
    tester,
  ) async {
    final repository = FakeEvaluationRepository()
      ..participantsResult = [participant.copyWith(rowStatus: 1)];
    final (_, _, cubit) = await pump(
      tester,
      repositoryArg: repository,
      window: liveWindow.copyWith(viewerPackageOptional: true),
    );
    expect(
      find.textContaining('You no longer take part in this request'),
      findsOneWidget,
    );
    await cubit.close();
  });

  testWidgets('sections render at 360px and textScaler 2.0', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeEvaluationRepository()
      ..participantsResult = [participant.copyWith(rowStatus: 1), optional];
    final (_, _, cubit) = await pump(
      tester,
      repositoryArg: repository,
      surfaceSize: const Size(360, 800),
      textScaler: const TextScaler.linear(2),
      window: liveWindow.copyWith(totalCount: 2, optionalTotal: 1),
    );
    // A long header block can silently stop the list from building its items:
    // assert the card itself, not just the absence of an overflow.
    // The header stack is taller than the viewport at this combination, so the
    // sections live below the fold. They must still be reachable: a list that
    // silently stops building its items fails here, with no overflow error.
    expect(find.text('Required', skipOffstage: false), findsOneWidget);
    final card = find.byKey(TestIds.key(TestIds.evaluationParticipant('u1')));
    await tester.scrollUntilVisible(
      card,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(card, findsOneWidget);
    final optionalCard = find.byKey(
      TestIds.key(TestIds.evaluationParticipant('u2')),
    );
    await tester.scrollUntilVisible(
      optionalCard,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(optionalCard, findsOneWidget);
    expect(
      find.text('Optional · participation ended', skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await cubit.close();
  });
}
