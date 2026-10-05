// Home's rail beside root routes: five destinations from the shared list, and
// the account avatar at the rail's foot instead of a Profile destination.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/ui/widget/home_rail_account_footer.dart';
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Future<void> _pump(
  WidgetTester tester, {
  required HomeTab selectedTab,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: HomeRailFrame(
          selectedTab: selectedTab,
          child: const Scaffold(body: Text('route')),
        ),
      ),
    ),
  );
}

NavigationRail _rail(WidgetTester tester) =>
    tester.widget<NavigationRail>(find.byType(NavigationRail));

HomeRailAccountFooter _avatar(WidgetTester tester) =>
    tester.widget<HomeRailAccountFooter>(find.byType(HomeRailAccountFooter));

void main() {
  testWidgets('rail: Work, Conversations, Activity, Field, People', (
    tester,
  ) async {
    await _pump(tester, selectedTab: HomeTab.conversations);

    expect(
      [
        for (final d in _rail(tester).destinations) ((d.label as Text).data),
      ],
      ['Work', 'Posts', 'Activity', 'Field', 'People'],
    );
    expect(_rail(tester).selectedIndex, 1);
    expect(_avatar(tester).selected, isFalse);
  });

  testWidgets('the avatar sits at the rail foot, below every destination', (
    tester,
  ) async {
    await _pump(tester, selectedTab: HomeTab.work);

    final avatar = tester.getRect(find.byType(HomeRailAccountFooter));
    final people = tester.getRect(find.text('People'));
    expect(avatar.top, greaterThan(people.bottom));
    expect(avatar.bottom, greaterThan(800 - 100));
  });

  testWidgets('extended rail: a divider, then the avatar with a label', (
    tester,
  ) async {
    await _pump(tester, selectedTab: HomeTab.work);

    final footer = find.byType(HomeRailAccountFooter);
    expect(_avatar(tester).extended, isTrue);
    expect(
      find.descendant(of: footer, matching: find.byType(Divider)),
      findsOneWidget,
    );
    // No profile loaded in this harness: the label falls back to «Profile».
    expect(
      find.descendant(of: footer, matching: find.text('Profile')),
      findsOneWidget,
    );
    // The label starts where the destinations' labels do.
    expect(
      tester
          .getTopLeft(
            find.descendant(of: footer, matching: find.text('Profile')),
          )
          .dx,
      closeTo(tester.getTopLeft(find.text('People')).dx, 1),
    );
  });

  testWidgets('collapsed rail: the label sits under the avatar', (
    tester,
  ) async {
    await _pump(tester, selectedTab: HomeTab.work, size: const Size(760, 800));

    expect(_avatar(tester).extended, isFalse);
    final footer = find.byType(HomeRailAccountFooter);
    final label = tester.getRect(
      find.descendant(of: footer, matching: find.text('Profile')),
    );
    final glyph = tester.getRect(
      find.descendant(of: footer, matching: find.byType(Icon)),
    );
    expect(label.top, greaterThan(glyph.bottom));
    expect(label.center.dx, closeTo(glyph.center.dx, 1));
  });

  testWidgets('on a profile route no destination is selected; the avatar is', (
    tester,
  ) async {
    await _pump(tester, selectedTab: HomeTab.me);

    expect(_rail(tester).selectedIndex, isNull);
    expect(_avatar(tester).selected, isTrue);
  });

  testWidgets('compact windows get no rail', (tester) async {
    await _pump(tester, selectedTab: HomeTab.work, size: const Size(390, 800));

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('route'), findsOneWidget);
  });
}
