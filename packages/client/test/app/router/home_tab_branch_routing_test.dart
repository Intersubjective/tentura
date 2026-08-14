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
import 'package:tentura/consts.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/home/ui/screen/home_screen.dart';
import 'package:tentura/features/home/ui/widget/home_shell_chrome_listenable.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

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
/// branch routes) so branch routers exist for redirect guards.
///
/// When [withCompactChrome] is true, mirrors HomeScreen's compact bottom-nav
/// gate and the history + [HomeShellChromeListenable] rebuild sources.
///
/// [wrapShell] reproduces the `HomeScreen.wrappedRoute` account-arrival
/// reparenting: when the signed-in account id becomes known the home subtree
/// gains wrapper widgets (`BlocProvider` > `InboxNeedsMeReporter`), changing
/// its element depth mid-session. The [GlobalKey]ed subtree mirrors
/// `HomeScreen._shellSubtreeKey` — without it the tabs router is disposed on
/// reparent and rebuilt from bare tab roots, dropping any pushed branch
/// detail (the production bug this file pins down).
class _TestHomeShell extends StatefulWidget {
  const _TestHomeShell({this.withCompactChrome = false});

  /// When true, render a stand-in bottom bar gated like HomeScreen compact.
  final bool withCompactChrome;

  static final wrapShell = ValueNotifier<bool>(false);

  static final _shellSubtreeKey = GlobalKey(
    debugLabel: 'TestHomeShellSubtree',
  );

  @override
  State<_TestHomeShell> createState() => _TestHomeShellState();
}

class _TestHomeShellState extends State<_TestHomeShell> {
  final _chrome = HomeShellChromeListenable();

  @override
  void dispose() {
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _TestHomeShell.wrapShell,
    builder: (_, wrapped, _) {
      final tabs = KeyedSubtree(
        key: _TestHomeShell._shellSubtreeKey,
        child: AutoTabsRouter(
          routes: [for (final spec in HomeTabSpec.all) spec.shell()],
          duration: Duration.zero,
          transitionBuilder: (_, child, _) => child,
          navigatorObservers: () => [HomeShellNavObserver(_chrome)],
          builder: (context, child) {
            if (!widget.withCompactChrome) return child;
            final tabsRouter = context.tabsRouter;
            return ListenableBuilder(
              listenable: Listenable.merge([
                context.router.root.navigationHistory,
                _chrome,
              ]),
              builder: (context, _) {
                final activeBranch = tabsRouter.stackRouterOfIndex(
                  tabsRouter.activeIndex,
                );
                final branchShowsDetail =
                    (activeBranch?.stackData.length ?? 1) > 1;
                return Scaffold(
                  body: child,
                  bottomNavigationBar: branchShowsDetail
                      ? null
                      : const SizedBox(
                          key: ValueKey('test-bottom-nav'),
                          height: 56,
                          child: Center(child: Text('bottom-nav')),
                        ),
                );
              },
            );
          },
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

int _countRoutePages(List<AutoRoute> routes, String pageName) {
  var count = 0;
  for (final route in routes) {
    if (route.page.name == pageName) {
      count++;
    }
    final children = route.children;
    if (children != null) {
      count += _countRoutePages(children, pageName);
    }
  }
  return count;
}

String? _parentSegmentOfRoute(List<AutoRoute> routes, String pageName) {
  for (final route in routes) {
    final children = route.children;
    if (children != null) {
      for (final child in children) {
        if (child.page.name == pageName) {
          return route.path;
        }
      }
      final nested = _parentSegmentOfRoute(children, pageName);
      if (nested != null) {
        return nested;
      }
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final PageInfo realHomePage;
  late final PageInfo realMyWorkPage;
  late final PageInfo realInboxPage;
  late final PageInfo realUpdatesPage;
  late final PageInfo realFriendsPage;
  late final PageInfo realProfilePage;
  late final PageInfo realBeaconViewPage;
  late final PageInfo realBeaconViewOperationalPage;
  late final PageInfo realAuthLoginPage;
  late final PageInfo realGraphPage;
  late final PageInfo realProfileViewPage;
  late final PageInfo realReviewContributionsPage;
  late final PageInfo realThreadDetailPage;
  late final PageInfo realInboxRejectedPage;
  late final PageInfo realBlockedUsersPage;

  setUpAll(() {
    realHomePage = HomeRoute.page;
    realMyWorkPage = MyWorkRoute.page;
    realInboxPage = InboxRoute.page;
    realUpdatesPage = UpdatesRoute.page;
    realFriendsPage = FriendsRoute.page;
    realProfilePage = ProfileRoute.page;
    realBeaconViewPage = BeaconViewRoute.page;
    realBeaconViewOperationalPage = BeaconViewOperationalRoute.page;
    realAuthLoginPage = AuthLoginRoute.page;
    realGraphPage = GraphRoute.page;
    realProfileViewPage = ProfileViewRoute.page;
    realReviewContributionsPage = ReviewContributionsRoute.page;
    realThreadDetailPage = ThreadDetailRoute.page;
    realInboxRejectedPage = InboxRejectedRoute.page;
    realBlockedUsersPage = BlockedUsersRoute.page;

    HomeRoute.page = PageInfo(
      HomeRoute.name,
      builder: (_) => const _TestHomeShell(),
    );
    MyWorkRoute.page = _labelPage(MyWorkRoute.name, 'my-work-root');
    InboxRoute.page = _labelPage(InboxRoute.name, 'inbox-root');
    UpdatesRoute.page = _labelPage(UpdatesRoute.name, 'updates-root');
    FriendsRoute.page = _labelPage(FriendsRoute.name, 'friends-root');
    ProfileRoute.page = _labelPage(ProfileRoute.name, 'profile-root');
    AuthLoginRoute.page = _labelPage(AuthLoginRoute.name, 'auth-login');
    BeaconViewOperationalRoute.page = PageInfo(
      BeaconViewOperationalRoute.name,
      builder: (data) {
        final id = data.inheritedPathParams.getString('id', '');
        final entry = data.queryParams.optString('entry') ?? '';
        final viewTab = data.queryParams.optString('tab') ?? '';
        return Text(
          'beacon-operational:$id:$entry:$viewTab',
          textDirection: TextDirection.ltr,
        );
      },
    );
    BeaconViewRoute.page = PageInfo(
      BeaconViewRoute.name,
      builder: (data) {
        final id = data.inheritedPathParams.getString('id', '');
        final entry = data.queryParams.optString('entry') ?? '';
        final viewTab = data.queryParams.optString('tab') ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'beacon-view:$id:$entry:$viewTab',
              textDirection: TextDirection.ltr,
            ),
            const Expanded(child: AutoRouter()),
          ],
        );
      },
    );
    GraphRoute.page = PageInfo(
      GraphRoute.name,
      builder: (data) {
        final focus = data.inheritedPathParams.getString('id', '');
        return Text('graph:$focus', textDirection: TextDirection.ltr);
      },
    );
    ProfileViewRoute.page = PageInfo(
      ProfileViewRoute.name,
      builder: (data) {
        final id = data.inheritedPathParams.getString('id', '');
        return Text('profile-view:$id', textDirection: TextDirection.ltr);
      },
    );
    ReviewContributionsRoute.page = _labelPage(
      ReviewContributionsRoute.name,
      'review-contributions',
    );
    ThreadDetailRoute.page = PageInfo(
      ThreadDetailRoute.name,
      builder: (data) {
        final id = data.inheritedPathParams.getString('id', '');
        final threadId = data.pathParams.getString('threadId', '');
        return Text(
          'thread-detail:$id:$threadId',
          textDirection: TextDirection.ltr,
        );
      },
    );
    InboxRejectedRoute.page = _labelPage(
      InboxRejectedRoute.name,
      'inbox-rejected',
    );
    BlockedUsersRoute.page = PageInfo(
      BlockedUsersRoute.name,
      builder: (_) => Scaffold(
        appBar: AppBar(
          leading: const AutoLeadingWithFallback(fallbackPath: kPathNetwork),
          title: const Text(
            'blocked-users',
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );
  });

  tearDownAll(() {
    HomeRoute.page = realHomePage;
    MyWorkRoute.page = realMyWorkPage;
    InboxRoute.page = realInboxPage;
    UpdatesRoute.page = realUpdatesPage;
    FriendsRoute.page = realFriendsPage;
    ProfileRoute.page = realProfilePage;
    BeaconViewRoute.page = realBeaconViewPage;
    BeaconViewOperationalRoute.page = realBeaconViewOperationalPage;
    AuthLoginRoute.page = realAuthLoginPage;
    GraphRoute.page = realGraphPage;
    ProfileViewRoute.page = realProfileViewPage;
    ReviewContributionsRoute.page = realReviewContributionsPage;
    ThreadDetailRoute.page = realThreadDetailPage;
    InboxRejectedRoute.page = realInboxRejectedPage;
    BlockedUsersRoute.page = realBlockedUsersPage;
  });

  late RootRouter router;
  late _FakeAuthCubit authCubit;
  var _routerPumped = false;

  tearDown(() async {
    if (!_routerPumped) {
      return;
    }
    router.dispose();
    await authCubit.shutDown();
    _routerPumped = false;
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
    _routerPumped = true;
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
      'reselecting My Work resets a cold deep-linked detail to the list',
      (tester) async {
        await pumpRouter(
          tester,
          initialPath: '/home/work/beacon/view/B154f2638566a',
          viaPlatform: true,
        );

        final tabsRouter = router.innerRouterOf<TabsRouter>(HomeRoute.name);
        final workSpec = HomeTabSpec.forTab(HomeTab.work);
        final workBranch = tabsRouter?.stackRouterOfIndex(workSpec.index);
        expect(tabsRouter?.activeIndex, workSpec.index);
        expect(workBranch?.stack.length, 1);
        expect(workBranch?.stack.first.name, BeaconViewRoute.name);

        await resetHomeTabBranchToRoot(tabsRouter!, HomeTab.work);
        await tester.pumpAndSettle();

        expect(find.text('my-work-root'), findsOneWidget);
        expect(currentUrl(), '/home/work');
        expect(workBranch?.stack.length, 1);
        expect(workBranch?.stack.first.name, MyWorkRoute.name);
      },
    );

    for (final testCase in [
      (
        tabLabel: 'Network',
        initialPath: '/home/network/graph/U2',
        tab: HomeTab.network,
        detailRouteName: GraphRoute.name,
        rootRouteName: FriendsRoute.name,
        rootLabel: 'friends-root',
        rootPath: '/home/network',
      ),
      (
        tabLabel: 'Profile',
        initialPath: '/home/profile/profile/view/U2',
        tab: HomeTab.me,
        detailRouteName: ProfileViewRoute.name,
        rootRouteName: ProfileRoute.name,
        rootLabel: 'profile-root',
        rootPath: '/home/profile',
      ),
    ]) {
      testWidgets(
        'reselecting ${testCase.tabLabel} resets a cold deep-linked detail '
        'to the tab root',
        (tester) async {
          await pumpRouter(
            tester,
            initialPath: testCase.initialPath,
            viaPlatform: true,
          );

          final tabsRouter = router.innerRouterOf<TabsRouter>(HomeRoute.name);
          final spec = HomeTabSpec.forTab(testCase.tab);
          final branch = tabsRouter?.stackRouterOfIndex(spec.index);
          expect(tabsRouter?.activeIndex, spec.index);
          expect(branch?.stack.length, 1);
          expect(branch?.stack.first.name, testCase.detailRouteName);

          await resetHomeTabBranchToRoot(tabsRouter!, testCase.tab);
          await tester.pumpAndSettle();

          expect(find.text(testCase.rootLabel), findsOneWidget);
          expect(currentUrl(), testCase.rootPath);
          expect(branch?.stack.length, 1);
          expect(branch?.stack.first.name, testCase.rootRouteName);
        },
      );
    }

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
      'dispatcher-shaped pushPath (includePrefixMatches: true) lands in the '
      'active tab branch',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home/profile');
        expect(find.text('profile-root'), findsOneWidget);

        // ui_effect_dispatcher.dart pushes with includePrefixMatches: true
        // and swallows failures (the guard rejects the root push after
        // forwarding into the branch) — mirror that exact call shape.
        await router.pushPath(
          '/graph/U2?x=1',
          includePrefixMatches: true,
          onFailure: (_) {},
        );
        await tester.pumpAndSettle();

        expect(find.text('graph:U2'), findsOneWidget);
        expect(currentUrl(), startsWith('/home/profile/graph/U2'));
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
      'legacy /beacon/room/:id is not registered and follows unknown-route behavior',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home');

        await router.navigatePath('/beacon/room/B123');
        await tester.pumpAndSettle();

        expect(find.textContaining('beacon-view:B123'), findsNothing);
        expect(currentUrl(), kPathMyWork);
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

    testWidgets(
      'popped beacon page stays isRouteDataActive until rebuildUrl '
      '(onPopPage gate)',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home');
        await router.pushPath('/beacon/view/B123');
        await tester.pumpAndSettle();

        final tabsRouter = router.innerRouterOf<TabsRouter>(HomeRoute.name);
        final workBranch = tabsRouter?.stackRouterOfIndex(
          HomeTabSpec.forTab(HomeTab.work).index,
        );
        final beaconPage = workBranch?.stack.last;
        expect(beaconPage?.name, BeaconViewRoute.name);

        // This is the exact predicate auto_route's StackRouter.onPopPage uses
        // before calling navigationHistory.rebuildUrl(). If false, HomeScreen's
        // ListenableBuilder never rebuilds and compact bottom nav stays hidden.
        expect(
          router.navigationHistory.isRouteDataActive(beaconPage!.routeData),
          isTrue,
          reason:
              'BeaconView must count as active in urlState.segments or '
              'in-app pop will not notify navigationHistory',
        );
      },
    );

    testWidgets(
      'compact chrome shows bottom nav again after app-bar back from '
      'pushed beacon view',
      (tester) async {
        final previousHome = HomeRoute.page;
        final previousOperational = BeaconViewOperationalRoute.page;
        HomeRoute.page = PageInfo(
          HomeRoute.name,
          builder: (_) => const _TestHomeShell(withCompactChrome: true),
        );
        BeaconViewOperationalRoute.page = PageInfo(
          BeaconViewOperationalRoute.name,
          builder: (data) {
            final id = data.inheritedPathParams.getString('id', '');
            // Mirrors BeaconViewScreen: PopScope + AutoLeadingWithFallback.
            return PopScope(
              canPop: true,
              child: Scaffold(
                appBar: AppBar(
                  leading: const AutoLeadingWithFallback(
                    fallbackPath: '/home',
                  ),
                  title: Text('beacon-op:$id'),
                ),
                body: Text('beacon-body:$id'),
              ),
            );
          },
        );
        addTearDown(() {
          HomeRoute.page = previousHome;
          BeaconViewOperationalRoute.page = previousOperational;
        });

        await pumpRouter(tester, initialPath: '/home');
        expect(find.byKey(const ValueKey('test-bottom-nav')), findsOneWidget);

        await router.pushPath('/beacon/view/B123');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('test-bottom-nav')), findsNothing);
        expect(find.text('beacon-op:B123'), findsOneWidget);

        await tester.tap(find.byType(BackButton));
        await tester.pump(); // schedule observer post-frame tick
        await tester.pump(); // apply chrome rebuild
        await tester.pumpAndSettle();

        expect(find.text('my-work-root'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('test-bottom-nav')),
          findsOneWidget,
          reason:
              'app-bar back must restore compact bottom nav (not only content)',
        );
      },
    );
  });

  group('Step 2 — remaining browse cluster', () {
    testWidgets(
      'restores nested graph view from a full branch URL (browser refresh)',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home/network/graph/U1');

        expect(find.text('graph:U1'), findsOneWidget);
        expect(currentUrl(), '/home/network/graph/U1');
      },
    );

    testWidgets(
      'pushPath of legacy /graph/:id (warm, work tab active) lands in the '
      'work branch, not its semantic-owner (network) branch',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home');
        expect(find.text('my-work-root'), findsOneWidget);

        await router.pushPath('/graph/U1');
        await tester.pumpAndSettle();

        expect(find.text('graph:U1'), findsOneWidget);
        expect(currentUrl(), '/home/work/graph/U1');
      },
    );

    testWidgets(
      'pushPath of legacy /graph/:id (cold — Home not mounted yet, hit as '
      'the initial route) falls back to its semantic-owner (network) branch',
      (tester) async {
        await pumpRouter(tester, initialPath: '/graph/U1');

        expect(find.text('graph:U1'), findsOneWidget);
        expect(currentUrl(), '/home/network/graph/U1');
      },
    );

    testWidgets(
      'ProfileViewRoute isMe guard redirects to ProfileRoute inside a branch',
      (tester) async {
        // _FakeAuthCubit's currentAccountId is 'U1' — viewing "U1" is self.
        await pumpRouter(tester, initialPath: '/home/network/profile/view/U1');

        expect(find.text('profile-root'), findsOneWidget);
        expect(currentUrl(), '/home/profile');
      },
    );

    testWidgets(
      'ProfileViewRoute renders normally for another user inside a branch',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home/network/profile/view/U2');

        expect(find.text('profile-view:U2'), findsOneWidget);
        expect(currentUrl(), '/home/network/profile/view/U2');
      },
    );

    testWidgets(
      'ThreadDetailRoute nests under BeaconViewRoute inside a branch',
      (tester) async {
        await pumpRouter(
          tester,
          initialPath: '/home/work/beacon/view/B1/thread/I1',
        );

        expect(find.text('thread-detail:B1:I1'), findsOneWidget);
        expect(currentUrl(), '/home/work/beacon/view/B1/thread/I1');
      },
    );

    testWidgets(
      'pushPath of thread detail lands in the active tab branch',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home');

        await router.pushPath('/beacon/view/B1/thread/I1');
        await tester.pumpAndSettle();

        expect(find.text('thread-detail:B1:I1'), findsOneWidget);
        expect(currentUrl(), '/home/work/beacon/view/B1/thread/I1');
      },
    );

    testWidgets(
      'restores InboxRejected from a full branch URL (browser refresh)',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home/inbox/inbox-rejected');

        expect(find.text('inbox-rejected'), findsOneWidget);
        expect(currentUrl(), '/home/inbox/inbox-rejected');
      },
    );

    testWidgets(
      'pushPath of legacy inbox-rejected path targets the active '
      '(non-default) tab branch',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home/network');
        expect(find.text('friends-root'), findsOneWidget);

        await router.pushPath('/home/inbox/rejected');
        await tester.pumpAndSettle();

        expect(find.text('inbox-rejected'), findsOneWidget);
        expect(currentUrl(), '/home/network/inbox-rejected');
      },
    );

    testWidgets(
      'two consecutive warm detail pushes stack on the branch (no URL '
      'replace) and back-pop one page at a time',
      (tester) async {
        // Regression: the guards previously used `navigate(HomeRoute(...))`
        // for warm forwards too; auto_route's navigate has replace semantics,
        // so the second detail swapped the URL in place and browser back
        // skipped a level (graph1 → profile → graph2, back×2 ≠ graph1).
        await pumpRouter(tester, initialPath: '/home/profile');
        expect(find.text('profile-root'), findsOneWidget);

        await router.pushPath('/graph/U5');
        await tester.pumpAndSettle();
        expect(find.text('graph:U5'), findsOneWidget);
        expect(currentUrl(), '/home/profile/graph/U5');

        await router.pushPath('/profile/view/U2');
        await tester.pumpAndSettle();
        expect(find.text('profile-view:U2'), findsOneWidget);
        expect(currentUrl(), '/home/profile/profile/view/U2');

        // The branch stack must hold all three pages — proof the second
        // detail was pushed, not navigated-over (which would have replaced
        // the graph entry).
        final branch = router
            .innerRouterOf<TabsRouter>(HomeRoute.name)
            ?.stackRouterOfIndex(HomeTabSpec.forTab(HomeTab.me).index);
        expect(branch, isNotNull, reason: 'me branch router exists');
        expect(
          branch!.stack.length,
          3,
          reason: 'branch stack is [profile-root, graph, profile-view]',
        );

        // Back one level: profile-view → graph.
        await router.maybePopTop();
        await tester.pumpAndSettle();
        expect(find.text('graph:U5'), findsOneWidget);
        expect(currentUrl(), '/home/profile/graph/U5');

        // Back again: graph → tab root.
        await router.maybePopTop();
        await tester.pumpAndSettle();
        expect(find.text('profile-root'), findsOneWidget);
        expect(currentUrl(), '/home/profile');
      },
    );

    testWidgets(
      'back at a branch root defers to the platform (backgrounds the app)',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home/work');
        expect(find.text('my-work-root'), findsOneWidget);

        // Decided back semantics: with the active branch at its root there
        // is nothing to pop in-app — maybePopTop must return false so the
        // system back (Android predictive back / browser history) takes
        // over and backgrounds/exits the app instead of e.g. snapping to
        // the initial tab.
        expect(await router.maybePopTop(), isFalse);
        await tester.pumpAndSettle();
        expect(find.text('my-work-root'), findsOneWidget);
        expect(currentUrl(), '/home/work');
      },
    );

    testWidgets(
      'deepLinkTransformer nests bare browse paths under the active branch '
      '(single history entry for platform navigations)',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home/network');

        // Warm: active tab (network) wins over the semantic owner.
        expect(
          (await router.deepLinkTransformer(
            Uri.parse('/profile/view/U2?x=1'),
          )).toString(),
          '/home/network/profile/view/U2?x=1',
        );
        expect(
          (await router.deepLinkTransformer(
            Uri.parse('/beacon/view/B9?tab=threads&thread=general'),
          )).toString(),
          '/home/network/beacon/view/B9?tab=threads&thread=general',
        );
        // Non-browse paths pass through untouched.
        for (final path in ['/settings', '/sign/in', '/beacon/new', '/home']) {
          expect(
            (await router.deepLinkTransformer(Uri.parse(path))).toString(),
            path,
          );
        }
      },
    );

    testWidgets(
      'notification dest=room link opens threads tab through the branch pipeline',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home');

        unawaited(
          router.openFromNotificationLink(
            'https://app.example/#/shared/view?id=B7&dest=room',
          ),
        );
        await tester.pumpAndSettle();

        expect(currentUrl(), contains('/home/work/beacon/view/B7'));
        expect(currentUrl(), contains('tab=threads'));
        expect(currentUrl(), contains('thread=general'));
        expect(currentUrl(), contains('entry=room_notification'));
      },
    );

    testWidgets(
      'Updates-origin browse destinations stay in the Updates branch',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home');

        unawaited(
          router.openFromNotificationLink(
            '/beacon/view/B2?tab=threads&thread=I1&message=M1',
            preferUpdatesBranch: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          currentUrl(),
          '/home/updates/beacon/view/B2?tab=threads&thread=I1&message=M1',
        );
      },
    );

    testWidgets(
      'cold platform load of a bare browse path lands nested in its '
      'semantic-owner branch',
      (tester) async {
        await pumpRouter(
          tester,
          initialPath: '/profile/view/U2',
          viaPlatform: true,
        );

        expect(find.text('profile-view:U2'), findsOneWidget);
        expect(currentUrl(), '/home/network/profile/view/U2');
      },
    );
  });

  group('WU6 — Blocked people route ownership', () {
    test('registers BlockedUsersRoute once under Network', () async {
      final localAuth = _FakeAuthCubit();
      final localRouter = RootRouter(
        Logger('test'),
        localAuth,
        _FakeSettingsCubit(),
        PostJoinNavigationCubit(),
      );
      addTearDown(() async {
        localRouter.dispose();
        await localAuth.shutDown();
      });

      expect(
        _countRoutePages(localRouter.routes, BlockedUsersRoute.name),
        1,
      );
      expect(
        _parentSegmentOfRoute(localRouter.routes, BlockedUsersRoute.name),
        kPathNetwork.split('/').last,
      );
    });

    testWidgets('openBlockedUsers from People lands on canonical URL', (
      tester,
    ) async {
      await pumpRouter(tester, initialPath: '/home/network');
      expect(find.text('friends-root'), findsOneWidget);

      await router.openBlockedUsers();
      await tester.pumpAndSettle();

      expect(find.text('blocked-users'), findsOneWidget);
      expect(currentUrl(), kPathBlockedUsers);
    });

    testWidgets(
      'openBlockedUsers from another tab activates Network with '
      '[FriendsRoute, BlockedUsersRoute]',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home/work');
        expect(find.text('my-work-root'), findsOneWidget);

        await router.openBlockedUsers();
        await tester.pumpAndSettle();

        final tabsRouter = router.innerRouterOf<TabsRouter>(HomeRoute.name);
        final networkSpec = HomeTabSpec.forTab(HomeTab.network);
        final branch = tabsRouter?.stackRouterOfIndex(networkSpec.index);
        expect(tabsRouter?.activeIndex, networkSpec.index);
        expect(branch?.stack.map((r) => r.name).toList(), [
          FriendsRoute.name,
          BlockedUsersRoute.name,
        ]);
        expect(find.text('blocked-users'), findsOneWidget);
        expect(currentUrl(), kPathBlockedUsers);
      },
    );

    testWidgets(
      'restores blocked users from a full branch URL (browser refresh)',
      (tester) async {
        await pumpRouter(tester, initialPath: kPathBlockedUsers);

        expect(find.text('blocked-users'), findsOneWidget);
        expect(currentUrl(), kPathBlockedUsers);
      },
    );

    testWidgets(
      'restores blocked users from a platform initial route (browser URL bar)',
      (tester) async {
        await pumpRouter(
          tester,
          initialPath: kPathBlockedUsers,
          viaPlatform: true,
        );

        expect(find.text('blocked-users'), findsOneWidget);
        expect(currentUrl(), kPathBlockedUsers);
      },
    );

    testWidgets('back after openBlockedUsers returns to People root', (
      tester,
    ) async {
      await pumpRouter(tester, initialPath: '/home/network');
      await router.openBlockedUsers();
      await tester.pumpAndSettle();
      expect(find.text('blocked-users'), findsOneWidget);

      await router.maybePopTop();
      await tester.pumpAndSettle();

      expect(find.text('friends-root'), findsOneWidget);
      expect(currentUrl(), kPathNetwork);
    });

    testWidgets(
      'fallback back after cold refresh on blocked URL navigates to People',
      (tester) async {
        await pumpRouter(
          tester,
          initialPath: kPathBlockedUsers,
          viaPlatform: true,
        );
        expect(find.text('blocked-users'), findsOneWidget);

        final branch = router
            .innerRouterOf<TabsRouter>(HomeRoute.name)
            ?.stackRouterOfIndex(HomeTabSpec.forTab(HomeTab.network).index);
        expect(branch, isNotNull);
        expect(branch!.canPop(), isFalse);

        final blockedAppBar = find.ancestor(
          of: find.text('blocked-users'),
          matching: find.byType(AppBar),
        );
        await tester.tap(
          find.descendant(
            of: blockedAppBar,
            matching: find.byType(IconButton),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('friends-root'), findsOneWidget);
        expect(currentUrl(), kPathNetwork);
      },
    );

    testWidgets(
      '/settings/blocked is not registered and follows unknown-route behavior',
      (tester) async {
        await pumpRouter(tester, initialPath: '/settings/blocked');

        expect(find.text('blocked-users'), findsNothing);
        expect(currentUrl(), kPathMyWork);
      },
    );
  });
}
