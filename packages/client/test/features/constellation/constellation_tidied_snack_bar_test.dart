import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tidied_snack_bar.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/undo_snack_bar.dart';

/// After «Tidy up» a snackbar says how many people moved and offers Undo.

void main() {
  Future<void> show(
    WidgetTester tester, {
    required int count,
    required VoidCallback onUndo,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showConstellationTidiedSnackBar(
                context,
                count: count,
                onUndo: onUndo,
              ),
              child: const Text('tidy'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('tidy'));
    await tester.pump();
  }

  group('tidied snackbar', () {
    testWidgets('names the number of people moved and offers Undo', (
      tester,
    ) async {
      await show(tester, count: 7, onUndo: () {});

      expect(
        find.widgetWithText(SnackBar, 'Tidied up: 7 people moved'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
    });

    testWidgets('Undo calls the undo callback once', (tester) async {
      var undone = 0;
      await show(tester, count: 3, onUndo: () => undone++);

      await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
      await tester.pump();

      expect(undone, 1);
    });

    testWidgets('is the shared Undo bar: long-lived and not pinned', (
      tester,
    ) async {
      await show(tester, count: 2, onUndo: () {});

      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.duration, kUndoSnackBarDuration);
      expect(bar.persist, isFalse);

      await tester.pump(kUndoSnackBarDuration + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('is shown in Russian with the count', (tester) async {
      await show(
        tester,
        count: 4,
        onUndo: () {},
        locale: const Locale('ru'),
      );

      expect(find.text('Причёсано: сдвинуто 4'), findsOneWidget);
    });
  });
}
