// Routing contract for the per-tab home branches (adaptive-router Phase 2,
// Step 1): browse details (beacon view) live inside the active tab's own
// nested stack, and the legacy root-level `/beacon/view/:id` path keeps
// resolving by redirecting into the active branch.
//
// Uses the real [RootRouter] route table with lightweight builder overrides
// (generated `PageInfo.page` statics are mutable) so no feature DI is needed.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

class _FakeAuthCubit extends Fake implements AuthCubit {
  _FakeAuthCubit({bool bootstrapping = false})
    : _state = AuthState(
        updatedAt: DateTime(2026),
        currentAccountId: bootstrapping ? '' : 'U1',
        isBootstrapping: bootstrapping,
      );

  AuthState _state;

  final _controller = StreamController<AuthState>.broadcast();

  @override
  AuthState get state => _state;

  @override
  Stream<AuthState> get stream => _controller.stream;

  /// Simulates the cold-start session probe finishing (bootstrap → signed in),
  /// which fires [RootRouter.reevaluateListenable] and re-runs route guards.
  void completeSignIn() {
    _state = AuthState(updatedAt: DateTime(2026), currentAccountId: 'U1');
    _controller.add(_state);
  }

  Future<void> shutDown() => _controller.close();
}

class _FakeSettingsCubit extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

/// Mirrors the [AutoTabsRouter] shell that `home_screen.dart` builds (same
/// branch routes, no chrome) so branch routers exist for redirect guards.
///
/// [wrapShell] reproduces the `HomeScreen.wrappedRoute` account-arrival
/// reparenting: when the signed-in account id becomes known the home subtree
/// gains wrapper widgets (`BlocProvider` > `InboxNeedsMeReporter`), changing
/// its element depth mid-session. The [GlobalKey]ed subtree mirrors
/// `HomeScreen._shellSubtreeKey` — without it the tabs router is disposed on
/// reparent and rebuilt from bare tab roots, dropping any pushed branch
/// detail (the production bug this file pins down).
class _TestHomeShell extends StatelessWidget {
  const _TestHomeShell();

  static final wrapShell = ValueNotifier<bool>(false);

  static final _shellSubtreeKey = GlobalKey(
    debugLabel: 'TestHomeShellSubtree',
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: wrapShell,
    builder: (_, wrapped, _) {
      final tabs = KeyedSubtree(
        key: _shellSubtreeKey,
        child: AutoTabsRouter(
          routes: [
            workTabShell(),
            inboxTabShell(),
            networkTabShell(),
            meTabShell(),
          ],
          duration: Duration.zero,
          transitionBuilder: (_, child, _) => child,
          builder: (_, child) => child,
        ),
      );
      return wrapped
          ? SizedBox(
              child: ColoredBox(color: const Color(0x00000000), child: tabs),
            )
          : tabs;
    },
  );
}

PageInfo _labelPage(String name, String label) => PageInfo(
  name,
  builder: (_) => Text(label, textDirection: TextDirection.ltr),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final PageInfo realHomePage;
  late final PageInfo realMyWorkPage;
  late final PageInfo realInboxPage;
  late final PageInfo realFriendsPage;
  late final PageInfo realProfilePage;
  late final PageInfo realBeaconViewPage;
  late final PageInfo realAuthLoginPage;

  setUpAll(() {
    realHomePage = HomeRoute.page;
    realMyWorkPage = MyWorkRoute.page;
    realInboxPage = InboxRoute.page;
    realFriendsPage = FriendsRoute.page;
    realProfilePage = ProfileRoute.page;
    realBeaconViewPage = BeaconViewRoute.page;
    realAuthLoginPage = AuthLoginRoute.page;

    HomeRoute.page = PageInfo(
      HomeRoute.name,
      builder: (_) => const _TestHomeShell(),
    );
    MyWorkRoute.page = _labelPage(MyWorkRoute.name, 'my-work-root');
    InboxRoute.page = _labelPage(InboxRoute.name, 'inbox-root');
    FriendsRoute.page = _labelPage(FriendsRoute.name, 'friends-root');
    ProfileRoute.page = _labelPage(ProfileRoute.name, 'profile-root');
    AuthLoginRoute.page = _labelPage(AuthLoginRoute.name, 'auth-login');
    BeaconViewRoute.page = PageInfo(
      BeaconViewRoute.name,
      builder: (data) {
        final id = data.inheritedPathParams.getString('id', '');
        final entry = data.queryParams.optString('entry') ?? '';
        final viewTab = data.queryParams.optString('tab') ?? '';
        return Text(
          'beacon-view:$id:$entry:$viewTab',
          textDirection: TextDirection.ltr,
        );
      },
    );
  });

  tearDownAll(() {
    HomeRoute.page = realHomePage;
    MyWorkRoute.page = realMyWorkPage;
    InboxRoute.page = realInboxPage;
    FriendsRoute.page = realFriendsPage;
    ProfileRoute.page = realProfilePage;
    BeaconViewRoute.page = realBeaconViewPage;
    AuthLoginRoute.page = realAuthLoginPage;
  });

  late RootRouter router;
  late _FakeAuthCubit authCubit;

  tearDown(() async {
    router.dispose();
    await authCubit.shutDown();
  });

  /// Pumps the real [RootRouter] with web-parity parsing
  /// (`includePrefixMatches: false`, as in WASM builds where `kIsWeb` flips
  /// the `config()` default).
  ///
  /// With [viaPlatform] the link arrives as the platform initial route
  /// (browser URL-bar load: route information parser → [RootRouter
  /// .deepLinkTransformer] → delegate), exactly like app.dart wires it;
  /// otherwise it is injected through a plain [DeepLink.path].
  Future<void> pumpRouter(
    WidgetTester tester, {
    required String initialPath,
    bool viaPlatform = false,
    bool bootstrapping = false,
  }) async {
    authCubit = _FakeAuthCubit(bootstrapping: bootstrapping);
    router = RootRouter(
      Logger('test'),
      authCubit,
      _FakeSettingsCubit(),
      PostJoinNavigationCubit(),
    );
    if (viaPlatform) {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = initialPath;
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
    }
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router.config(
          deepLinkBuilder: viaPlatform
              ? router.deepLinkBuilder
              : (_) => DeepLink.path(initialPath),
          deepLinkTransformer: router.deepLinkTransformer,
          includePrefixMatches: false,
          reevaluateListenable: router.reevaluateListenable,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String currentUrl() => router.navigationHistory.urlState.url;

  group('home tab branch routing', () {
    testWidgets(
      'restores nested beacon view from a full branch URL (browser refresh)',
      (tester) async {
        await pumpRouter(
          tester,
          initialPath: '/home/work/beacon/view/B123?entry=my_work',
        );

        expect(find.text('beacon-view:B123:my_work:'), findsOneWidget);
        expect(currentUrl(), '/home/work/beacon/view/B123?entry=my_work');
      },
    );

    testWidgets(
      'restores nested beacon view from a platform initial route '
      '(browser URL bar)',
      (tester) async {
        await pumpRouter(
          tester,
          initialPath: '/home/work/beacon/view/B123?entry=my_work',
          viaPlatform: true,
        );

        expect(find.text('beacon-view:B123:my_work:'), findsOneWidget);
        expect(currentUrl(), '/home/work/beacon/view/B123?entry=my_work');
      },
    );

    testWidgets(
      'keeps nested beacon view when auth bootstrap completes '
      '(guard reevaluation)',
      (tester) async {
        await pumpRouter(
          tester,
          initialPath: '/home/work/beacon/view/B123?entry=my_work',
          viaPlatform: true,
          bootstrapping: true,
        );
        expect(find.text('beacon-view:B123:my_work:'), findsOneWidget);

        authCubit.completeSignIn();
        await tester.pumpAndSettle();

        expect(find.text('beacon-view:B123:my_work:'), findsOneWidget);
        expect(currentUrl(), '/home/work/beacon/view/B123?entry=my_work');
      },
    );

    testWidgets(
      'pushPath of legacy /beacon/view/:id lands in the active tab branch',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home');
        expect(find.text('my-work-root'), findsOneWidget);

        await router.pushPath('/beacon/view/B123?entry=my_work');
        await tester.pumpAndSettle();

        expect(find.text('beacon-view:B123:my_work:'), findsOneWidget);
        expect(currentUrl(), '/home/work/beacon/view/B123?entry=my_work');
        // Rail stays: the home shell (tabs scope) is still mounted.
        expect(
          find.byType(_TestHomeShell, skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'pushPath of legacy /beacon/view/:id targets the active (non-default) '
      'tab branch',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home/inbox');
        expect(find.text('inbox-root'), findsOneWidget);

        await router.pushPath('/beacon/view/B321?entry=inbox');
        await tester.pumpAndSettle();

        expect(find.text('beacon-view:B321:inbox:'), findsOneWidget);
        expect(currentUrl(), '/home/inbox/beacon/view/B321?entry=inbox');
      },
    );

    testWidgets(
      'pushPath from inside a branch (context.router at a tab screen) '
      'lands in that branch, not on the root stack',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home');
        expect(find.text('my-work-root'), findsOneWidget);

        // Card taps call `context.router.pushPath(...)` where context.router
        // is the branch's nested StackRouter — not the RootRouter.
        final branchRouter = router
            .innerRouterOf<TabsRouter>(HomeRoute.name)
            ?.stackRouterOfIndex(0);
        expect(branchRouter, isNotNull, reason: 'work branch router exists');
        await branchRouter!.pushPath('/beacon/view/B123?entry=my_work');
        await tester.pumpAndSettle();

        expect(find.text('beacon-view:B123:my_work:'), findsOneWidget);
        expect(currentUrl(), '/home/work/beacon/view/B123?entry=my_work');
        expect(
          find.byType(_TestHomeShell, skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'legacy /beacon/room/:id still resolves to beacon view in room mode',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home');

        await router.navigatePath('/beacon/room/B123');
        await tester.pumpAndSettle();

        expect(find.text('beacon-view:B123:deep_link:room'), findsOneWidget);
      },
    );

    testWidgets(
      'keeps nested beacon view when the home shell subtree is reparented '
      '(HomeScreen wrappedRoute account arrival)',
      (tester) async {
        _TestHomeShell.wrapShell.value = false;
        addTearDown(() => _TestHomeShell.wrapShell.value = false);
        await pumpRouter(
          tester,
          initialPath: '/home/work/beacon/view/B123?entry=my_work',
          viaPlatform: true,
        );
        expect(find.text('beacon-view:B123:my_work:'), findsOneWidget);

        // Account id arrives: HomeScreen.wrappedRoute swaps in the
        // BlocProvider/InboxNeedsMeReporter wrappers around the tabs shell.
        _TestHomeShell.wrapShell.value = true;
        await tester.pumpAndSettle();

        expect(find.text('beacon-view:B123:my_work:'), findsOneWidget);
        expect(currentUrl(), '/home/work/beacon/view/B123?entry=my_work');
      },
    );

    testWidgets(
      'branch back pop returns to the tab root and keeps the shell',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home');
        await router.pushPath('/beacon/view/B123');
        await tester.pumpAndSettle();
        expect(find.text('beacon-view:B123::'), findsOneWidget);

        await router.maybePopTop();
        await tester.pumpAndSettle();

        expect(find.text('my-work-root'), findsOneWidget);
        expect(currentUrl(), '/home/work');
      },
    );
  });
}
