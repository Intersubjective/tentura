// Issue #735 (#735a): «Create new request» from a discussion message opened
// the editor like a standalone request, with nothing saying it becomes a
// child of the request it came from. The form now names the parent above
// the title; a Post bud (its own flow) and a standalone request do not.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/beacon_create/ui/widget/info_tab.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import 'fake_beacon_ports.dart';
import 'post_bud_fakes.dart';

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

class _Router extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;
}

const _parentTitle = 'GQ1024 Garden cleanup Saturday';

/// The parent of the child request: a Request, not a Post.
Beacon _parentRequest() => Beacon.empty.copyWith(
  id: kBudPostId,
  kind: BeaconKind.request,
  title: _parentTitle,
);

Future<void> _pump(
  WidgetTester tester, {
  required BeaconCreateCubit cubit,
  Locale locale = const Locale('en'),
}) async {
  const surface = Size(800, 1200);
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = _Router();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
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
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late FakeUiEffectPort effects;

  setUp(() {
    effects = FakeUiEffectPort();
    GetIt.I
      ..registerSingleton<Env>(const Env())
      ..registerSingleton<UiEffectPort>(effects)
      ..registerSingleton<AuthCase>(
        buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
      )
      ..registerSingleton<ContextRepository>(_ContextRepositoryFake());
  });

  tearDown(GetIt.I.reset);

  testWidgets('a child request from a message names its parent', (
    tester,
  ) async {
    final h = BudHarness(parent: _parentRequest());
    final cubit = h.cubit(effects: effects);
    addTearDown(cubit.close);

    await _pump(tester, cubit: cubit);

    expect(cubit.state.isChildMode, isTrue);
    expect(cubit.state.isPostBud, isFalse);
    expect(find.byKey(InfoTab.childOfBannerKey), findsOneWidget);
    expect(find.text('Child request of ‘$_parentTitle’'), findsOneWidget);
  });

  testWidgets('in Russian too', (tester) async {
    final h = BudHarness(parent: _parentRequest());
    final cubit = h.cubit(effects: effects);
    addTearDown(cubit.close);

    await _pump(tester, cubit: cubit, locale: const Locale('ru'));

    expect(find.text('Дочерний запрос для «$_parentTitle»'), findsOneWidget);
  });

  testWidgets('guard: a Post bud has its own flow and no such line', (
    tester,
  ) async {
    final h = BudHarness(parent: budPost());
    final cubit = h.cubit(effects: effects);
    addTearDown(cubit.close);

    await _pump(tester, cubit: cubit);

    expect(cubit.state.isPostBud, isTrue);
    expect(find.byKey(InfoTab.childOfBannerKey), findsNothing);
  });

  test('guard: a standalone new request has no parent to name', () async {
    final cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(),
      effects: effects,
    );
    addTearDown(cubit.close);

    expect(cubit.state.isChildMode, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.childParentTitle, isEmpty);
  });

  // #784 review: the title was a Future held by the cubit and read by a
  // FutureBuilder; it is now part of the cubit's state.
  test('the parent title is loaded into the state', () async {
    final h = BudHarness(parent: _parentRequest());
    final cubit = h.cubit(effects: effects);
    addTearDown(cubit.close);

    final state = await cubit.stream
        .firstWhere((s) => s.childParentTitle.isNotEmpty)
        .timeout(const Duration(seconds: 5));
    expect(state.childParentTitle, _parentTitle);
  });

  test('guard: a Post bud loads no parent title', () async {
    final h = BudHarness(parent: budPost());
    final cubit = h.cubit(effects: effects);
    addTearDown(cubit.close);

    await cubit.stream
        .firstWhere((s) => s.postBud != null)
        .timeout(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.childParentTitle, isEmpty);
  });
}
