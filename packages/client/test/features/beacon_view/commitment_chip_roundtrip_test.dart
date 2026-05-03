import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
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
    'dialog renders a FilterChip for every CapabilityTag value',
    (tester) async {
      await _pumpDialog(tester);

      // Every CapabilityTag must have exactly one chip in the dialog.
      expect(
        find.byType(FilterChip),
        findsNWidgets(CapabilityTag.values.length),
      );
    },
  );

  testWidgets(
    'all chip labels match expected l10n strings',
    (tester) async {
      await _pumpDialog(tester);

      // A sample of representative labels.
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
    'slug round-trip: every CapabilityTag.slug is non-empty and unique',
    (tester) async {
      final slugs = CapabilityTag.values.map((t) => t.slug).toList();

      // No empty slugs.
      for (final slug in slugs) {
        expect(slug, isNotEmpty);
      }

      // All slugs are distinct.
      expect(slugs.toSet().length, equals(CapabilityTag.values.length));
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

      final physicalHelpChip = find.widgetWithText(FilterChip, 'Physical help');
      // TextField autofocus scrolls content to the field; early chips can sit
      // above the viewport until we explicitly scroll them into view.
      await tester.ensureVisible(physicalHelpChip);
      await tester.pumpAndSettle();
      await tester.tap(physicalHelpChip);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ok'));
      await tester.pumpAndSettle();

      expect(outcome, isNotNull);
      expect(outcome!.helpTypeWire, equals('physical_help'));
    },
  );
}
