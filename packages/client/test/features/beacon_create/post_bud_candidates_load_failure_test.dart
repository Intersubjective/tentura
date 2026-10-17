// The bud form's invite step when the Post's members cannot be loaded: a
// failed load must be shown as a failure (not an endless spinner) with a retry
// action that keeps what the budder typed, and the bud cannot be submitted
// while the membership is unavailable (loading or failed).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import 'post_bud_fakes.dart';

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

class _Router extends Mock implements StackRouter {
  final opened = <PageRouteInfo>[];

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    opened.add(route);
    return null;
  }
}

const _profiles = [
  Profile(id: 'writer', displayName: 'Writer Wanda'),
  Profile(id: 'silent', displayName: 'Silent Sam'),
  Profile(id: 'other', displayName: 'Other Olga'),
];

const _retryKey = Key('PostBud.RetryCandidates');
const _submitKey = Key('PostBud.SubmitButton');

Future<({BudHarness h, BeaconCreateCubit cubit, _Router router})> _pump(
  WidgetTester tester, {
  required void Function(FakePostBudPort port) seed,
}) async {
  final effects = FakeUiEffectPort();
  GetIt.I
    ..registerSingleton<Env>(const Env())
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<AuthCase>(
      buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
    )
    ..registerSingleton<ContextRepository>(_ContextRepositoryFake());
  addTearDown(GetIt.I.reset);

  final h = BudHarness(parent: budPost(), profiles: _profiles);
  seed(h.port);
  final cubit = h.cubit(effects: effects);
  addTearDown(cubit.close);

  const surface = Size(800, 1600);
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = _Router();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(size: surface),
        child: TenturaResponsiveScope(
          child: RouterScope(
            controller: router,
            stateHash: 0,
            inheritableObserversBuilder: () => const [],
            child: StackRouterScope(
              controller: router,
              stateHash: 0,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider(create: (_) => ContextCubit()),
                  BlocProvider<BeaconCreateCubit>.value(value: cubit),
                ],
                child: const BeaconCreateScreen(
                  parentBeaconId: kBudPostId,
                  sourceMessageId: kBudSourceMessageId,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester, frames: 20);
  return (h: h, cubit: cubit, router: router);
}

/// Not `pumpAndSettle`: the loading spinner never settles.
Future<void> _settle(WidgetTester tester, {int frames = 5}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openInviteStep(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('PostBud.NextButton')));
  await _settle(tester);
}

Finder _inviteeTile(String userId) => find.descendant(
  of: find.byKey(ValueKey('PostBud.Invitee.$userId')),
  matching: find.byType(CheckboxListTile),
);

bool _ticked(WidgetTester tester, String userId) =>
    tester.widget<CheckboxListTile>(_inviteeTile(userId)).value ?? false;

Finder _titleField() => find.byType(TextFormField).at(0);

Finder _descriptionField() => find.byType(TextFormField).at(1);

String _fieldText(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(
      find.descendant(of: field, matching: find.byType(TextField)),
    ).controller!.text;

bool _submitEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(_submitKey)).onPressed != null;

void main() {
  testWidgets(
    'a failed member load shows a retry action instead of a spinner and '
    'keeps submit disabled',
    (tester) async {
      final opened = await _pump(
        tester,
        seed: (port) => port
          ..candidatesError = Exception('offline')
          ..candidates = [budCandidate('silent', pretick: true)],
      );
      await _openInviteStep(tester);

      expect(find.byKey(const Key('PostBud.InviteStep')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(_retryKey), findsOneWidget);
      expect(_submitEnabled(tester), isFalse);

      await tester.tap(find.byKey(_submitKey), warnIfMissed: false);
      await _settle(tester);
      expect(opened.h.port.calls, isEmpty);
    },
  );

  testWidgets(
    'retrying after a failed member load shows the members with their '
    'ticks, keeps the typed form and then allows the bud',
    (tester) async {
      final opened = await _pump(
        tester,
        seed: (port) => port
          ..candidatesError = Exception('offline')
          ..candidates = [
            budCandidate('silent', pretick: true),
            budCandidate('writer', hasWritten: true, pretick: true),
            budCandidate('other'),
          ],
      );
      await tester.enterText(_titleField(), 'Ladder for Saturday');
      await tester.enterText(_descriptionField(), 'Needed from noon.');
      await _openInviteStep(tester);
      expect(find.byKey(_retryKey), findsOneWidget);
      expect(_submitEnabled(tester), isFalse);
      await tester.tap(find.byKey(_submitKey), warnIfMissed: false);
      await _settle(tester);
      expect(opened.h.port.calls, isEmpty);

      opened.h.port.candidatesError = null;
      await tester.tap(find.byKey(_retryKey));
      await _settle(tester);

      expect(opened.cubit.state.title, 'Ladder for Saturday');
      expect(opened.cubit.state.description, 'Needed from noon.');
      expect(find.byKey(_retryKey), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Writer Wanda'), findsOneWidget);
      expect(find.text('Silent Sam'), findsOneWidget);
      expect(find.text('Other Olga'), findsOneWidget);
      expect(_ticked(tester, 'writer'), isTrue);
      expect(_ticked(tester, 'silent'), isTrue);
      expect(_ticked(tester, 'other'), isFalse);
      expect(find.byKey(const ValueKey('PostBud.Note.writer')), findsOneWidget);
      expect(find.byKey(const ValueKey('PostBud.Note.silent')), findsOneWidget);
      expect(find.byKey(const ValueKey('PostBud.Note.other')), findsNothing);
      expect(_submitEnabled(tester), isTrue);

      // The form step still holds what was typed before the failure.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
      await _settle(tester);
      expect(_fieldText(tester, _titleField()), 'Ladder for Saturday');
      expect(_fieldText(tester, _descriptionField()), 'Needed from noon.');
      await _openInviteStep(tester);
      expect(_ticked(tester, 'writer'), isTrue);
      expect(_ticked(tester, 'silent'), isTrue);
      expect(_ticked(tester, 'other'), isFalse);
      expect(_submitEnabled(tester), isTrue);

      await tester.enterText(
        find.byKey(const ValueKey('PostBud.Note.writer')),
        'You know the ladder',
      );
      await tester.tap(_inviteeTile('other'));
      await _settle(tester);
      expect(_ticked(tester, 'other'), isTrue);

      await tester.tap(find.byKey(_submitKey));
      await _settle(tester);
      final call = opened.h.port.calls.single;
      expect(call.title, 'Ladder for Saturday');
      expect(call.description, 'Needed from noon.');
      expect(
        call.invitees.map((i) => i.userId),
        unorderedEquals(['silent', 'writer', 'other']),
      );
      expect(
        call.invitees.firstWhere((i) => i.userId == 'writer').note,
        'You know the ladder',
      );
    },
  );

  testWidgets('a retry that fails again keeps the retry action', (
    tester,
  ) async {
    final opened = await _pump(
      tester,
      seed: (port) => port
        ..candidatesError = Exception('offline')
        ..candidates = [budCandidate('silent', pretick: true)],
    );
    await _openInviteStep(tester);

    await tester.tap(find.byKey(_retryKey));
    await _settle(tester);

    expect(opened.h.port.calls, isEmpty);
    expect(find.byKey(_retryKey), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_submitEnabled(tester), isFalse);
  });

  testWidgets(
    'while the members are still loading the spinner shows, there is no '
    'retry action and submit is disabled',
    (tester) async {
      final opened = await _pump(
        tester,
        seed: (port) => port
          ..candidatesGate = Completer<void>()
          ..candidates = [budCandidate('silent', pretick: true)],
      );
      await _openInviteStep(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(_retryKey), findsNothing);
      expect(_submitEnabled(tester), isFalse);

      opened.h.port.candidatesGate!.complete();
      await _settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_submitEnabled(tester), isTrue);
    },
  );
}
