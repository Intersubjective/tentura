// #500: the Home rail was no navigation landmark and had no skip link, so on
// web a screen reader met one flat list of nodes and a keyboard user tabbed
// through all of the rail before reaching the page.
//
// Spec, for the rail on Home and beside root routes (HomeRailFrame):
// - the rail is ONE named navigation landmark holding every destination and
//   the account entry, and nothing of the page;
// - a «Skip to content» button sits OUTSIDE and BEFORE that landmark: not
//   inside the navigation node, ahead of it in screen-reader order, and the
//   first Tab stop (reached by Tab, not autofocused); it shows when it has
//   focus, and Enter on it moves focus into the page beside the rail so the
//   next Tab lands on the page's first control, not back in the rail;
// - after it, the keyboard walks the rail before the page.
// Compact windows: the bottom bar is the same named navigation landmark.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/app/router/root_router.dart';
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
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../my_work/my_work_test_support.dart';

const _destinationLabels = ['Requests', 'Posts', 'Activity', 'Field', 'People'];
const _pageButton = 'in content';

/// The page beside the rail: one focusable control at its top-left corner.
class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: ElevatedButton(onPressed: () {}, child: const Text(_pageButton)),
    ),
  );
}

late L10n _l10n;

Future<void> _pumpFrame(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Builder(
          builder: (context) {
            _l10n = L10n.of(context)!;
            return const HomeRailFrame(
              selectedTab: HomeTab.work,
              child: _Page(),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
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

/// Signed out: Home skips the account-scoped Inbox / My Work providers, so
/// only the shell chrome (rail or bottom bar + tab content) is under test.
class _SignedOutAuthCubit extends Fake implements AuthCubit {
  @override
  AuthState get state => AuthState(updatedAt: DateTime.utc(2026, 10, 20));

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

/// The real HomeRoute page and shell; the Work tab root is [_Page], every
/// other tab root a stand-in.
Future<void> _pumpHome(WidgetTester tester, {required Size size}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

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
    ..registerSingleton<Logger>(Logger('home-nav-landmark'))
    ..registerSingleton<HomeAttentionCubit>(homeAttention)
    ..registerSingleton<PostJoinNavigationCubit>(postJoin)
    ..registerSingleton<PostJoinBeaconHandoffPort>(_NoInviteHandoff());

  final router = RootStackRouter.build(
    routes: [
      AutoRoute(
        page: HomeRoute.page,
        path: '/home',
        initial: true,
        children: [
          for (final spec in HomeTabSpec.all)
            AutoRoute(
              page: spec.shell.page,
              path: spec.path.split('/').last,
              initial: spec.tab == HomeTab.work,
              children: [
                AutoRoute(
                  page: PageInfo(
                    spec.rootRoute().routeName,
                    builder: (_) => spec.tab == HomeTab.work
                        ? const _Page()
                        : const SizedBox.shrink(),
                  ),
                  path: '',
                  initial: true,
                ),
              ],
            ),
        ],
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
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
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      routerConfig: router.config(),
      builder: (context, child) {
        _l10n = L10n.of(context)!;
        return TenturaResponsiveScope(child: child!);
      },
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(HomeScreen), findsOneWidget);
  expect(find.text(_pageButton), findsOneWidget);
}

/// Every semantics node, depth-first in the order a screen reader (and the
/// web DOM) walks them.
List<SemanticsNode> _readingOrder(WidgetTester tester) {
  final root = tester
      .getSemantics(find.text(_pageButton))
      .owner!
      .rootSemanticsNode!;
  final out = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    out.add(node);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(root);
  return out;
}

List<String> _labelsUnder(SemanticsNode node) {
  final out = <String>[node.label];
  node.visitChildren((child) {
    out.addAll(_labelsUnder(child));
    return true;
  });
  return out;
}

List<SemanticsNode> _navLandmarks(WidgetTester tester) => [
  for (final node in _readingOrder(tester))
    if (node.getSemanticsData().role == SemanticsRole.navigation) node,
];

/// The one named navigation landmark: every destination (and [alsoInside])
/// under it, and none of the page.
void _expectNavLandmark(
  WidgetTester tester, {
  List<String> alsoInside = const [],
}) {
  final landmarks = _navLandmarks(tester);
  expect(landmarks, hasLength(1), reason: 'exactly one navigation landmark');
  final nav = landmarks.single;
  expect(nav.label, _l10n.homeNavLandmark);
  expect(nav.label, isNotEmpty);
  final inside = _labelsUnder(nav).join('\n');
  for (final label in [..._destinationLabels, ...alsoInside]) {
    expect(inside, contains(label), reason: '$label is in the landmark');
  }
  expect(inside, isNot(contains(_pageButton)), reason: 'the page is not');
  expect(
    inside,
    isNot(contains(_l10n.skipToContent)),
    reason: 'Skip to content sits outside the landmark',
  );
}

bool _isUnder(SemanticsNode node, SemanticsNode ancestor) {
  for (var n = node.parent; n != null; n = n.parent) {
    if (n == ancestor) return true;
  }
  return false;
}

/// Skip to content: outside the navigation landmark and before it; the rail
/// before the page.
void _expectSkipBeforeAndOutsideNav(WidgetTester tester) {
  final skip = _skipNode(tester);
  expect(skip, isNotNull, reason: 'a Skip to content button exists');
  final nav = _navLandmarks(tester).single;
  expect(
    _isUnder(skip!, nav),
    isFalse,
    reason: 'Skip to content is not inside the navigation landmark',
  );
  final order = _readingOrder(tester);
  final skipAt = order.indexOf(skip);
  final navAt = order.indexOf(nav);
  final pageAt = _firstIndexOf(order, _pageButton);
  expect(skipAt, lessThan(navAt), reason: 'skip before the rail');
  expect(navAt, lessThan(pageAt), reason: 'rail before the page');
  for (final label in _destinationLabels) {
    expect(
      _firstIndexOf(order, label),
      lessThan(pageAt),
      reason: '$label before the page',
    );
  }
}

SemanticsNode? _skipNode(WidgetTester tester) {
  for (final node in _readingOrder(tester)) {
    final data = node.getSemanticsData();
    if (data.label.contains(_l10n.skipToContent) &&
        data.hasAction(SemanticsAction.tap)) {
      return node;
    }
  }
  return null;
}

/// Index of the first node in reading order whose label contains [label].
int _firstIndexOf(List<SemanticsNode> order, String label) =>
    order.indexWhere((n) => n.label.contains(label));

/// Whether the focused node's element is an ancestor of [matching].
bool _focusedEncloses(Finder matching) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  return find
      .descendant(
        of: find.byElementPredicate((e) => e == focused, skipOffstage: false),
        matching: matching,
      )
      .evaluate()
      .isNotEmpty;
}

/// Focus is on the skip control itself — not on a screen-wide scope that
/// merely contains it (a route's scope encloses the skip text too).
bool _skipHasFocus() {
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null || focus is FocusScopeNode) return false;
  final skipText = find.text(_l10n.skipToContent, skipOffstage: false);
  return _focusedEncloses(skipText) &&
      !_focusedEncloses(find.byType(NavigationRail, skipOffstage: false)) &&
      !_focusedEncloses(find.text(_pageButton, skipOffstage: false));
}

/// Focus is on the page's first control (its button), not on a scope or
/// wrapper around the page.
void _expectPageButtonFocused(String reason) {
  final focus = FocusManager.instance.primaryFocus;
  expect(focus, isNotNull, reason: reason);
  expect(focus, isNot(isA<FocusScopeNode>()), reason: '$reason (a control)');
  final focused = focus!.context!;
  expect(
    _focusedEncloses(find.text(_pageButton, skipOffstage: false)),
    isTrue,
    reason: reason,
  );
  expect(
    find.ancestor(
      of: find.byElementPredicate((e) => e == focused, skipOffstage: false),
      matching: find.byType(ElevatedButton),
    ),
    findsOneWidget,
    reason: '$reason (the page button itself)',
  );
}

/// Where keyboard focus is: on the skip button, in the rail, in the page
/// right of the rail, or elsewhere.
String _focusAt(Rect rail) {
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null || focus.context == null) return 'none';
  if (_skipHasFocus()) return 'skip';
  final rect = focus.rect;
  if (rail.contains(rect.center)) return 'rail';
  // Wholly right of the rail: a bare unfocus leaves the screen-wide scope
  // focused, which is not the page.
  if (rect.left >= rail.right - 0.5) return 'page';
  return 'other';
}

Future<void> _tab(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// From a freshly opened page: nothing is focused yet (Skip to content is
/// a skip link, shown on the first Tab, not autofocused), and the first Tab
/// lands on it.
Future<void> _firstTabLandsOnSkip(WidgetTester tester, Rect rail) async {
  expect(_skipHasFocus(), isFalse, reason: 'not autofocused on open');
  await _tab(tester);
  expect(_focusAt(rail), 'skip', reason: 'first Tab stop');
}

void _expectSkipShown(WidgetTester tester) {
  final text = find.text(_l10n.skipToContent);
  expect(text.hitTestable(), findsOneWidget, reason: 'shown when focused');
  final rect = tester.getRect(text);
  expect(rect.width, greaterThan(0));
  expect(rect.height, greaterThan(0));
  expect(
    Offset.zero & tester.view.physicalSize,
    predicate<Rect>((screen) => screen.contains(rect.center)),
    reason: 'on screen',
  );
}

Future<void> _activateSkipAndExpectPageFocus(
  WidgetTester tester,
  Rect rail,
) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  expect(_focusAt(rail), 'page', reason: 'focus moved into the page');
  final focused = FocusManager.instance.primaryFocus!.context!;
  expect(
    find.ancestor(
      of: find.byElementPredicate((e) => e == focused, skipOffstage: false),
      matching: find.byType(NavigationRail),
    ),
    findsNothing,
    reason: 'not left in the rail',
  );
}

/// Enter on Skip, then Tab: the page's first control, not the rail.
Future<void> _skipThenTabLandsOnPageControl(
  WidgetTester tester,
  Rect rail,
) async {
  await _activateSkipAndExpectPageFocus(tester, rail);
  await _tab(tester);
  expect(_focusAt(rail), 'page', reason: 'next Tab stays in the page');
  _expectPageButtonFocused('next Tab after Skip: the first page control');
}

void main() {
  group('beside a root route (HomeRailFrame)', () {
    testWidgets('#500 the rail is one named navigation landmark', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpFrame(tester);

      _expectNavLandmark(tester, alsoInside: const ['Profile']);
      semantics.dispose();
    });

    testWidgets('#500 screen readers meet Skip to content, then the rail', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpFrame(tester);

      _expectSkipBeforeAndOutsideNav(tester);
      semantics.dispose();
    });

    testWidgets('#500 keyboard: skip first, then the whole rail, then page', (
      tester,
    ) async {
      await _pumpFrame(tester);
      final rail = tester.getRect(find.byType(NavigationRail));

      await _firstTabLandsOnSkip(tester, rail);
      _expectSkipShown(tester);

      // Walk one full cycle (until skip comes round again).
      final stops = <String>['skip'];
      for (var i = 0; i < 20; i++) {
        await _tab(tester);
        final at = _focusAt(rail);
        if (at == 'skip') break;
        stops.add(at);
      }
      // Five destinations and the account entry.
      expect(
        stops.where((s) => s == 'rail').length,
        greaterThanOrEqualTo(6),
        reason: 'five destinations and the account: $stops',
      );
      expect(stops, contains('page'));
      expect(
        stops.lastIndexOf('rail'),
        lessThan(stops.indexOf('page')),
        reason: 'every rail stop before the page: $stops',
      );
      expect(stops[1], 'rail', reason: 'the rail right after skip: $stops');
    });

    testWidgets('#500 Skip to content: Enter, then Tab is the page control', (
      tester,
    ) async {
      await _pumpFrame(tester);
      final rail = tester.getRect(find.byType(NavigationRail));

      await _firstTabLandsOnSkip(tester, rail);
      await _skipThenTabLandsOnPageControl(tester, rail);
    });
  });

  group('Home (wide window, rail)', () {
    testWidgets('#500 the rail is one named navigation landmark', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpHome(tester, size: const Size(1280, 800));

      expect(find.byType(NavigationRail), findsOneWidget);
      _expectNavLandmark(tester, alsoInside: const ['Profile']);
      semantics.dispose();
    });

    testWidgets('#500 screen readers meet Skip to content, then the rail', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpHome(tester, size: const Size(1280, 800));
      final rail = tester.getRect(find.byType(NavigationRail));

      _expectSkipBeforeAndOutsideNav(tester);

      // What the web engine sends when a screen reader lands on the node.
      final skip = _skipNode(tester)!;
      skip.owner!.performAction(skip.id, SemanticsAction.focus);
      await tester.pump();
      expect(_focusAt(rail), 'skip');
      _expectSkipShown(tester);
      await _activateSkipAndExpectPageFocus(tester, rail);
      semantics.dispose();
    });

    // Home's tab content lives in nested Navigators: on open, focus sits in
    // the active tab route's own FocusScope, so a plain Tab searches only the
    // page and skips the rail and any skip control (#500).
    testWidgets('#500 keyboard: first Tab is Skip; Enter, Tab is the page', (
      tester,
    ) async {
      await _pumpHome(tester, size: const Size(1280, 800));
      final rail = tester.getRect(find.byType(NavigationRail));

      await _firstTabLandsOnSkip(tester, rail);
      _expectSkipShown(tester);
      await _skipThenTabLandsOnPageControl(tester, rail);
    });
  });

  group('Home (compact window, bottom bar)', () {
    testWidgets('#500 the bottom bar is the named navigation landmark', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpHome(tester, size: const Size(390, 800));

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(HomeBottomNavigationBar), findsOneWidget);
      _expectNavLandmark(tester);
      semantics.dispose();
    });
  });
}
