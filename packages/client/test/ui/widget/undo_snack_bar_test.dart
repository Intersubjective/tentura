import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/undo_snack_bar.dart';

void main() {
  testWidgets('shows the text with an Undo action', (tester) async {
    await _pumpHost(
      tester,
      onShow: (context) =>
          showUndoSnackBar(context, text: 'Tag deleted', onUndo: () {}),
    );
    await _showAndSettleEntrance(tester);

    expect(find.text('Tag deleted'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
  });

  testWidgets('tapping Undo invokes the callback exactly once', (tester) async {
    var undone = 0;
    await _pumpHost(
      tester,
      onShow: (context) => showUndoSnackBar(
        context,
        text: 'Tag deleted',
        onUndo: () => undone++,
      ),
    );
    await _showAndSettleEntrance(tester);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pump();
    // A second tap while the bar animates out must not fire it again.
    await tester.tap(
      find.widgetWithText(SnackBarAction, 'Undo'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(undone, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('stays on screen for 10 s by default, then goes away', (
    tester,
  ) async {
    var undone = 0;
    await _pumpHost(
      tester,
      onShow: (context) => showUndoSnackBar(
        context,
        text: 'Tag deleted',
        onUndo: () => undone++,
      ),
    );
    await _showAndSettleEntrance(tester);

    // Still there just short of 10 s, well past the 5 s of an ordinary bar.
    await tester.pump(const Duration(milliseconds: 9900));
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(undone, 0, reason: 'letting the bar time out is not an Undo');
  });

  testWidgets('an explicit duration replaces the 10 s default', (tester) async {
    await _pumpHost(
      tester,
      onShow: (context) => showUndoSnackBar(
        context,
        text: 'Tag deleted',
        onUndo: () {},
        duration: const Duration(seconds: 3),
      ),
    );
    await _showAndSettleEntrance(tester);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });
}

/// Mounts a screen whose button raises a bar through the helper under test.
Future<void> _pumpHost(
  WidgetTester tester, {
  required void Function(BuildContext context) onShow,
}) => tester.pumpWidget(
  MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => onShow(context),
            child: const Text('Show'),
          ),
        ),
      ),
    ),
  ),
);

/// Taps Show and lets the entrance animation finish so the messenger arms
/// its timeout timer (it does so on the build after the bar is fully shown).
Future<void> _showAndSettleEntrance(WidgetTester tester) async {
  await tester.tap(find.text('Show'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  expect(find.byType(SnackBar), findsOneWidget);
}
