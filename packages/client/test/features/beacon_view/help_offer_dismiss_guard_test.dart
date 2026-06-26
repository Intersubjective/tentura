import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// Pumps a MaterialApp that shows HelpOfferMessageDialog with a free-text
// message field so we can exercise the unsaved-changes dismiss guard.
Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => HelpOfferMessageDialog.show(
              context,
              title: 'Offer Help',
              hintText: 'Your message',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Cancel with no input closes immediately (no confirm)', (
    tester,
  ) async {
    await _pumpDialog(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(HelpOfferMessageDialog), findsNothing);
  });

  testWidgets(
    'Cancel with unsaved text prompts to discard and can keep editing',
    (
      tester,
    ) async {
      await _pumpDialog(tester);

      await tester.enterText(find.byType(TextField).last, 'I can help');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Confirm dialog appears; original dialog still mounted underneath.
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('Keep editing'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(HelpOfferMessageDialog), findsOneWidget);
      expect(find.text('I can help'), findsOneWidget);
    },
  );

  testWidgets('Discard confirms away unsaved input', (tester) async {
    await _pumpDialog(tester);

    await tester.enterText(find.byType(TextField).last, 'I can help');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.byType(HelpOfferMessageDialog), findsNothing);
  });
}
