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
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/widget/inbox_navbar_item.dart';
import 'package:tentura/features/home/ui/widget/my_work_navbar_item.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _SurfaceRepository extends AttentionRepositoryFake {
  AttentionSurfaceSummary surfaceSummaryValue = const AttentionSurfaceSummary(
    activityUnreadTotal: 0,
    myWorkUnreadTotal: 0,
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
      const {};

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

Future<void> _settle([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

AttentionReceipt _updateReceipt({
  required AttentionSurface surface,
  String id = 'r1',
}) =>
    AttentionReceipt(
      id: id,
      category: surface == AttentionSurface.activity ? 'social' : 'requestProgress',
      kind: surface == AttentionSurface.activity
          ? 'inviteAccepted'
          : 'relayReceived',
      priority: 'normal',
      title: 'Title',
      body: 'Body',
      actionUrl: '/profile/view/U2',
      createdAt: DateTime.utc(2026, 9, 10),
      collapsedCount: 1,
      presentationPayloadJson: '{}',
      surface: surface,
      destinationKind: 'profile',
      targetEntityId: 'U2',
      presentationKey:
          surface == AttentionSurface.activity ? 'invite_accepted' : null,
      beaconId: surface == AttentionSurface.myWork ? 'beacon-1' : null,
    );

HomeAttentionState _redesignState({
  int activityUnread = 0,
  int myWorkUnread = 0,
  int needsYou = 0,
  HomeTab activeTab = HomeTab.work,
  bool loaded = true,
}) =>
    HomeAttentionState(
      surfaceSummaryLoaded: loaded,
      activityUnreadTotal: activityUnread,
      myWorkUnreadTotal: myWorkUnread,
      surfaceNeedsYouTotal: needsYou,
      activeHomeTab: activeTab,
    );

Future<({
  HomeAttentionCubit home,
  AttentionCase attention,
  TestRealtimeSyncPort sync,
})> _bootCubitWithSurface({
  required _Accounts accounts,
  required _SurfaceRepository repository,
  WidgetTester? tester,
}) async {
  final syncBundle = buildTestRealtimeSync();
  final attention = AttentionCase(
    repository,
    accounts,
    syncBundle.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('work-activity-nav-indicators'),
  );
  final home = HomeAttentionCubit(
    attention,
    accounts,
    Logger('work-activity-nav-indicators'),
  );
  accounts.emit('U1');
  if (tester != null) {
    for (var i = 0; i < 32; i++) {
      await tester.pump();
    }
  } else {
    await _settle(24);
  }
  return (home: home, attention: attention, sync: syncBundle.port);
}

Future<void> _disposeBoot(
  ({
    HomeAttentionCubit home,
    AttentionCase attention,
    TestRealtimeSyncPort sync,
  }) boot,
) async {
  await boot.home.close();
  await boot.attention.dispose();
  await boot.sync.dispose();
}

final class _FakeAuthCubit extends Fake implements AuthCubit {
  _FakeAuthCubit()
    : _state = AuthState(updatedAt: DateTime(2026), currentAccountId: 'U1');

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

void main() {
  group('HomeAttentionState redesign indicator getters', () {
    // U14c: every expectation below is a function of the totals alone. No case
    // names the active tab as a reason, because §6 gives it no say: "Indicators
    // do not hide because the tab is currently open", and dot and number are
    // independent rather than one gating the other.
    const cases = <({
      String name,
      int activity,
      int myWorkUnread,
      int needsYou,
      HomeTab tab,
      bool activityDot,
      bool myWorkNumber,
      bool myWorkDot,
    })>[
      (
        name: 'obligations and optional updates show a number and a dot',
        activity: 2,
        myWorkUnread: 1,
        needsYou: 3,
        tab: HomeTab.work,
        activityDot: true,
        myWorkNumber: true,
        myWorkDot: true,
      ),
      (
        name: 'the activity dot survives its own tab being open',
        activity: 2,
        myWorkUnread: 1,
        needsYou: 3,
        tab: HomeTab.inbox,
        activityDot: true,
        myWorkNumber: true,
        myWorkDot: true,
      ),
      (
        name: 'activity unread only',
        activity: 1,
        myWorkUnread: 0,
        needsYou: 0,
        tab: HomeTab.work,
        activityDot: true,
        myWorkNumber: false,
        myWorkDot: false,
      ),
      (
        name: 'my work unread dot when no obligations',
        activity: 0,
        myWorkUnread: 2,
        needsYou: 0,
        tab: HomeTab.inbox,
        activityDot: false,
        myWorkNumber: false,
        myWorkDot: true,
      ),
      (
        name: 'the my work dot survives its own tab being open',
        activity: 0,
        myWorkUnread: 2,
        needsYou: 0,
        tab: HomeTab.work,
        activityDot: false,
        myWorkNumber: false,
        myWorkDot: true,
      ),
      (
        name: 'obligations do not extinguish the my work dot',
        activity: 0,
        myWorkUnread: 4,
        needsYou: 2,
        tab: HomeTab.inbox,
        activityDot: false,
        myWorkNumber: true,
        myWorkDot: true,
      ),
      (
        name: 'all clear',
        activity: 0,
        myWorkUnread: 0,
        needsYou: 0,
        tab: HomeTab.work,
        activityDot: false,
        myWorkNumber: false,
        myWorkDot: false,
      ),
    ];

    for (final c in cases) {
      test(c.name, () {
        final state = _redesignState(
          activityUnread: c.activity,
          myWorkUnread: c.myWorkUnread,
          needsYou: c.needsYou,
          activeTab: c.tab,
        );
        expect(state.showRedesignActivityUnreadDot, c.activityDot);
        expect(state.showRedesignMyWorkObligationBadge, c.myWorkNumber);
        expect(state.showRedesignMyWorkUnreadDot, c.myWorkDot);
      });
    }

    test('no indicator changes when the active tab does', () {
      for (final c in cases) {
        final readings = <({bool activity, bool number, bool dot})>{
          for (final tab in HomeTab.values)
            () {
              final state = _redesignState(
                activityUnread: c.activity,
                myWorkUnread: c.myWorkUnread,
                needsYou: c.needsYou,
                activeTab: tab,
              );
              return (
                activity: state.showRedesignActivityUnreadDot,
                number: state.showRedesignMyWorkObligationBadge,
                dot: state.showRedesignMyWorkUnreadDot,
              );
            }(),
        }.toSet();
        expect(
          readings,
          hasLength(1),
          reason: 'the active tab changed an indicator for "${c.name}"',
        );
      }
    });

    test('the getters read the shared predicate, not a local copy', () {
      for (final total in [0, 1, 5]) {
        final state = _redesignState(
          activityUnread: total,
          myWorkUnread: total,
          needsYou: total,
        );
        expect(
          state.showRedesignActivityUnreadDot,
          surfaceDotFromTotal(total),
        );
        expect(state.showRedesignMyWorkUnreadDot, surfaceDotFromTotal(total));
        expect(
          state.showRedesignMyWorkObligationBadge,
          surfaceCountFromTotal(total) > 0,
        );
      }
    });

    test('M1 — a lit surface indicator implies a non-empty default list', () {
      // The totals are server counts of the authorized default list (U10b), so
      // "lit" and "the list has rows" are the same statement. Asserted here so
      // a future getter cannot light on something the list does not return.
      for (final activity in [0, 2]) {
        for (final myWorkUnread in [0, 2]) {
          for (final needsYou in [0, 3]) {
            final state = _redesignState(
              activityUnread: activity,
              myWorkUnread: myWorkUnread,
              needsYou: needsYou,
            );
            expect(state.showRedesignActivityUnreadDot, activity > 0);
            expect(state.showRedesignMyWorkUnreadDot, myWorkUnread > 0);
            expect(state.showRedesignMyWorkObligationBadge, needsYou > 0);
          }
        }
      }
    });

    test('the unloaded summary lights nothing', () {
      final state = _redesignState(
        activityUnread: 3,
        myWorkUnread: 3,
        needsYou: 3,
        loaded: false,
      );
      expect(state.showRedesignActivityUnreadDot, isFalse);
      expect(state.showRedesignMyWorkObligationBadge, isFalse);
      expect(state.showRedesignMyWorkUnreadDot, isFalse);
    });
  });

  group('HomeAttentionCubit surface summary', () {
    late _Accounts accounts;
    late _SurfaceRepository repository;

    setUp(() {
      accounts = _Accounts();
      repository = _SurfaceRepository();
    });

    tearDown(() async {
      await accounts.close();
    });

    test('maps AttentionCase.surfaceSummary into state', () async {
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        activityUnreadTotal: 1,
        myWorkUnreadTotal: 0,
        needsYouTotal: 0,
      );
      final boot = await _bootCubitWithSurface(
        accounts: accounts,
        repository: repository,
      );
      expect(boot.home.state.surfaceSummaryLoaded, isTrue);
      expect(boot.home.state.activityUnreadTotal, 1);
      expect(boot.home.state.showRedesignActivityUnreadDot, isTrue);
      await _disposeBoot(boot);
    });

    test('invite_accepted activity surface lights Activity dot only', () async {
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        activityUnreadTotal: 1,
        myWorkUnreadTotal: 0,
        needsYouTotal: 0,
      );
      final boot = await _bootCubitWithSurface(
        accounts: accounts,
        repository: repository,
      );
      expect(boot.home.state.showRedesignActivityUnreadDot, isTrue);
      expect(boot.home.state.showRedesignMyWorkUnreadDot, isFalse);
      expect(boot.home.state.showRedesignMyWorkObligationBadge, isFalse);
      await _disposeBoot(boot);
    });

    test('beacon-scoped my work unread lights My Work only', () async {
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        activityUnreadTotal: 0,
        myWorkUnreadTotal: 1,
        needsYouTotal: 0,
      );
      final boot = await _bootCubitWithSurface(
        accounts: accounts,
        repository: repository,
      );
      expect(boot.home.state.showRedesignActivityUnreadDot, isFalse);
      expect(boot.home.state.showRedesignMyWorkUnreadDot, isTrue);
      expect(boot.home.state.showRedesignMyWorkObligationBadge, isFalse);
      await _disposeBoot(boot);
    });
  });

  group('tab icons — dot and number are independent (§6, D09)', () {
    late _Accounts accounts;
    late _SurfaceRepository repository;

    setUp(() {
      accounts = _Accounts();
      repository = _SurfaceRepository();
    });

    tearDown(() async {
      await accounts.close();
    });

    Future<HomeAttentionCubit> pumpNav(
      WidgetTester tester, {
      required HomeTab activeTab,
    }) async {
      // A tree must exist before `tester.pump()` can drive the cubit's boot.
      await tester.pumpWidget(const SizedBox.shrink());
      final boot = await _bootCubitWithSurface(
        accounts: accounts,
        repository: repository,
        tester: tester,
      );
      addTearDown(() => _disposeBoot(boot));
      boot.home.setActiveHomeTab(activeTab);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: BlocProvider<HomeAttentionCubit>.value(
            value: boot.home,
            child: const Scaffold(
              body: Row(
                children: [
                  MyWorkNavbarItem(selected: true),
                  InboxNavbarItem(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return boot.home;
    }

    // CHANGES IN U15R-c (was: "the count takes the slot while obligations
    // are live", asserting the dot was suppressed). That came from the U14c
    // brief's paraphrase, not from the contract: §6 and D09 both say the dot
    // and the number are independent and appear together (R7).
    testWidgets('the dot and the number appear together', (
      tester,
    ) async {
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        activityUnreadTotal: 1,
        myWorkUnreadTotal: 2,
        needsYouTotal: 3,
      );
      final home = await pumpNav(tester, activeTab: HomeTab.work);

      expect(find.text('3'), findsOneWidget);
      expect(find.byKey(MyWorkNavbarItem.countKey), findsOneWidget);
      expect(find.byKey(MyWorkNavbarItem.dotKey), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(lookupL10n(const Locale('en')).myWorkNavBadgeObligations(3)),
        ),
        findsOneWidget,
      );
      expect(home.state.showRedesignMyWorkUnreadDot, isTrue);
    });

    testWidgets('the dot returns when the count drops to zero', (tester) async {
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        activityUnreadTotal: 0,
        myWorkUnreadTotal: 2,
        needsYouTotal: 0,
      );
      final home = await pumpNav(tester, activeTab: HomeTab.work);

      expect(find.text('0'), findsNothing);
      expect(home.state.showRedesignMyWorkObligationBadge, isFalse);
      expect(home.state.showRedesignMyWorkUnreadDot, isTrue);
      // My Work carries the dot; Activity is clear, so exactly one Badge.
      expect(find.byType(Badge), findsOneWidget);
      expect(find.byKey(MyWorkNavbarItem.dotKey), findsOneWidget);
      expect(find.byKey(MyWorkNavbarItem.countKey), findsNothing);
    });

    testWidgets('the Activity dot shows while Activity is the open tab', (
      tester,
    ) async {
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        activityUnreadTotal: 4,
        myWorkUnreadTotal: 0,
        needsYouTotal: 0,
      );
      final home = await pumpNav(tester, activeTab: HomeTab.inbox);

      expect(home.state.showRedesignActivityUnreadDot, isTrue);
      // For You never carries a count, however many events it holds.
      expect(find.text('4'), findsNothing);
      expect(find.byType(Badge), findsOneWidget);
    });

    testWidgets('the My Work number shows while My Work is the open tab', (
      tester,
    ) async {
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        activityUnreadTotal: 0,
        myWorkUnreadTotal: 2,
        needsYouTotal: 5,
      );
      await pumpNav(tester, activeTab: HomeTab.work);
      expect(find.text('5'), findsOneWidget);
    });
  });

  group('nav bar semantics copy under redesign gate', () {
    test('obligation badge label differs from activity dot label', () {
      final l10n = lookupL10n(const Locale('en'));
      expect(l10n.myWorkNavBadgeObligations(3), '3 obligations');
      expect(l10n.activityNavBadgeNewActivity, 'New activity');
      expect(
        l10n.myWorkNavBadgeObligations(3),
        isNot(l10n.activityNavBadgeNewActivity),
      );
    });
  });

  group('openFromUpdate branch selection', () {
    late RootRouter router;
    late PageInfo homePage;
    late PageInfo workPage;
    late PageInfo inboxPage;

    setUpAll(() {
      homePage = HomeRoute.page;
      workPage = MyWorkRoute.page;
      inboxPage = InboxRoute.page;
      HomeRoute.page = PageInfo(
        HomeRoute.name,
        builder: (_) => const _TestHomeShell(),
      );
      MyWorkRoute.page = PageInfo(
        MyWorkRoute.name,
        builder: (_) =>
            const Text('work-root', textDirection: TextDirection.ltr),
      );
      InboxRoute.page = PageInfo(
        InboxRoute.name,
        builder: (_) =>
            const Text('inbox-root', textDirection: TextDirection.ltr),
      );
      ProfileViewRoute.page = PageInfo(
        ProfileViewRoute.name,
        builder: (data) => Text(
          'profile:${data.inheritedPathParams.getString('id', '')}',
          textDirection: TextDirection.ltr,
        ),
      );
    });

    tearDownAll(() {
      HomeRoute.page = homePage;
      MyWorkRoute.page = workPage;
      InboxRoute.page = inboxPage;
    });

    setUp(() {
      if (!GetIt.I.isRegistered<HomeTabReselectCubit>()) {
        GetIt.I.registerSingleton<HomeTabReselectCubit>(HomeTabReselectCubit());
      }
      router = RootRouter(
        Logger('openFromUpdateTest'),
        _FakeAuthCubit(),
        _FakeSettingsCubit(),
        PostJoinNavigationCubit(),
      );
    });

    tearDown(() {
      router.dispose();
      if (GetIt.I.isRegistered<HomeTabReselectCubit>()) {
        GetIt.I.unregister<HomeTabReselectCubit>();
      }
    });

    Future<void> pumpOnWorkTab(WidgetTester tester) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue =
          kPathMyWork;
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

    testWidgets('gate on: activity surface selects Activity branch', (
      tester,
    ) async {
      await pumpOnWorkTab(tester);
      final tabs = router.innerRouterOf<TabsRouter>(HomeRoute.name)!;
      expect(tabs.activeIndex, HomeTabSpec.forTab(HomeTab.work).index);

      unawaited(
        router.openFromUpdate(_updateReceipt(surface: AttentionSurface.activity)),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump();
      }

      expect(tabs.activeIndex, HomeTabSpec.forTab(HomeTab.inbox).index);
      expect(find.text('profile:U2'), findsOneWidget);
    });

    testWidgets('gate on: myWork surface selects Work branch', (tester) async {
      await pumpOnWorkTab(tester);
      final tabs = router.innerRouterOf<TabsRouter>(HomeRoute.name)!;

      unawaited(
        router.openFromUpdate(_updateReceipt(surface: AttentionSurface.myWork)),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump();
      }

      expect(tabs.activeIndex, HomeTabSpec.forTab(HomeTab.work).index);
      expect(find.text('profile:U2'), findsOneWidget);
    });

  });
}
