import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/help_type.dart';
import 'package:tentura/features/beacon_view/ui/dialog/commitment_message_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// Pumps a MaterialApp that shows CommitmentMessageDialog with
// showHelpTypeChips enabled and allowEmptyMessage so the submit button
// works without typing text.
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
            onPressed: () => CommitmentMessageDialog.show(
              context,
              title: 'Commit',
              hintText: 'Your message',
              showHelpTypeChips: true,
              allowEmptyMessage: true,
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
  testWidgets(
    'dialog renders a FilterChip for every CommitHelpType value',
    (tester) async {
      await _pumpDialog(tester);

      // Every CommitHelpType must have exactly one chip in the dialog.
      expect(
        find.byType(FilterChip),
        findsNWidgets(CommitHelpType.values.length),
      );
    },
  );

  testWidgets(
    'all chip labels match expected l10n strings',
    (tester) async {
      await _pumpDialog(tester);

      // A sample of the label-to-wireKey mapping verified via the dialog's
      // static _helpTypeLabel helper.  We check a few representative ones.
      expect(find.text('Money'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
    },
  );

  testWidgets(
    'no chip is selected by default',
    (tester) async {
      await _pumpDialog(tester);

      final chips = tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .toList();
      for (final chip in chips) {
        expect(chip.selected, isFalse);
      }
    },
  );

  testWidgets(
    'tapping a chip selects it and deselects it on second tap (toggle)',
    (tester) async {
      await _pumpDialog(tester);

      // Tap the "Money" chip.
      final moneyChipFinder = find.widgetWithText(FilterChip, 'Money');
      await tester.tap(moneyChipFinder);
      await tester.pumpAndSettle();

      expect(
        tester.widget<FilterChip>(moneyChipFinder).selected,
        isTrue,
      );

      // Tap again → deselect.
      await tester.tap(moneyChipFinder);
      await tester.pumpAndSettle();

      expect(
        tester.widget<FilterChip>(moneyChipFinder).selected,
        isFalse,
      );
    },
  );

  testWidgets(
    'selecting a chip and submitting passes the correct wireKey in the outcome',
    (tester) async {
      CommitmentDialogOutcome? outcome;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  outcome = await CommitmentMessageDialog.show(
                    context,
                    title: 'Commit',
                    hintText: 'Your message',
                    showHelpTypeChips: true,
                    allowEmptyMessage: true,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Select the "Time" chip.
      await tester.tap(find.widgetWithText(FilterChip, 'Time'));
      await tester.pumpAndSettle();

      // Confirm via the Ok button.
      await tester.tap(find.text('Ok'));
      await tester.pumpAndSettle();

      expect(outcome, isNotNull);
      expect(outcome!.helpTypeWire, equals(CommitHelpType.time.wireKey));
      expect(outcome!.helpTypeWire, equals('time'));
    },
  );

  testWidgets(
    'submitting without chip selection yields null helpTypeWire',
    (tester) async {
      CommitmentDialogOutcome? outcome;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  outcome = await CommitmentMessageDialog.show(
                    context,
                    title: 'Commit',
                    hintText: 'Your message',
                    showHelpTypeChips: true,
                    allowEmptyMessage: true,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Do NOT select any chip; just submit.
      await tester.tap(find.text('Ok'));
      await tester.pumpAndSettle();

      expect(outcome, isNotNull);
      expect(outcome!.helpTypeWire, isNull);
    },
  );

  testWidgets(
    'wireKey round-trip: every CommitHelpType.wireKey is non-empty and unique',
    (tester) async {
      final wireKeys =
          CommitHelpType.values.map((t) => t.wireKey).toList();

      // No empty keys.
      for (final key in wireKeys) {
        expect(key, isNotEmpty);
      }

      // All keys are distinct.
      expect(wireKeys.toSet().length, equals(CommitHelpType.values.length));
    },
  );

  testWidgets(
    'selecting physicalHelp chip submits wire key physical_help',
    (tester) async {
      CommitmentDialogOutcome? outcome;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  outcome = await CommitmentMessageDialog.show(
                    context,
                    title: 'Commit',
                    hintText: 'Your message',
                    showHelpTypeChips: true,
                    allowEmptyMessage: true,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilterChip, 'Physical help'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ok'));
      await tester.pumpAndSettle();

      expect(outcome!.helpTypeWire, equals('physical_help'));
    },
  );
}
