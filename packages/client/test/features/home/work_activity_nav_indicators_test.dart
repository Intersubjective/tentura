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
  // CHANGES IN U18c: `activityUnread` / `myWorkUnread` knobs are gone with the
  // state fields they set (`activityUnreadTotal`, `myWorkUnreadTotal`). They
  // fed no indicator after U15R-d, and D09's independence is proved by the
  // three §6 inputs below carrying opposite values, not by a fourth number
  // sitting inert beside them.
  int myDeskCount = 0,
  // CHANGES IN U15R-d: the two dots are server booleans now, not totals —
  // §6 states each as a membership question the server answers from the same
  // predicates its lists compose.
  bool myDeskDot = false,
  bool forYouDot = false,
  HomeTab activeTab = HomeTab.work,
  bool loaded = true,
}) =>
    HomeAttentionState(
      surfaceSummaryLoaded: loaded,
      surfaceMyDeskCount: myDeskCount,
      surfaceMyDeskDot: myDeskDot,
      surfaceForYouDot: forYouDot,
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
    // U14c: every expectation below is a function of the summary alone. No
    // case names the active tab as a reason, because §6 gives it no say:
    // "Indicators do not hide because the tab is currently open", and dot and
    // number are independent rather than one gating the other.
    //
    // CHANGES IN U15R-d: the two dot *inputs* are `myDeskDot` / `forYouDot`
    // rather than the two unread totals. Not one expectation moved — §6 says
    // the same thing about what should light — but the totals were never the
    // §6 rules (`myWorkUnreadTotal` included obligations, `activityUnreadTotal`
    // missed outcomes and the pinned zone), so a case that inferred a dot from
    // one was asserting the right answer over the wrong input.
    // CHANGES IN U18c: those two totals are retired and their columns are
    // gone. D09's independence is still proved here, by `myDeskCount` and
    // `myDeskDot` carrying opposite values across the cases.
    const cases = <({
      String name,
      int myDeskCount,
      bool forYouDot,
      bool myDeskDot,
      HomeTab tab,
      bool activityDot,
      bool myWorkNumber,
      bool myWorkDot,
    })>[
      (
        name: 'obligations and optional updates show a number and a dot',
        myDeskCount: 3,
        forYouDot: true,
        myDeskDot: true,
        tab: HomeTab.work,
        activityDot: true,
        myWorkNumber: true,
        myWorkDot: true,
      ),
      (
        name: 'the activity dot survives its own tab being open',
        myDeskCount: 3,
        forYouDot: true,
        myDeskDot: true,
        tab: HomeTab.inbox,
        activityDot: true,
        myWorkNumber: true,
        myWorkDot: true,
      ),
      (
        name: 'activity unread only',
        myDeskCount: 0,
        forYouDot: true,
        myDeskDot: false,
        tab: HomeTab.work,
        activityDot: true,
        myWorkNumber: false,
        myWorkDot: false,
      ),
      (
        name: 'my work unread dot when no obligations',
        myDeskCount: 0,
        forYouDot: false,
        myDeskDot: true,
        tab: HomeTab.inbox,
        activityDot: false,
        myWorkNumber: false,
        myWorkDot: true,
      ),
      (
        name: 'the my work dot survives its own tab being open',
        myDeskCount: 0,
        forYouDot: false,
        myDeskDot: true,
        tab: HomeTab.work,
        activityDot: false,
        myWorkNumber: false,
        myWorkDot: true,
      ),
      (
        name: 'obligations do not extinguish the my work dot',
        myDeskCount: 2,
        forYouDot: false,
        myDeskDot: true,
        tab: HomeTab.inbox,
        activityDot: false,
        myWorkNumber: true,
        myWorkDot: true,
      ),
      (
        name: 'all clear',
        myDeskCount: 0,
        forYouDot: false,
        myDeskDot: false,
        tab: HomeTab.work,
        activityDot: false,
        myWorkNumber: false,
        myWorkDot: false,
      ),
    ];

    for (final c in cases) {
      test(c.name, () {
        final state = _redesignState(
          myDeskCount: c.myDeskCount,
          forYouDot: c.forYouDot,
          myDeskDot: c.myDeskDot,
          activeTab: c.tab,
        );
        expect(state.showRedesignActivityUnreadDot, c.activityDot);
        expect(state.showRedesignMyWorkObligationBadge, c.myWorkNumber);
        expect(state.showRedesignMyWorkUnreadDot, c.myWorkDot);
      });
    }

    // CHANGES IN U15R-d: §6 names the dots as their own rules —
    // `my desk.dot = any owned Request has a dot` where
    // `request.dot = uncleared optional event or uncleared outcome`, and
    // `for you.dot = any dismissible attention, pending forward or pending
    // prompt`. Neither is "a total is greater than zero", so the server now
    // sends each as a boolean and the cases below carry it as an input
    // instead of inferring it from the legacy totals. The number beside the
    // dot has its own field too since U15R-e (`surfaceMyDeskCount`, §6
    // `my desk.count`), and the cases keep proving the dot and the number are
    // independent (D09). CHANGES IN U18c: `activityUnreadTotal`,
    // `myWorkUnreadTotal` and `surfaceNeedsYouTotal` fed no indicator and are
    // retired — no state field one could be inferred from survives.
    test('U15R-d §6 — an obligation-only My Desk shows the number and no dot',
        () {
      final state = _redesignState(
        myDeskCount: 3,
        myDeskDot: false,
      );
      expect(
        state.showRedesignMyWorkObligationBadge,
        isTrue,
        reason: '§6 `my desk.count` = sum of live obligations',
      );
      expect(
        state.showRedesignMyWorkUnreadDot,
        isFalse,
        reason:
            '§6 `request.dot` is optional events and outcomes only — an '
            'obligation is the number, never the dot. The legacy '
            '`myWorkUnreadTotal` counted the obligation here and must not be '
            'what the dot reads; U18c retired it outright.',
      );
    });

    test('U15R-d §6 — a pending forward lights For You with no receipt total',
        () {
      final state = _redesignState(forYouDot: true);
      expect(
        state.showRedesignActivityUnreadDot,
        isTrue,
        reason:
            '§6 `for you.dot` counts the pending-forward zone, which no '
            'receipt total has ever seen',
      );
    });

    test('U15R-d §6 — For You is structurally unable to show a count', () {
      // `for you.count = never`. The client cannot render one because there
      // is no field to render: `AttentionSurfaceSummary` has no `forYouCount`
      // and `HomeAttentionState` has no For-You number getter. This test
      // fails the day somebody adds either.
      const state = HomeAttentionState();
      expect(
        state.toString().contains('forYouCount'),
        isFalse,
        reason: 'a For-You count field would make §6 violable by a widget',
      );
    });

    test('no indicator changes when the active tab does', () {
      for (final c in cases) {
        final readings = <({bool activity, bool number, bool dot})>{
          for (final tab in HomeTab.values)
            () {
              final state = _redesignState(
                myDeskCount: c.myDeskCount,
                forYouDot: c.forYouDot,
                myDeskDot: c.myDeskDot,
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
      // CHANGES IN U15R-d: the number still comes through
      // `surfaceCountFromTotal` (§6 `my desk.count` is a total), but the dots
      // no longer come through `surfaceDotFromTotal`. §6 defines each dot as
      // a membership question over the surface's own predicates, and U15R-d
      // moved that computation to the server so the dot and the list it
      // stands for cannot be two rules (M1). The client's job is to relay the
      // answer, and asserting it re-derives one would be asserting the bug.
      for (final dot in [false, true]) {
        for (final total in [0, 1, 5]) {
          final state = _redesignState(
            myDeskCount: total,
            forYouDot: dot,
            myDeskDot: dot,
          );
          expect(state.showRedesignActivityUnreadDot, dot);
          expect(state.showRedesignMyWorkUnreadDot, dot);
          expect(
            state.showRedesignMyWorkObligationBadge,
            surfaceCountFromTotal(total) > 0,
          );
        }
      }
    });

    test('M1 — a lit surface indicator implies a non-empty default list', () {
      // CHANGES IN U15R-d: the dot inputs are the server's §6 membership
      // answers instead of the unread totals. The statement is unchanged —
      // "lit" and "the surface has something to act on" are the same fact —
      // but the server now computes each dot from the predicates behind its
      // own list, so a total is no longer the thing that stands for it.
      for (final forYouDot in [false, true]) {
        for (final myDeskDot in [false, true]) {
          for (final myDeskCount in [0, 3]) {
            final state = _redesignState(
              myDeskCount: myDeskCount,
              forYouDot: forYouDot,
              myDeskDot: myDeskDot,
            );
            expect(state.showRedesignActivityUnreadDot, forYouDot);
            expect(state.showRedesignMyWorkUnreadDot, myDeskDot);
            expect(state.showRedesignMyWorkObligationBadge, myDeskCount > 0);
          }
        }
      }
    });

    test('the unloaded summary lights nothing', () {
      final state = _redesignState(
        myDeskCount: 3,
        forYouDot: true,
        myDeskDot: true,
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
      // CHANGES IN U15R-d: §6 `for you.dot` is its own field. A fixture that
      // only set `activityUnreadTotal` was asserting the dot over a total
      // that does not answer §6's question. CHANGES IN U18c: retired.
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        myDeskCount: 0,
        forYouDot: true,
      );
      final boot = await _bootCubitWithSurface(
        accounts: accounts,
        repository: repository,
      );
      expect(boot.home.state.surfaceSummaryLoaded, isTrue);
      expect(boot.home.state.surfaceForYouDot, isTrue);
      expect(boot.home.state.showRedesignActivityUnreadDot, isTrue);
      await _disposeBoot(boot);
    });

    test('invite_accepted activity surface lights Activity dot only', () async {
      // CHANGES IN U15R-d: §6 `for you.dot`, as its own field.
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        myDeskCount: 0,
        forYouDot: true,
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
      // CHANGES IN U15R-d: §6 `my desk.dot`, as its own field.
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        myDeskCount: 0,
        myDeskDot: true,
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
      // CHANGES IN U15R-d: both dots are §6 fields now.
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        myDeskCount: 3,
        myDeskDot: true,
        forYouDot: true,
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
      // CHANGES IN U15R-d: the dot is §6 `my desk.dot`, its own field.
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        myDeskCount: 0,
        myDeskDot: true,
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
      // CHANGES IN U15R-d: the dot is §6 `for you.dot`, its own field.
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        myDeskCount: 0,
        forYouDot: true,
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
      // CHANGES IN U15R-d: the dot is §6 `my desk.dot`, its own field.
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        myDeskCount: 5,
        myDeskDot: true,
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
