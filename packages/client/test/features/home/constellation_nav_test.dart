import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import '../../support/attention_repository_fake_base.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/home/ui/widget/constellation_navbar_item.dart';
import 'package:tentura/features/home/ui/widget/friends_navbar_item.dart';
import 'package:tentura/features/home/ui/widget/home_bottom_navigation_bar.dart';
import 'package:tentura/features/home/ui/widget/inbox_navbar_item.dart';
import 'package:tentura/features/home/ui/widget/my_work_navbar_item.dart';
import 'package:tentura/features/home/ui/widget/profile_navbar_item.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_empty_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';

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

final class _FakeProfileCubit extends Fake implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'U1', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _Repository extends AttentionRepositoryFake {
  Set<String> unread = const {};
  AttentionSurfaceSummary surfaceSummaryValue = const AttentionSurfaceSummary(
    activityUnreadTotal: 1,
    myWorkUnreadTotal: 1,
    needsYouTotal: 0,
  );

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() async =>
      surfaceSummaryValue;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => const AttentionFeed(
    summary: AttentionSummary(),
    page: AttentionFeedPage(),
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      unread.intersection(beaconIds);

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
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

Future<void> _settle([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

Future<HomeAttentionCubit> _seedAttentionCubit({
  required _Accounts accounts,
  required _Repository repository,
}) async {
  final sync = buildTestRealtimeSync();
  final attentionCase = AttentionCase(
    repository,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('constellation-nav-test'),
  );
  final cubit = HomeAttentionCubit(
    attentionCase,
    accounts,
    Logger('constellation-nav-test'),
  );
  repository.unread = {'inbox-b1', 'work-b1'};
  accounts.emit('U1');
  await _settle();
  cubit.reportInboxSnapshot(
    accountId: 'U1',
    beaconIds: {'inbox-b1'},
    loaded: true,
  );
  cubit.reportMyWorkSnapshot(
    accountId: 'U1',
    beaconIds: {'work-b1'},
    loaded: true,
  );
  await _settle();
  expect(cubit.state.projectionReady, isTrue);
  expect(cubit.state.myWorkMarkerIds, isNotEmpty);
  expect(cubit.state.inboxMarkerIds, isNotEmpty);
  return cubit;
}

/// Mirrors [HomeScreen]'s five-destination chrome without AutoRoute shell deps.
class _HomeChromeFixture extends StatelessWidget {
  const _HomeChromeFixture({
    required this.useSideNav,
    this.selectedIndex = 2,
  });

  final bool useSideNav;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    if (useSideNav) {
      return NavigationRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: (_) {},
        destinations: [
          NavigationRailDestination(
            icon: const MyWorkNavbarItem(),
            selectedIcon: const MyWorkNavbarItem(selected: true),
            label: Text(l10n.myWork),
          ),
          NavigationRailDestination(
            icon: const InboxNavbarItem(),
            selectedIcon: const InboxNavbarItem(selected: true),
            label: Text(l10n.inbox),
          ),
          NavigationRailDestination(
            icon: const ConstellationNavbarItem(),
            selectedIcon: const ConstellationNavbarItem(selected: true),
            label: Text(l10n.constellationNavLabel),
          ),
          NavigationRailDestination(
            icon: const FriendsNavbarItem(),
            selectedIcon: const FriendsNavbarItem(selected: true),
            label: Text(l10n.network),
          ),
          NavigationRailDestination(
            icon: const ProfileNavBarItem(),
            selectedIcon: const ProfileNavBarItem(selected: true),
            label: Text(l10n.profile),
          ),
        ],
      );
    }
    return HomeBottomNavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (_) {},
      destinations: [
        HomeNavDestination(
          icon: const MyWorkNavbarItem(),
          selectedIcon: const MyWorkNavbarItem(selected: true),
          label: l10n.myWork,
        ),
        HomeNavDestination(
          icon: const InboxNavbarItem(),
          selectedIcon: const InboxNavbarItem(selected: true),
          label: l10n.inbox,
        ),
        HomeNavDestination(
          icon: const ConstellationNavbarItem(),
          selectedIcon: const ConstellationNavbarItem(selected: true),
          label: '',
          tooltip: l10n.constellationNavLabel,
          commandChrome: true,
        ),
        HomeNavDestination(
          icon: const FriendsNavbarItem(),
          selectedIcon: const FriendsNavbarItem(selected: true),
          label: l10n.network,
        ),
        HomeNavDestination(
          icon: const ProfileNavBarItem(),
          selectedIcon: const ProfileNavBarItem(selected: true),
          label: l10n.profile,
        ),
      ],
    );
  }
}

Future<void> _pumpHomeChrome(
  WidgetTester tester, {
  required Size logicalSize,
  required HomeAttentionCubit attention,
  required bool useSideNav,
  int selectedIndex = 0,
}) async {
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final profile = _FakeProfileCubit();
  final auth = _FakeAuthCubit();
  if (GetIt.I.isRegistered<ProfileCubit>()) {
    await GetIt.I.unregister<ProfileCubit>();
  }
  if (GetIt.I.isRegistered<AuthCubit>()) {
    await GetIt.I.unregister<AuthCubit>();
  }
  if (GetIt.I.isRegistered<HomeAttentionCubit>()) {
    await GetIt.I.unregister<HomeAttentionCubit>();
  }
  GetIt.I
    ..registerSingleton<ProfileCubit>(profile)
    ..registerSingleton<AuthCubit>(auth)
    ..registerSingleton<HomeAttentionCubit>(attention);
  addTearDown(GetIt.I.reset);

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<HomeAttentionCubit>.value(value: attention),
        BlocProvider<AuthCubit>.value(value: auth),
        BlocProvider<ProfileCubit>.value(value: profile),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(size: logicalSize),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: SizedBox(
                height: logicalSize.height,
                child: _HomeChromeFixture(
                  useSideNav: useSideNav,
                  selectedIndex: selectedIndex,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _navItemShowsBadge(WidgetTester tester, Finder navItemFinder) {
  return find
      .descendant(
        of: navItemFinder,
        matching: find.byType(Badge),
      )
      .evaluate()
      .isNotEmpty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeTabSpec', () {
    test('restores five destinations with Constellation at index 2', () {
      expect(HomeTabSpec.all, hasLength(5));
      expect(
        [for (final spec in HomeTabSpec.all) (spec.tab, spec.index, spec.path)],
        const [
          (HomeTab.work, 0, '/home/work'),
          (HomeTab.inbox, 1, '/home/inbox'),
          (HomeTab.constellation, 2, '/home/constellation'),
          (HomeTab.network, 3, '/home/network'),
          (HomeTab.me, 4, '/home/profile'),
        ],
      );
    });

    test('My Work remains the default landing tab', () {
      expect(HomeTabSpec.all.first.tab, HomeTab.work);
      expect(HomeTabSpec.all.first.index, 0);
    });
  });

  group('ConstellationNavbarItem', () {
    testWidgets('never renders a badge widget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConstellationNavbarItem(),
          ),
        ),
      );

      expect(find.byType(Badge), findsNothing);
      expect(
        find.byKey(TestIds.key(TestIds.constellationNavItem)),
        findsOneWidget,
      );
    });
  });

  group('Home chrome', () {
    late _Accounts accounts;
    late _Repository repository;
    late HomeAttentionCubit attention;

    setUp(() async {
      accounts = _Accounts();
      repository = _Repository();
      attention = await _seedAttentionCubit(
        accounts: accounts,
        repository: repository,
      );
    });

    tearDown(() async {
      await attention.close();
      await accounts.close();
    });

    testWidgets('expanded rail shows five destinations', (tester) async {
      await _pumpHomeChrome(
        tester,
        logicalSize: const Size(900, 800),
        attention: attention,
        useSideNav: true,
      );

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.destinations, hasLength(5));
    });

    testWidgets('compact bottom bar shows five destinations', (tester) async {
      await _pumpHomeChrome(
        tester,
        logicalSize: const Size(390, 800),
        attention: attention,
        useSideNav: false,
      );

      expect(find.byType(HomeBottomNavigationBar), findsOneWidget);
      final bar = tester.widget<HomeBottomNavigationBar>(
        find.byType(HomeBottomNavigationBar),
      );
      expect(bar.destinations, hasLength(5));
    });

    testWidgets('compact bottom bar hides Field tab label', (tester) async {
      await _pumpHomeChrome(
        tester,
        logicalSize: const Size(390, 800),
        attention: attention,
        useSideNav: false,
      );

      expect(find.text('My field'), findsNothing);
      expect(find.byIcon(TenturaIcons.graph), findsOneWidget);
    });

    testWidgets('compact Field tab uses command disk chrome', (tester) async {
      await _pumpHomeChrome(
        tester,
        logicalSize: const Size(390, 800),
        attention: attention,
        useSideNav: false,
      );

      final bar = tester.widget<HomeBottomNavigationBar>(
        find.byType(HomeBottomNavigationBar),
      );
      expect(bar.destinations[2].commandChrome, isTrue);

      final disk = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.byIcon(TenturaIcons.graph),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = disk.decoration as BoxDecoration;
      final inactive = Theme.of(
        tester.element(find.byType(HomeBottomNavigationBar)),
      ).colorScheme.onSurfaceVariant;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, TenturaPalette.surface);
      expect(decoration.border?.top.color, inactive);
      expect(
        tester
            .widget<IconTheme>(
              find
                  .ancestor(
                    of: find.byIcon(TenturaIcons.graph),
                    matching: find.byType(IconTheme),
                  )
                  .first,
            )
            .data
            .color,
        inactive,
      );

      final expectedSize =
          (TenturaTokens.light.bottomNavHeight +
              TenturaTokens.light.buttonHeight) /
          2;
      final diskSize = tester.getSize(
        find
            .ancestor(
              of: find.byIcon(TenturaIcons.graph),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(diskSize.width, closeTo(expectedSize, 0.5));
      expect(diskSize.height, closeTo(expectedSize, 0.5));

      final diskCenter = tester.getCenter(find.byIcon(TenturaIcons.graph));
      final barCenter = tester.getCenter(find.byType(HomeBottomNavigationBar));
      expect(diskCenter.dy, closeTo(barCenter.dy, 1));
    });

    testWidgets('expanded rail shows Field tab label', (tester) async {
      await _pumpHomeChrome(
        tester,
        logicalSize: const Size(900, 800),
        attention: attention,
        useSideNav: true,
      );

      expect(find.text('My field'), findsOneWidget);
      expect(find.byIcon(TenturaIcons.graph), findsOneWidget);
    });

    testWidgets(
      'constellation nav item has no badge while sibling tabs can',
      (
        tester,
      ) async {
        for (final useSideNav in [true, false]) {
          await _pumpHomeChrome(
            tester,
            logicalSize: useSideNav
                ? const Size(900, 800)
                : const Size(390, 800),
            attention: attention,
            useSideNav: useSideNav,
            selectedIndex: HomeTabSpec.forTab(HomeTab.constellation).index,
          );
          attention.setActiveHomeTab(HomeTab.constellation);

          final constellationIcon = find.byKey(
            TestIds.key(TestIds.constellationNavItem),
          );
          expect(constellationIcon, findsOneWidget);
          expect(_navItemShowsBadge(tester, constellationIcon), isFalse);

        }
      },
    );
  });

  group('My Work empty state', () {
    testWidgets('exposes find-ways-to-help and routes to constellation', (
      tester,
    ) async {
      late RootRouter router;
      late PageInfo homePage;
      late PageInfo workPage;
      late PageInfo inboxPage;
      late PageInfo constellationPage;
      late PageInfo friendsPage;
      late PageInfo mePage;

      homePage = HomeRoute.page;
      workPage = MyWorkRoute.page;
      inboxPage = InboxRoute.page;
      constellationPage = ConstellationRoute.page;
      friendsPage = FriendsRoute.page;
      mePage = ProfileRoute.page;

      HomeRoute.page = PageInfo(
        HomeRoute.name,
        builder: (_) => const _TestHomeShell(),
      );
      MyWorkRoute.page = PageInfo(
        MyWorkRoute.name,
        builder: (data) => Builder(
          builder: (context) => MyWorkEmptyBody(
            filter: MyWorkFilter.active,
            draftCount: 0,
            archivedCountHint: 0,
            onCreateBeacon: () {},
            onOpenInbox: () {},
            onOpenConstellation: () =>
                AutoTabsRouter.of(context).setActiveIndex(
                  HomeTabSpec.forTab(HomeTab.constellation).index,
                ),
            onShowDrafts: () {},
            onShowArchived: () {},
          ),
        ),
      );
      InboxRoute.page = _labelPage(InboxRoute.name, 'inbox-root');
      ConstellationRoute.page = _labelPage(
        ConstellationRoute.name,
        'constellation-root',
      );
      FriendsRoute.page = _labelPage(FriendsRoute.name, 'network-root');
      ProfileRoute.page = _labelPage(ProfileRoute.name, 'me-root');

      router = RootRouter(
        Logger('ConstellationNavTest'),
        _FakeAuthCubit(),
        _FakeSettingsCubit(),
        PostJoinNavigationCubit(),
      );
      addTearDown(router.dispose);

      GetIt.I.registerSingleton<ProfileCubit>(_FakeProfileCubit());
      addTearDown(() {
        if (GetIt.I.isRegistered<ProfileCubit>()) {
          GetIt.I.unregister<ProfileCubit>();
        }
      });

      tester.binding.platformDispatcher.defaultRouteNameTestValue = kPathMyWork;
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );

      await tester.pumpWidget(
        MaterialApp.router(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router.config(
            deepLinkBuilder: router.deepLinkBuilder,
            deepLinkTransformer: router.deepLinkTransformer,
            reevaluateListenable: router.reevaluateListenable,
            includePrefixMatches: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tabs = router.innerRouterOf<TabsRouter>(HomeRoute.name)!;
      expect(tabs.activeIndex, HomeTabSpec.forTab(HomeTab.work).index);

      await tester.tap(find.byKey(TestIds.key(TestIds.myWorkFindWaysToHelp)));
      await tester.pumpAndSettle();

      expect(tabs.activeIndex, HomeTabSpec.forTab(HomeTab.constellation).index);
      expect(
        router.navigationHistory.urlState.url,
        kPathConstellation,
      );
      expect(find.text('constellation-root'), findsOneWidget);

      HomeRoute.page = homePage;
      MyWorkRoute.page = workPage;
      InboxRoute.page = inboxPage;
      ConstellationRoute.page = constellationPage;
      FriendsRoute.page = friendsPage;
      ProfileRoute.page = mePage;
    });
  });
}

final class _FakeSettingsCubit extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}
