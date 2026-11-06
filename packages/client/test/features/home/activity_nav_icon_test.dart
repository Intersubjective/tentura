// #1065: Activity (HomeTab.inbox) must not use Material «inbox tray» glyphs —
// user-facing vocabulary is Activity; bell/notification icons match updates.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/ui/widget/home_bottom_navigation_bar.dart';
import 'package:tentura/features/home/ui/widget/home_nav_destinations.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));
  final activityIndex = HomeTabSpec.forTab(HomeTab.inbox).index;

  Future<void> pumpBar(WidgetTester tester, {required int? selectedIndex}) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: HomeBottomNavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (_) {},
              destinations: [
                for (final d in homeNavDestinations(l10n, badged: false))
                  HomeNavDestination(
                    icon: d.icon,
                    selectedIcon: d.selectedIcon,
                    label: d.label,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('375×667 Activity selected: notifications filled, no inbox glyph', (
    tester,
  ) async {
    await pumpBar(tester, selectedIndex: activityIndex);
    expect(find.byIcon(Icons.notifications), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsNothing);
    expect(find.byIcon(Icons.inbox), findsNothing);
    expect(find.byIcon(Icons.inbox_outlined), findsNothing);
  });

  testWidgets('375×667 Activity unselected: notifications outlined', (
    tester,
  ) async {
    await pumpBar(tester, selectedIndex: 0);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications), findsNothing);
    expect(find.byIcon(Icons.inbox), findsNothing);
    expect(find.byIcon(Icons.inbox_outlined), findsNothing);
  });
}
