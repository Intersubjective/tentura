import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

final class _FakeAuthCubit extends Fake implements AuthCubit {
  _FakeAuthCubit()
    : _state = AuthState(
        updatedAt: DateTime(2026),
        currentAccountId: 'U1',
      );

  final AuthState _state;

  @override
  AuthState get state => _state;

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

final class _FakeSettingsCubit extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

class _TestHomeShell extends StatelessWidget {
  const _TestHomeShell();

  @override
  Widget build(BuildContext context) => AutoTabsRouter(
    routes: [for (final spec in HomeTabSpec.all) spec.shell()],
    duration: Duration.zero,
    transitionBuilder: (_, child, _) => child,
    builder: (_, child) => child,
  );
}

PageInfo _labelPage(String name, String label) => PageInfo(
  name,
  builder: (_) => Text(label, textDirection: TextDirection.ltr),
);

int _countRoutePages(List<AutoRoute> routes, String name) {
  var count = 0;
  for (final route in routes) {
    if (route.page.name == name) count++;
    if (route.children case final children?) {
      count += _countRoutePages(children, name);
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RootRouter router;
  late PageInfo homePage;
  late PageInfo workPage;
  late PageInfo inboxPage;
  late PageInfo updatesPage;
  late PageInfo friendsPage;
  late PageInfo mePage;
  late PageInfo profilePage;
  late PageInfo graphPage;
  late PageInfo forwardsGraphPage;
  late PageInfo genealogyPage;
  late PageInfo ratingPage;
  late PageInfo rejectedPage;
  late PageInfo authPage;

  setUpAll(() {
    homePage = HomeRoute.page;
    workPage = MyWorkRoute.page;
    inboxPage = InboxRoute.page;
    updatesPage = UpdatesRoute.page;
    friendsPage = FriendsRoute.page;
    mePage = ProfileRoute.page;
    profilePage = ProfileViewRoute.page;
    graphPage = GraphRoute.page;
    forwardsGraphPage = ForwardsGraphRoute.page;
    genealogyPage = InviteGenealogyRoute.page;
    ratingPage = RatingRoute.page;
    rejectedPage = InboxRejectedRoute.page;
    authPage = AuthLoginRoute.page;

    HomeRoute.page = PageInfo(
      HomeRoute.name,
      builder: (_) => const _TestHomeShell(),
    );
    MyWorkRoute.page = _labelPage(MyWorkRoute.name, 'work-root');
    InboxRoute.page = _labelPage(InboxRoute.name, 'inbox-root');
    UpdatesRoute.page = _labelPage(UpdatesRoute.name, 'updates-root');
    FriendsRoute.page = _labelPage(FriendsRoute.name, 'network-root');
    ProfileRoute.page = _labelPage(ProfileRoute.name, 'me-root');
    ProfileViewRoute.page = PageInfo(
      ProfileViewRoute.name,
      builder: (data) => Text(
        'profile:${data.inheritedPathParams.getString('id', '')}',
        textDirection: TextDirection.ltr,
      ),
    );
    GraphRoute.page = PageInfo(
      GraphRoute.name,
      builder: (data) => Text(
        'graph:${data.inheritedPathParams.getString('id', '')}',
        textDirection: TextDirection.ltr,
      ),
    );
    ForwardsGraphRoute.page = _labelPage(
      ForwardsGraphRoute.name,
      'forwards-graph',
    );
    InviteGenealogyRoute.page = _labelPage(
      InviteGenealogyRoute.name,
      'genealogy',
    );
    RatingRoute.page = _labelPage(RatingRoute.name, 'rating');
    InboxRejectedRoute.page = _labelPage(
      InboxRejectedRoute.name,
      'inbox-rejected',
    );
    AuthLoginRoute.page = _labelPage(AuthLoginRoute.name, 'auth-login');
  });

  tearDownAll(() {
    HomeRoute.page = homePage;
    MyWorkRoute.page = workPage;
    InboxRoute.page = inboxPage;
    UpdatesRoute.page = updatesPage;
    FriendsRoute.page = friendsPage;
    ProfileRoute.page = mePage;
    ProfileViewRoute.page = profilePage;
    GraphRoute.page = graphPage;
    ForwardsGraphRoute.page = forwardsGraphPage;
    InviteGenealogyRoute.page = genealogyPage;
    RatingRoute.page = ratingPage;
    InboxRejectedRoute.page = rejectedPage;
    AuthLoginRoute.page = authPage;
  });

  setUp(() {
    router = RootRouter(
      Logger('RootBrowseRoutingTest'),
      _FakeAuthCubit(),
      _FakeSettingsCubit(),
      PostJoinNavigationCubit(),
    );
  });

  tearDown(() => router.dispose());

  Future<void> pumpRouter(
    WidgetTester tester, {
    required String initialPath,
  }) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = initialPath;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router.config(
          deepLinkBuilder: router.deepLinkBuilder,
          deepLinkTransformer: router.deepLinkTransformer,
          reevaluateListenable: router.reevaluateListenable,
          includePrefixMatches: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('browse details have one canonical root registration', () {
    for (final name in [
      ProfileViewRoute.name,
      GraphRoute.name,
      ForwardsGraphRoute.name,
      InviteGenealogyRoute.name,
      RatingRoute.name,
      InboxRejectedRoute.name,
    ]) {
      expect(_countRoutePages(router.routes, name), 1, reason: name);
    }
  });

  testWidgets('warm Home to Profile preserves active tab and state', (
    tester,
  ) async {
    await pumpRouter(tester, initialPath: '/home/inbox');
    final tabs = router.innerRouterOf<TabsRouter>(HomeRoute.name)!;
    expect(tabs.activeIndex, HomeTabSpec.forTab(HomeTab.inbox).index);

    unawaited(router.push(ProfileViewRoute(id: 'U2')));
    await tester.pumpAndSettle();

    expect(router.stackData.map((data) => data.name), [
      HomeRoute.name,
      ProfileViewRoute.name,
    ]);
    expect(find.text('profile:U2'), findsOneWidget);
    expect(router.navigationHistory.urlState.url, '/profile/view/U2');

    await router.maybePop();
    await tester.pumpAndSettle();
    expect(tabs.activeIndex, HomeTabSpec.forTab(HomeTab.inbox).index);
    expect(find.text('inbox-root'), findsOneWidget);
  });

  testWidgets('cold canonical Profile uses Network as semantic source', (
    tester,
  ) async {
    await pumpRouter(tester, initialPath: '/profile/view/U2');

    expect(router.stackData.map((data) => data.name), [
      HomeRoute.name,
      ProfileViewRoute.name,
    ]);
    final tabs = router.innerRouterOf<TabsRouter>(HomeRoute.name)!;
    expect(tabs.activeIndex, HomeTabSpec.forTab(HomeTab.network).index);
    expect(router.navigationHistory.urlState.url, '/profile/view/U2');
  });

  testWidgets('legacy detail retains explicit tab and canonicalizes URL', (
    tester,
  ) async {
    await pumpRouter(
      tester,
      initialPath: '/home/inbox/profile/view/U2',
    );

    final tabs = router.innerRouterOf<TabsRouter>(HomeRoute.name)!;
    expect(tabs.activeIndex, HomeTabSpec.forTab(HomeTab.inbox).index);
    expect(router.stackData.last.name, ProfileViewRoute.name);
    expect(router.navigationHistory.urlState.url, '/profile/view/U2');
  });

  testWidgets('Profile to Graph to Profile pops in reverse order', (
    tester,
  ) async {
    await pumpRouter(tester, initialPath: '/profile/view/U2');
    unawaited(router.push(GraphRoute(focus: 'U2')));
    await tester.pumpAndSettle();
    unawaited(router.push(ProfileViewRoute(id: 'U3')));
    await tester.pumpAndSettle();

    expect(router.stackData.map((data) => data.name), [
      HomeRoute.name,
      ProfileViewRoute.name,
      GraphRoute.name,
      ProfileViewRoute.name,
    ]);
    expect(find.text('profile:U3'), findsOneWidget);

    await router.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('graph:U2'), findsOneWidget);
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('profile:U2'), findsOneWidget);
  });

  testWidgets('self profile keeps Home Me special handling', (tester) async {
    await pumpRouter(tester, initialPath: '/home/work');
    unawaited(router.push(ProfileViewRoute(id: 'U1')));
    await tester.pumpAndSettle();

    expect(router.stackData.map((data) => data.name), [HomeRoute.name]);
    final tabs = router.innerRouterOf<TabsRouter>(HomeRoute.name)!;
    expect(tabs.activeIndex, HomeTabSpec.forTab(HomeTab.me).index);
    expect(find.text('me-root'), findsOneWidget);
  });

  testWidgets('warm notification pushes above the current source', (
    tester,
  ) async {
    await pumpRouter(tester, initialPath: '/home/inbox');
    unawaited(router.openFromNotificationLink('/profile/view/U2'));
    await tester.pumpAndSettle();

    expect(router.stackData.map((data) => data.name), [
      HomeRoute.name,
      ProfileViewRoute.name,
    ]);
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('inbox-root'), findsOneWidget);
  });
}
