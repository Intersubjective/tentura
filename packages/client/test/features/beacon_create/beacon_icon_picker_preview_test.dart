import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_icon_picker_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

Widget _pickerHarness() {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    theme: TenturaTheme.light(),
    home: const Scaffold(
      body: BeaconIconPickerScreen(),
    ),
  );
}

void main() {
  testWidgets('hover previews symbol label in app bar before selection', (
    tester,
  ) async {
    await tester.pumpWidget(_pickerHarness());
    await tester.pumpAndSettle();

    expect(find.text('Request symbol'), findsOneWidget);
    expect(find.text('Announcement'), findsWidgets);

    final announcementTile = find.ancestor(
      of: find.text('Announcement'),
      matching: find.byType(InkWell),
    );
    final center = tester.getCenter(announcementTile.first);

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: center);
    await gesture.moveTo(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Announcement'), findsWidgets);
    expect(find.byType(BeaconIdentityTile), findsOneWidget);
    expect(find.text('Request symbol'), findsNothing);
  });

  testWidgets('search query filters visible symbols', (tester) async {
    await tester.pumpWidget(_pickerHarness());
    await tester.pumpAndSettle();

    expect(find.text('Announcement'), findsWidgets);
    expect(find.text('Discussion'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'announcement');
    await tester.pump();

    expect(find.text('Announcement'), findsWidgets);
    expect(find.text('Discussion'), findsNothing);
  });

  testWidgets('category chip filters visible symbols', (tester) async {
    await tester.pumpWidget(_pickerHarness());
    await tester.pumpAndSettle();

    expect(find.text('Announcement'), findsWidgets);

    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();

    expect(find.text('Announcement'), findsNothing);
    expect(find.text('Accessibility'), findsWidgets);
  });

  testWidgets('tap selects symbol on touch devices', (tester) async {
    await tester.pumpWidget(_pickerHarness());
    await tester.pumpAndSettle();

    final announcementTile = find.ancestor(
      of: find.text('Announcement'),
      matching: find.byType(InkWell),
    );
    expect(announcementTile, findsOneWidget);

    final center = tester.getCenter(announcementTile);
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Request symbol'), findsNothing);
    expect(find.text('Announcement'), findsWidgets);
  });

  testWidgets('long-press does not block tap selection on touch devices', (
    tester,
  ) async {
    await tester.pumpWidget(_pickerHarness());
    await tester.pumpAndSettle();

    final announcementTile = find.ancestor(
      of: find.text('Announcement'),
      matching: find.byType(InkWell),
    );
    final center = tester.getCenter(announcementTile.first);

    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Request symbol'), findsNothing);
    expect(find.text('Announcement'), findsWidgets);
  });
}
