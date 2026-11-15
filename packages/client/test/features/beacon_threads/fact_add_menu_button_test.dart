// The shared «Add fact» menu button (M3 MenuAnchor): tapping an item runs
// only its own action, once, and closes the menu.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_add_menu_button.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

final _newItem = find.byKey(TestIds.key('beacon.facts.add.new'));
final _pickItem = find.byKey(TestIds.key('beacon.facts.add.pick'));

void main() {
  late int newFact;
  late int pick;

  Future<void> pumpButton(WidgetTester tester) async {
    newFact = 0;
    pick = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: Center(
              child: FactAddMenuButton(
                onNewFact: () => newFact++,
                onPickFromAvailable: () => pick++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(TestIds.key(TestIds.beaconFactsAdd)));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping New fact runs only the new-fact action once and '
      'closes the menu', (tester) async {
    await pumpButton(tester);
    expect(find.byType(MenuItemButton), findsNWidgets(2));

    await tester.tap(_newItem);
    await tester.pumpAndSettle();

    expect((newFact, pick), (1, 0));
    expect(find.byType(MenuItemButton), findsNothing);
  });

  testWidgets('tapping Pick from available runs only the pick action once '
      'and closes the menu', (tester) async {
    await pumpButton(tester);

    await tester.tap(_pickItem);
    await tester.pumpAndSettle();

    expect((newFact, pick), (0, 1));
    expect(find.byType(MenuItemButton), findsNothing);
  });
}
