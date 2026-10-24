// #706: the Field's presence watch pauses with the Field. While another Home
// tab is active, or a root route (a Request, a profile, …) covers Home, the
// field asks for nobody's presence; coming back re-watches its people. The
// cubit's own setVisible is unit-tested in constellation_presence_test.dart;
// this pins the screen path that drives it from the router.

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/app/router/root_router.gr.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/constellation_presence.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_presence_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_reference_fixture.dart';

/// Records the watch each presence source holds now.
final class _RecordingPresenceRepository implements PresenceRepository {
  final watches = <String, Set<String>>{};

  @override
  Stream<Map<String, UserPresenceStatus>> get presenceChanges =>
      const Stream.empty();

  @override
  UserPresenceStatus? statusOf(String userId) => null;

  @override
  void watch(String sourceKey, Set<String> userIds) =>
      watches[sourceKey] = {...userIds};

  @override
  void unwatch(String sourceKey) => watches.remove(sourceKey);

  Set<String>? get field => watches[ConstellationPresenceCubit.sourceKey];
}

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

ConstellationTrustEdgeEntity _edge(String src, String dst) =>
    ConstellationTrustEdgeEntity(src: src, dst: dst, tier: 1);

/// Maria trusts back (a friend), Yuri is only trusted, Igor is no contact:
/// the field watches Maria and Yuri.
ConstellationField _field() => ConstellationField(
  loadedAt: DateTime.utc(2026, 10, 23),
  context: '',
  peers: const [
    ConstellationPerson(id: 'm', displayName: 'Maria'),
    ConstellationPerson(id: 'y', displayName: 'Yuri'),
    ConstellationPerson(id: 'i', displayName: 'Igor'),
  ],
  edges: [
    _edge('ego', 'm'),
    _edge('m', 'ego'),
    _edge('ego', 'y'),
    _edge('m', 'i'),
  ],
  directContactIds: const ['m', 'y'],
);

const _fieldPeople = {'m', 'y'};

/// A root route that covers Home, as a Request does.
const _requestRouteName = 'TestRequestRoute';

/// Home with its tabs; only the Constellation tab holds the real screen.
class _TestHomeShell extends StatelessWidget {
  const _TestHomeShell();

  @override
  Widget build(BuildContext context) => AutoTabsRouter(
    routes: [for (final spec in HomeTabSpec.all) spec.rootRoute()],
    duration: Duration.zero,
    transitionBuilder: (_, child, _) => child,
    builder: (_, child) => child,
  );
}

/// Hosts the real screen without its route wrapper: a page whose top widget
/// implements AutoRouteWrapper gets wrapped by auto_route, and the real
/// wrapper builds its cubits from DI. The test provides them above the app.
class _FieldTabHost extends StatelessWidget {
  const _FieldTabHost();

  @override
  Widget build(BuildContext context) => const ConstellationScreen();
}

RootStackRouter _router() => RootStackRouter.build(
  routes: [
    AutoRoute(
      page: PageInfo(HomeRoute.name, builder: (_) => const _TestHomeShell()),
      path: '/home',
      initial: true,
      children: [
        for (final spec in HomeTabSpec.all)
          AutoRoute(
            page: PageInfo(
              spec.rootRoute().routeName,
              builder: (_) => spec.tab == HomeTab.constellation
                  ? const _FieldTabHost()
                  : Text('${spec.tab.name}-root'),
            ),
            path: spec.path.split('/').last,
            initial: spec.tab == HomeTab.work,
          ),
      ],
    ),
    AutoRoute(
      page: PageInfo(
        _requestRouteName,
        builder: (_) => const Scaffold(body: Text('request')),
      ),
      path: '/request',
    ),
  ],
);

typedef _Harness = ({
  RootStackRouter router,
  _RecordingPresenceRepository presence,
  ConstellationPresenceCubit presenceCubit,
});

Future<_Harness> _mount(WidgetTester tester) async {
  final cubit = (await tester.runAsync(
    () => loadReferenceCubit(field: _field()),
  ))!;
  final presence = _RecordingPresenceRepository();
  // Wired to the field's people exactly as ConstellationScreen.wrappedRoute
  // wires it.
  Set<String> watchIdsOf(ConstellationState state) =>
      constellationPresenceWatchIds(
        field: state.field,
        composition: state.composition,
        viewerId: kRefEgo.id,
      );
  final presenceCubit = ConstellationPresenceCubit(
    initialWatchIds: watchIdsOf(cubit.state),
    watchIds: cubit.stream
        .distinct(
          (a, b) =>
              identical(a.field, b.field) &&
              identical(a.composition, b.composition),
        )
        .map(watchIdsOf),
    repository: presence,
  );
  final selection = ConstellationSelectionCubit();
  final reselect = HomeTabReselectCubit();
  final router = _router();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    router.dispose();
    await presenceCubit.close();
    await selection.close();
    await reselect.close();
    await cubit.close();
  });
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ConstellationCubit>.value(value: cubit),
        BlocProvider<ConstellationPresenceCubit>.value(value: presenceCubit),
        BlocProvider<ConstellationSelectionCubit>.value(value: selection),
        BlocProvider<HomeTabReselectCubit>.value(value: reselect),
        BlocProvider<GraphPersonContextCubit>(
          create: (_) => _StubContextCubit(),
        ),
        BlocProvider<ScreenCubit>(
          create: (_) => ScreenCubit(FakeUiEffectPort()),
        ),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        routerConfig: router.config(),
        builder: (_, child) => TenturaResponsiveScope(child: child!),
      ),
    ),
  );
  await _settle(tester);
  expect(router.current.name, HomeRoute.name);
  return (router: router, presence: presence, presenceCubit: presenceCubit);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

TabsRouter _tabs(RootStackRouter router) =>
    router.innerRouterOf<TabsRouter>(HomeRoute.name)!;

int _indexOf(HomeTab tab) => HomeTabSpec.forTab(tab).index;

/// Opens the Field tab and checks it watches the field's people.
Future<void> _openField(WidgetTester tester, _Harness h) async {
  _tabs(h.router).setActiveIndex(_indexOf(HomeTab.constellation));
  await _settle(tester);
  expect(find.byType(ConstellationScreen), findsOneWidget);
  expect(h.presence.field, _fieldPeople, reason: 'the open Field watches');
  expect(h.presenceCubit.watchedIds, _fieldPeople);
}

void main() {
  testWidgets('switching to another Home tab drops the Field presence watch; '
      'coming back re-watches its people', (tester) async {
    final h = await _mount(tester);
    await _openField(tester, h);

    _tabs(h.router).setActiveIndex(_indexOf(HomeTab.inbox));
    await _settle(tester);
    expect(
      find.byType(ConstellationScreen, skipOffstage: false),
      findsOneWidget,
      reason: 'the Field tab stays mounted behind the other tab',
    );
    expect(h.presence.field, isNull, reason: 'hidden, the Field watches none');
    expect(h.presenceCubit.watchedIds, isEmpty);

    _tabs(h.router).setActiveIndex(_indexOf(HomeTab.constellation));
    await _settle(tester);
    expect(h.presence.field, _fieldPeople);
    expect(h.presenceCubit.watchedIds, _fieldPeople);
  });

  testWidgets('a root route pushed over Home drops the Field presence watch; '
      'popping it re-watches', (tester) async {
    final h = await _mount(tester);
    await _openField(tester, h);

    unawaited(h.router.push(const PageRouteInfo<void>(_requestRouteName)));
    await _settle(tester);
    expect(h.router.current.name, _requestRouteName);
    expect(find.text('request'), findsOneWidget);
    expect(h.presence.field, isNull, reason: 'covered, the Field watches none');
    expect(h.presenceCubit.watchedIds, isEmpty);

    h.router.pop();
    await _settle(tester);
    expect(h.router.current.name, HomeRoute.name);
    expect(h.presence.field, _fieldPeople);
    expect(h.presenceCubit.watchedIds, _fieldPeople);
  });
}
