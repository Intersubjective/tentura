// #605 (from #495, #406): nothing pinned where a notice bar lands on a phone
// (compact window) with the Home bottom navigation bar showing. These guard
// the placement the app relies on: a plain notice is a fixed full-width bar
// directly above the bottom nav, an error floats above it, a body-bottom
// action inside a tab (SnackBarClearance) lifts bars above both, and with
// the bottom nav hidden (a pushed detail) the bar sits flush with the
// screen bottom.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/ui/widget/home_bottom_navigation_bar.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/snack_bar_clearance.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'snack_bar_clearance_support.dart';

const _compact = Size(390, 844);

const _labels = ['Requests', 'Posts', 'Activity', 'Field', 'People'];

const _notice = 'Invite saved';

const _error = 'Could not save the invite';

final _tabKey = GlobalKey(debugLabel: 'tab page');

final _actionKey = GlobalKey(debugLabel: 'body-bottom action');

final _nav = find.byType(HomeBottomNavigationBar);

Widget _bottomNav() => HomeBottomNavigationBar(
  selectedIndex: 0,
  onDestinationSelected: (_) {},
  destinations: [
    for (final label in _labels)
      HomeNavDestination(
        icon: const Icon(Icons.circle_outlined),
        selectedIcon: const Icon(Icons.circle),
        label: label,
      ),
  ],
);

/// The compact Home shell as the app builds it: an outer Scaffold with the
/// bottom navigation bar (null while a pushed detail is shown) around the
/// tab's own Scaffold, under the app-wide messenger.
Future<void> _pumpCompactHome(
  WidgetTester tester, {
  bool showBottomNav = true,
  bool bodyBottomAction = false,
}) async {
  tester.view
    ..physicalSize = _compact
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(Logger('test'));
    addTearDown(GetIt.I.reset);
  }

  await tester.pumpWidget(
    MaterialApp(
      scaffoldMessengerKey: snackbarKey,
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Scaffold(
          key: _tabKey,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: SizedBox()),
              if (bodyBottomAction)
                SnackBarClearance(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      key: _actionKey,
                      onPressed: () {},
                      child: const Text('Forward to 1'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: showBottomNav ? _bottomNav() : null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Lets the bar finish its entrance animation without waiting out its
/// auto-dismiss timer.
Future<void> _showBar(
  WidgetTester tester, {
  required String text,
  bool isError = false,
}) async {
  showSnackBar(
    tester.element(find.byKey(_tabKey)),
    text: text,
    isError: isError,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 750));
}

void _expectBarAboveBottomNav(WidgetTester tester) {
  final screen =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final bar = visibleSnackBarRect(tester);
  final nav = tester.getRect(_nav);
  expect(bar.height, greaterThan(0));
  expect(
    bar.top >= screen.top && bar.bottom <= screen.bottom,
    isTrue,
    reason: 'the bar must stay fully on screen, got $bar in $screen',
  );
  expect(
    bar.overlaps(nav),
    isFalse,
    reason: 'bar $bar is drawn over the bottom navigation bar $nav',
  );
  expect(bar.bottom, lessThanOrEqualTo(nav.top + 0.5));

  // Every tab of the bottom nav stays tappable under a showing bar.
  for (final label in _labels) {
    final tab = find.descendant(of: _nav, matching: find.text(label));
    final hit = tester.hitTestOnBinding(tester.getCenter(tab));
    expect(
      hit.path.any(
        (entry) => identical(entry.target, tester.renderObject(tab)),
      ),
      isTrue,
      reason: 'a tap on the $label tab must reach it, not the bar',
    );
  }
}

void main() {
  testWidgets('compact with bottom nav: a plain notice is a fixed full-width '
      'bar directly above the bottom nav', (tester) async {
    await _pumpCompactHome(tester);
    expect(_nav, findsOneWidget);

    await _showBar(tester, text: _notice);

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.behavior, isNot(SnackBarBehavior.floating));
    expect(snackBar.margin, isNull);

    _expectBarAboveBottomNav(tester);
    final bar = visibleSnackBarRect(tester);
    final nav = tester.getRect(_nav);
    expect(
      bar.bottom,
      moreOrLessEquals(nav.top, epsilon: 0.5),
      reason: 'a fixed bar rests on the bottom nav, got $bar over $nav',
    );
    expect(bar.left, moreOrLessEquals(0, epsilon: 0.5));
    expect(bar.right, moreOrLessEquals(_compact.width, epsilon: 0.5));
  });

  testWidgets('compact with bottom nav: an error bar floats above the bottom '
      'nav', (tester) async {
    await _pumpCompactHome(tester);

    await _showBar(tester, text: _error, isError: true);

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.behavior, SnackBarBehavior.floating);
    _expectBarAboveBottomNav(tester);
  });

  testWidgets('compact with bottom nav: a body-bottom action in the tab lifts '
      'the bar above both it and the bottom nav', (tester) async {
    await _pumpCompactHome(tester, bodyBottomAction: true);

    await _showBar(tester, text: _notice);

    expectSnackBarClearsButton(
      tester,
      message: _notice,
      button: find.byKey(_actionKey),
    );
    _expectBarAboveBottomNav(tester);
  });

  testWidgets('compact without bottom nav (a pushed detail): the bar sits '
      'flush with the screen bottom', (tester) async {
    await _pumpCompactHome(tester, showBottomNav: false);
    expect(_nav, findsNothing);

    await _showBar(tester, text: _notice);

    expectSnackBarAtDefaultPlacement(tester, message: _notice);
  });
}
