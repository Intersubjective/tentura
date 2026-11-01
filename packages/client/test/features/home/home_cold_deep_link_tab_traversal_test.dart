// #927: a cold start into a browse detail (deep link or reload of
// `#/graph/<id>`) pushes Home and the detail in one frame. Home sits under
// the detail and is never laid out, and on main the first Tab sorted Home's
// focus nodes: `RenderBox was not laid out` (TENTURA-CLIENT-54, QA
// 2026-11-01 11:16). In-app navigation lays Home out first, so it never
// crashed there. The fix builds Home's tab shell only once Home has been the
// current route.
//
// Real RootRouter (its routes, deep-link builder and browse stack), real
// HomeRoute page and shell; tab roots and the detail pages are stand-ins.
import 'dart:async';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/entity/post_join_destination.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/domain/port/post_join_beacon_handoff_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/home/ui/screen/home_screen.dart';
import 'package:tentura/features/home/ui/widget/home_bottom_navigation_bar.dart';
import 'package:tentura/features/home/ui/widget/home_rail_layout.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/a11y_focus.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../my_work/my_work_test_support.dart';

const _detailKey = Key('927.detail');
const _networkButton = 'network page control';
const _friendsTab = 'friends tab';
const _blockedUsers = 'blocked users page';

/// A browse detail with an ordered traversal group (as the Graph's person
/// panel mounts one).
class _Detail extends StatelessWidget {
  const _Detail(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: _detailKey,
    // Its back button pops to Home, as the real details' app bars do.
    appBar: AppBar(),
    body: FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FocusTraversalOrder(
            order: const NumericFocusOrder(0),
            child: TextButton(onPressed: () {}, child: Text('$label A')),
          ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: TextButton(onPressed: () {}, child: Text('$label B')),
          ),
        ],
      ),
    ),
  );
}

class _Network extends StatelessWidget {
  const _Network({this.tab});

  /// The Friends tab the route asked for (`?tab=`).
  final String? tab;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton(
            onPressed: () {},
            child: const Text(_networkButton),
          ),
          Text('$_friendsTab: $tab'),
        ],
      ),
    ),
  );
}

class _RouterAuthCubit extends Fake implements AuthCubit {
  @override
  AuthState get state => AuthState(
    updatedAt: DateTime.utc(2026, 11),
    currentAccountId: 'U1',
  );

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

class _SignedOutAuthCubit extends Fake implements AuthCubit {
  @override
  AuthState get state => AuthState(updatedAt: DateTime.utc(2026, 11));

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

class _Settings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

class _Accounts implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}

class _OrientationPreferences implements HomeOrientationPreferencesPort {
  @override
  Future<bool> isActivated({required String userId}) async => true;

  @override
  Future<bool> isOrientationDismissed({required String userId}) async => true;

  @override
  Future<OrientationDebugOverride> getDebugOverride() async =>
      OrientationDebugOverride.auto;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoInviteHandoff implements PostJoinBeaconHandoffPort {
  @override
  PostJoinDestination? readAndClear() => null;
}

PageInfo _page(String name, Widget child) =>
    PageInfo(name, builder: (_) => child);

/// Starts the app's RootRouter at [path], as a reload or a deep link does.
Future<RootRouter> _start(
  WidgetTester tester, {
  required String path,
  required Locale locale,
}) async {
  final homeActivation = HomeActivationCubit(_OrientationPreferences());
  final homeAttention = HomeAttentionCubit(
    buildStubAttentionCase(),
    _Accounts(),
    Logger('home-attention'),
  );
  final inbox = InboxOperationalCubit();
  final reselect = HomeTabReselectCubit();
  final effects = FakeUiEffectPort();
  final screen = ScreenCubit.local(effects);
  final postJoin = PostJoinNavigationCubit();
  GetIt.I
    ..registerSingleton<AuthCubit>(_SignedOutAuthCubit())
    ..registerSingleton<ScreenCubit>(screen)
    ..registerSingleton<HomeTabReselectCubit>(reselect)
    ..registerSingleton<InboxOperationalCubit>(inbox)
    ..registerSingleton<HomeActivationCubit>(homeActivation)
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<Logger>(Logger('home-927-cold'))
    ..registerSingleton<HomeAttentionCubit>(homeAttention)
    ..registerSingleton<PostJoinNavigationCubit>(postJoin)
    ..registerSingleton<PostJoinBeaconHandoffPort>(_NoInviteHandoff());

  final router = RootRouter(
    Logger('home-927-cold-router'),
    _RouterAuthCubit(),
    _Settings(),
    postJoin,
  );
  tester.binding.platformDispatcher.defaultRouteNameTestValue = path;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    tester.binding.platformDispatcher.clearDefaultRouteNameTestValue();
    await homeActivation.close();
    await homeAttention.close();
    await inbox.close();
    await reselect.close();
    await screen.close();
    router.dispose();
    await GetIt.I.reset();
  });
  await tester.pumpWidget(
    MaterialApp.router(
      theme: TenturaTheme.light(),
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      routerConfig: router.config(
        deepLinkBuilder: router.deepLinkBuilder,
        deepLinkTransformer: router.deepLinkTransformer,
        reevaluateListenable: router.reevaluateListenable,
        includePrefixMatches: false,
      ),
      builder: (context, child) => TenturaResponsiveScope(child: child!),
    ),
  );
  await _settle(tester);
  return router;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Cold start into a browse detail: the reported state, Home mounted under
/// the detail and never shown.
Future<RootRouter> _coldStart(
  WidgetTester tester, {
  required String path,
  required Locale locale,
}) async {
  final router = await _start(tester, path: path, locale: locale);
  expect(find.byKey(_detailKey), findsOneWidget);
  expect(find.byType(HomeScreen), findsNothing, reason: 'Home is covered');
  expect(
    find.byType(HomeScreen, skipOffstage: false),
    findsOneWidget,
    reason: 'Home is mounted under the detail',
  );
  return router;
}

/// Home is shown and laid out with its whole shell: [nav] (rail or bottom
/// bar) and the Network tab's page.
void _expectHomeShell(WidgetTester tester, Finder nav) {
  expect(find.byKey(_detailKey), findsNothing);
  final shell = find.byType(HomeRailLayout);
  expect(shell, findsOneWidget, reason: 'Home shell is built');
  expect(tester.renderObject<RenderBox>(shell).hasSize, isTrue);
  expect(nav, findsOneWidget, reason: 'rail / bottom bar');
  expect(find.text(_networkButton), findsOneWidget, reason: 'Network tab');
}

/// Tab from Home's shell moves focus into Home without throwing, and the
/// screen reader's focus follows every stop.
Future<void> _tabTraversesHome(WidgetTester tester) async {
  final semantics = tester.ensureSemantics();
  try {
    final home = find.byType(HomeScreen);
    final seen = <String>[];
    var inHome = false;
    for (var i = 0; i < 6 && !inHome; i++) {
      await _tab(tester, shift: false);
      expect(tester.takeException(), isNull, reason: 'Tab #$i in Home');
      seen.add(_expectSemanticsFocus('Tab #$i in Home', seen));
      inHome = _focusUnder(home);
    }
    expect(inHome, isTrue, reason: 'Tab reaches Home once it is shown');
  } finally {
    semantics.dispose();
  }
}

/// A semantics node says it has focus: on the web the browser's focus (and
/// the screen reader's) follows Flutter's primaryFocus to this stop. Returns
/// the stop as the screen reader names it; [seen] are the earlier stops.
String _expectSemanticsFocus(String stop, [List<String> seen = const []]) {
  final nodes = focusedSemanticsNodes();
  expect(
    nodes,
    isNotEmpty,
    reason:
        '$stop focused ${FocusManager.instance.primaryFocus}, but no '
        'semantics node says it has focus. Stops so far: $seen',
  );
  return nodes.map(describeSemanticsNode).join(' + ');
}

bool _isUnder(BuildContext context, Element ancestor) {
  if (context == ancestor) return true;
  var found = false;
  context.visitAncestorElements((e) {
    if (e == ancestor) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

bool _focusUnder(Finder finder) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  final target = finder.evaluate();
  return target.isNotEmpty && _isUnder(focused, target.single);
}

bool _focusInDetail() => _focusUnder(find.byKey(_detailKey));

/// On the web, a Tab while the app has no focus first moves the browser's
/// focus into the Flutter view, which reports it as a view focus change.
Future<void> _enterViewIfUnfocused(
  WidgetTester tester, {
  required bool forward,
}) async {
  final focus = FocusManager.instance.primaryFocus;
  if (focus != null && focus != FocusManager.instance.rootScope) return;
  tester.binding.handleViewFocusChanged(
    ViewFocusEvent(
      viewId: tester.view.viewId,
      state: ViewFocusState.focused,
      direction: forward
          ? ViewFocusDirection.forward
          : ViewFocusDirection.backward,
    ),
  );
  await tester.pump();
}

Future<void> _tab(WidgetTester tester, {required bool shift}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

/// The first two Tabs (or Shift+Tabs) after the cold start: none throws,
/// the first already lands in the detail, and focus stays there.
Future<void> _firstTabsLandInDetail(
  WidgetTester tester, {
  required bool shift,
}) async {
  await _enterViewIfUnfocused(tester, forward: !shift);
  await _tab(tester, shift: shift);
  expect(tester.takeException(), isNull, reason: 'first Tab threw');
  final firstStop = FocusManager.instance.primaryFocus;
  final firstLanded = _focusInDetail();
  // With the bug the first Tab lands in the covered Home's «Skip to
  // content» and the second throws `RenderBox was not laid out`.
  await _tab(tester, shift: shift);
  expect(tester.takeException(), isNull, reason: 'second Tab threw');
  expect(firstLanded, isTrue, reason: 'the first Tab lands in the detail');
  expect(
    _focusInDetail(),
    isTrue,
    reason: 'Tab stays in the visible detail',
  );

  // The screen reader's focus at both stops. Semantics goes on only now:
  // with it on while the bug threw, the run hung instead of failing. The
  // first stop is checked by stepping back to it.
  final semantics = tester.ensureSemantics();
  try {
    await tester.pump();
    await tester.pump();
    final second = _expectSemanticsFocus('second Tab');
    await _tab(tester, shift: !shift);
    expect(tester.takeException(), isNull, reason: 'stepping back threw');
    expect(
      FocusManager.instance.primaryFocus,
      same(firstStop),
      reason: 'stepping back returns to the first stop',
    );
    _expectSemanticsFocus('first Tab', [second]);
  } finally {
    semantics.dispose();
  }
}

void _matrix({
  required String name,
  required Locale locale,
  required Future<void> Function(WidgetTester) surface,
  required Finder nav,
  // The phone keeps a branch's pushed detail full-screen: no bottom bar.
  required bool navHiddenOnBranchDetail,
}) {
  group('#927 cold deep link, $name', () {
    for (final shift in [false, true]) {
      final key = shift ? 'Shift+Tab' : 'Tab';
      testWidgets('graph: the first $key lands in the Graph, no throw', (
        tester,
      ) async {
        await surface(tester);
        await _coldStart(tester, path: '$kPathGraph/U2', locale: locale);
        await _firstTabsLandInDetail(tester, shift: shift);
      });
    }

    testWidgets('profile: the first Tab lands in the profile, no throw', (
      tester,
    ) async {
      await surface(tester);
      await _coldStart(tester, path: '$kPathProfileView/U2', locale: locale);
      await _firstTabsLandInDetail(tester, shift: false);
    });

    testWidgets('request: the first Tab lands in the request, no throw', (
      tester,
    ) async {
      await surface(tester);
      await _coldStart(tester, path: '$kPathBeaconView/B1', locale: locale);
      await _firstTabsLandInDetail(tester, shift: false);
    });

    for (final appBarBack in [false, true]) {
      final how = appBarBack ? 'the app-bar back' : 'router back';
      testWidgets(
        'graph, $how: Home is shown with its shell, Tab traverses it',
        (
          tester,
        ) async {
          await surface(tester);
          final router = await _coldStart(
            tester,
            path: '$kPathGraph/U2',
            locale: locale,
          );
          await _firstTabsLandInDetail(tester, shift: false);

          if (appBarBack) {
            await tester.tap(find.byType(BackButton));
          } else {
            await router.maybePop();
          }
          await _settle(tester);
          expect(tester.takeException(), isNull);
          _expectHomeShell(tester, nav);
          await _tabTraversesHome(tester);
        },
      );
    }

    testWidgets(
      'graph, notification link: the request opens on top, Back returns '
      'to the Graph',
      (tester) async {
        await surface(tester);
        final router = await _coldStart(
          tester,
          path: '$kPathGraph/U2',
          locale: locale,
        );

        unawaited(router.openFromNotificationLink('$kPathBeaconView/B1'));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('request A'), findsOneWidget);
        expect(router.stackData.map((r) => r.name), [
          HomeRoute.name,
          GraphRoute.name,
          BeaconViewRoute.name,
        ], reason: 'the Graph the person was on stays under the request');

        await router.maybePop();
        await _settle(tester);
        expect(find.text('graph A'), findsOneWidget, reason: 'Back: Graph');

        await router.maybePop();
        await _settle(tester);
        expect(tester.takeException(), isNull);
        _expectHomeShell(tester, nav);
      },
    );

    testWidgets('graph, open invitations: Network › Invitations in the shell', (
      tester,
    ) async {
      await surface(tester);
      final router = await _coldStart(
        tester,
        path: '$kPathGraph/U2',
        locale: locale,
      );

      unawaited(router.openInvitations());
      await _settle(tester);
      expect(tester.takeException(), isNull);
      _expectHomeShell(tester, nav);
      expect(
        router.innerRouterOf<TabsRouter>(HomeRoute.name)!.activeIndex,
        HomeTabSpec.forTab(HomeTab.network).index,
      );
      expect(find.text('$_friendsTab: $kHomeTabInvitations'), findsOneWidget);
    });

    testWidgets('profile, open blocked users: Blocked users in Network', (
      tester,
    ) async {
      await surface(tester);
      final router = await _coldStart(
        tester,
        path: '$kPathProfileView/U2',
        locale: locale,
      );

      unawaited(router.openBlockedUsers());
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(_detailKey), findsNothing);
      expect(find.text(_blockedUsers), findsOneWidget);
      final shell = find.byType(HomeRailLayout);
      expect(shell, findsOneWidget, reason: 'Home shell is built');
      expect(tester.renderObject<RenderBox>(shell).hasSize, isTrue);
      expect(
        router.innerRouterOf<TabsRouter>(HomeRoute.name)!.activeIndex,
        HomeTabSpec.forTab(HomeTab.network).index,
      );
      expect(nav, navHiddenOnBranchDetail ? findsNothing : findsOneWidget);

      // Back from Blocked users lands on Friends, bar and all.
      await router.maybePopTop();
      await _settle(tester);
      expect(tester.takeException(), isNull);
      _expectHomeShell(tester, nav);
    });

    testWidgets('in-app: Home stays built and laid out under the Graph', (
      tester,
    ) async {
      await surface(tester);
      final router = await _start(tester, path: kPathNetwork, locale: locale);
      _expectHomeShell(tester, nav);

      unawaited(router.push(GraphRoute(focus: 'U2')));
      await _settle(tester);
      expect(find.byKey(_detailKey), findsOneWidget);
      final shell = find.byType(HomeRailLayout, skipOffstage: false);
      expect(shell, findsOneWidget, reason: 'never a placeholder');
      expect(tester.renderObject<RenderBox>(shell).hasSize, isTrue);
      expect(find.text(_networkButton, skipOffstage: false), findsOneWidget);
      await _firstTabsLandInDetail(tester, shift: false);
    });
  });
}

void main() {
  late Map<String, PageInfo> saved;

  setUpAll(() {
    saved = {
      MyWorkRoute.name: MyWorkRoute.page,
      ConversationsRoute.name: ConversationsRoute.page,
      InboxRoute.name: InboxRoute.page,
      ConstellationRoute.name: ConstellationRoute.page,
      FriendsRoute.name: FriendsRoute.page,
      ProfileRoute.name: ProfileRoute.page,
      GraphRoute.name: GraphRoute.page,
      ProfileViewRoute.name: ProfileViewRoute.page,
      BeaconViewRoute.name: BeaconViewRoute.page,
      BeaconViewOperationalRoute.name: BeaconViewOperationalRoute.page,
      BlockedUsersRoute.name: BlockedUsersRoute.page,
    };
    const empty = SizedBox.shrink();
    MyWorkRoute.page = _page(MyWorkRoute.name, empty);
    ConversationsRoute.page = _page(ConversationsRoute.name, empty);
    InboxRoute.page = _page(InboxRoute.name, empty);
    ConstellationRoute.page = _page(ConstellationRoute.name, empty);
    FriendsRoute.page = PageInfo(
      FriendsRoute.name,
      builder: (data) => _Network(
        tab: data
            .argsAs<FriendsRouteArgs>(
              orElse: () => FriendsRouteArgs(
                initialTab: data.queryParams.optString('tab'),
              ),
            )
            .initialTab,
      ),
    );
    ProfileRoute.page = _page(ProfileRoute.name, empty);
    GraphRoute.page = _page(GraphRoute.name, const _Detail('graph'));
    ProfileViewRoute.page = _page(
      ProfileViewRoute.name,
      const _Detail('profile'),
    );
    // As in the app: the request route only hosts its child router, and the
    // request's page (app bar and controls) is the operational child. An
    // empty child would hold the route's initial focus with nothing to Tab
    // to, a state the app never produces.
    BeaconViewRoute.page = _page(BeaconViewRoute.name, const AutoRouter());
    BeaconViewOperationalRoute.page = _page(
      BeaconViewOperationalRoute.name,
      const _Detail('request'),
    );
    BlockedUsersRoute.page = _page(
      BlockedUsersRoute.name,
      const Scaffold(body: Text(_blockedUsers)),
    );
  });

  tearDownAll(() {
    MyWorkRoute.page = saved[MyWorkRoute.name]!;
    ConversationsRoute.page = saved[ConversationsRoute.name]!;
    InboxRoute.page = saved[InboxRoute.name]!;
    ConstellationRoute.page = saved[ConstellationRoute.name]!;
    FriendsRoute.page = saved[FriendsRoute.name]!;
    ProfileRoute.page = saved[ProfileRoute.name]!;
    GraphRoute.page = saved[GraphRoute.name]!;
    ProfileViewRoute.page = saved[ProfileViewRoute.name]!;
    BeaconViewRoute.page = saved[BeaconViewRoute.name]!;
    BeaconViewOperationalRoute.page = saved[BeaconViewOperationalRoute.name]!;
    BlockedUsersRoute.page = saved[BlockedUsersRoute.name]!;
  });

  setUp(() async => GetIt.I.reset());

  _matrix(
    name: 'desktop 1280x800 (en)',
    locale: const Locale('en'),
    nav: find.byType(NavigationRail),
    navHiddenOnBranchDetail: false,
    surface: (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    },
  );
  _matrix(
    name: 'phone 375x667 (ru)',
    locale: const Locale('ru'),
    nav: find.byType(HomeBottomNavigationBar),
    navHiddenOnBranchDetail: true,
    surface: (tester) async {
      await usePhoneSurface(tester);
      // MediaQuery follows the view: the bottom-bar (compact) Home shell.
      tester.view
        ..physicalSize = kPhoneSurface
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    },
  );
}
