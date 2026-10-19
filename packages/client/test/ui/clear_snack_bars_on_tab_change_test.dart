// #470: a bar raised on one Home tab followed the user to the next tab,
// because ClearSnackBarsOnPushObserver only reacts to `didPush` and a Home tab
// switch (AutoTabsRouter.setActiveIndex) pushes no route. AutoTabsRouter
// reports tab switches to inherited AutoRouterObservers: `didChangeTabRoute`
// for a tab visited before, `didInitTabRoute` with a previous tab for the
// first visit to a lazy tab.
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

final class _FakeRouteMatch extends Fake implements RouteMatch<Object?> {}

TabPageRoute _tab(int index) =>
    TabPageRoute(routeInfo: _FakeRouteMatch(), index: index);

/// The observer as the app registers it (root `navigatorObservers`, inherited
/// by the Home AutoTabsRouter).
NavigatorObserver _appObserver() => ClearSnackBarsOnPushObserver();

void main() {
  testWidgets('switching to a visited Home tab clears the visible bar', (
    tester,
  ) async {
    await _showBar(tester);
    final observer = _appObserver();
    expect(observer, isA<AutoRouterObserver>());

    (observer as AutoRouterObserver).didChangeTabRoute(_tab(1), _tab(4));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('first visit to a lazy Home tab clears the visible bar', (
    tester,
  ) async {
    await _showBar(tester);
    final observer = _appObserver();
    expect(observer, isA<AutoRouterObserver>());

    (observer as AutoRouterObserver).didInitTabRoute(_tab(1), _tab(4));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('initial Home tab setup does not clear the visible bar', (
    tester,
  ) async {
    // Same rule as didPush with no previous route: mounting Home is not a
    // move away from the screen that raised the bar.
    await _showBar(tester);
    final observer = _appObserver();
    expect(observer, isA<AutoRouterObserver>());

    (observer as AutoRouterObserver).didInitTabRoute(_tab(0), null);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
  });
}

/// Raises a bar on the app-wide messenger ([snackbarKey]), the one the
/// observer clears, and waits until it is fully on screen.
Future<void> _showBar(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      scaffoldMessengerKey: snackbarKey,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSnackBar(
                context,
                text: 'Invite saved — find it in the Invitations tab',
                action: SnackBarAction(
                  label: 'View invitations',
                  onPressed: () {},
                ),
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Show'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  expect(find.byType(SnackBar), findsOneWidget);
}
