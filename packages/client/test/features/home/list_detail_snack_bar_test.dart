// #495: a profile opened from My people on a wide window is a list-detail
// route (HomeRailFrame > TenturaListDetailLayout): the people list and the
// profile are two sibling Scaffolds, both roots of the app messenger, so every
// notice was painted TWICE — once over the list column, once over the
// profile. Spec: one bar per notice, never over the rail.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

const _helpOffered = 'Help offered';
const _busy = 'Busy right now. Try again in a few seconds.';

Future<void> _pump(WidgetTester tester, {required Size size}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  GetIt.I.registerSingleton<Logger>(Logger('list-detail-snack-bar'));
  addTearDown(GetIt.I.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      scaffoldMessengerKey: snackbarKey,
      home: TenturaResponsiveScope(
        // The profile route's shape (profile_view_screen.dart).
        child: HomeRailFrame(
          selectedTab: HomeTab.network,
          child: TenturaListDetailLayout(
            list: const Scaffold(body: Text('people list')),
            detail: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    ElevatedButton(
                      onPressed: () =>
                          showSnackBar(context, text: _helpOffered),
                      child: const Text('notice'),
                    ),
                    ElevatedButton(
                      onPressed: () =>
                          showSnackBar(context, text: _busy, isError: true),
                      child: const Text('error'),
                    ),
                  ],
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

Future<void> _raise(WidgetTester tester, String button) async {
  await tester.tap(find.text(button));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 750));
}

/// The bar's own surface (outermost Material under the SnackBar); for a
/// floating bar the SnackBar widget itself also spans its margin.
Rect _barRect(WidgetTester tester) => tester.getRect(
  find
      .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
      .first,
);

void main() {
  for (final (label, button, message) in [
    ('notice bar', 'notice', _helpOffered),
    ('error bar', 'error', _busy),
  ]) {
    testWidgets('list beside profile: one $label, right of the rail', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1280, 1100));
      // Precondition: the wide split, both panes on screen.
      expect(find.text('people list'), findsOneWidget);
      expect(find.byKey(TenturaListDetailLayout.listPaneKey), findsOneWidget);

      await _raise(tester, button);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(message, findRichText: true), findsOneWidget);
      final rail = tester.getRect(find.byType(NavigationRail));
      final bar = _barRect(tester);
      expect(
        bar.left,
        greaterThanOrEqualTo(rail.right),
        reason: 'The bar must not be drawn over the rail ($rail): $bar',
      );
      expect(bar.bottom, greaterThan(1100 - 120));
    });
  }

  testWidgets('a second notice replaces the first: still one bar', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1280, 1100));

    await _raise(tester, 'notice');
    await _raise(tester, 'error');
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(_busy, findRichText: true), findsOneWidget);
    expect(find.text(_helpOffered, findRichText: true), findsNothing);
  });
}
