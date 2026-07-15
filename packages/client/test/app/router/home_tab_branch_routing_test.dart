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
import 'package:tentura/features/home/ui/screen/home_screen.dart';
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
  late final PageInfo realGraphPage;
  late final PageInfo realProfileViewPage;
  late final PageInfo realItemDiscussionPage;
  late final PageInfo realInboxRejectedPage;
  late final PageInfo realNotificationCenterPage;

  setUpAll(() {
    realHomePage = HomeRoute.page;
    realMyWorkPage = MyWorkRoute.page;
    realInboxPage = InboxRoute.page;
    realFriendsPage = FriendsRoute.page;
    realProfilePage = ProfileRoute.page;
    realBeaconViewPage = BeaconViewRoute.page;
    realAuthLoginPage = AuthLoginRoute.page;
    realGraphPage = GraphRoute.page;
    realProfileViewPage = ProfileViewRoute.page;
    realItemDiscussionPage = ItemDiscussionRoute.page;
    realInboxRejectedPage = InboxRejectedRoute.page;
    realNotificationCenterPage = NotificationCenterRoute.page;

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
    ItemDiscussionRoute.page = PageInfo(
      ItemDiscussionRoute.name,
      builder: (data) {
        final beaconId = data.inheritedPathParams.getString('beaconId', '');
        final itemId = data.inheritedPathParams.getString('itemId', '');
        return Text(
          'item-discussion:$beaconId:$itemId',
          textDirection: TextDirection.ltr,
        );
      },
    );
    InboxRejectedRoute.page = _labelPage(
      InboxRejectedRoute.name,
      'inbox-rejected',
    );
    NotificationCenterRoute.page = _labelPage(
      NotificationCenterRoute.name,
      'notification-center',
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
    GraphRoute.page = realGraphPage;
    ProfileViewRoute.page = realProfileViewPage;
    ItemDiscussionRoute.page = realItemDiscussionPage;
    InboxRejectedRoute.page = realInboxRejectedPage;
    NotificationCenterRoute.page = realNotificationCenterPage;
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
      'reselecting My Work resets a cold deep-linked detail to the list',
      (tester) async {
        await pumpRouter(
          tester,
          initialPath: '/home/work/beacon/view/B154f2638566a',
          viaPlatform: true,
        );

        final tabsRouter = router.innerRouterOf<TabsRouter>(HomeRoute.name);
        final workBranch = tabsRouter?.stackRouterOfIndex(0);
        expect(tabsRouter?.activeIndex, 0);
        expect(workBranch?.stack.length, 1);
        expect(workBranch?.stack.first.name, BeaconViewRoute.name);

        await resetHomeTabBranchToRoot(tabsRouter!, 0);
        await tester.pumpAndSettle();

        expect(find.text('my-work-root'), findsOneWidget);
        expect(currentUrl(), '/home/work');
        expect(workBranch?.stack.length, 1);
        expect(workBranch?.stack.first.name, MyWorkRoute.name);
      },
    );

    for (final testCase in [
      (
        tabLabel: 'Inbox',
        initialPath: '/home/inbox/notifications',
        tabIndex: 1,
        detailRouteName: NotificationCenterRoute.name,
        rootRouteName: InboxRoute.name,
        rootLabel: 'inbox-root',
        rootPath: '/home/inbox',
      ),
      (
        tabLabel: 'Network',
        initialPath: '/home/network/graph/U2',
        tabIndex: 2,
        detailRouteName: GraphRoute.name,
        rootRouteName: FriendsRoute.name,
        rootLabel: 'friends-root',
        rootPath: '/home/network',
      ),
      (
        tabLabel: 'Profile',
        initialPath: '/home/profile/profile/view/U2',
        tabIndex: 3,
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
          final branch = tabsRouter?.stackRouterOfIndex(testCase.tabIndex);
          expect(tabsRouter?.activeIndex, testCase.tabIndex);
          expect(branch?.stack.length, 1);
          expect(branch?.stack.first.name, testCase.detailRouteName);

          await resetHomeTabBranchToRoot(tabsRouter!, testCase.tabIndex);
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
      'ItemDiscussionRoute matches before BeaconViewRoute inside a branch',
      (tester) async {
        await pumpRouter(
          tester,
          initialPath: '/home/work/beacon/view/B1/discussion/I1',
        );

        expect(find.text('item-discussion:B1:I1'), findsOneWidget);
        expect(currentUrl(), '/home/work/beacon/view/B1/discussion/I1');
      },
    );

    testWidgets(
      'pushPath of legacy item-discussion path lands in the active tab branch',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home');

        await router.pushPath('/beacon/view/B1/discussion/I1');
        await tester.pumpAndSettle();

        expect(find.text('item-discussion:B1:I1'), findsOneWidget);
        expect(currentUrl(), '/home/work/beacon/view/B1/discussion/I1');
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
      'restores NotificationCenter from a full branch URL (browser refresh)',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home/inbox/notifications');

        expect(find.text('notification-center'), findsOneWidget);
        expect(currentUrl(), '/home/inbox/notifications');
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
            ?.stackRouterOfIndex(3);
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
            Uri.parse('/beacon/view/B9?tab=room'),
          )).toString(),
          '/home/network/beacon/view/B9?tab=room',
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
      'notification dest=room link keeps the room entry through the '
      'branch-prefixed pipeline',
      (tester) async {
        await pumpRouter(tester, initialPath: '/home');

        // Not awaited: the underlying push future completes only when the
        // pushed page pops.
        unawaited(
          router.openFromNotificationLink(
            'https://app.example/#/shared/view?id=B7&dest=room',
          ),
        );
        await tester.pumpAndSettle();

        expect(currentUrl(), contains('/home/work/beacon/view/B7'));
        expect(currentUrl(), contains('entry=room_notification'));
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
}
