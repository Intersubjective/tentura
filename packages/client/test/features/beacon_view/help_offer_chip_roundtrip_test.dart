import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// Pumps a MaterialApp that shows HelpOfferMessageDialog with
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
            onPressed: () => HelpOfferMessageDialog.show(
              context,
              title: 'Offer Help',
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

Future<void> _expandAllCapabilityGroups(WidgetTester tester) async {
  for (final g in CapabilityGroup.values) {
    final tile = find.byKey(ValueKey<CapabilityGroup>(g));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'dialog renders a FilterChip for every CapabilityTag value',
    (tester) async {
      await _pumpDialog(tester);
      await _expandAllCapabilityGroups(tester);

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
      await _expandAllCapabilityGroups(tester);

      // A sample of representative labels.
      expect(find.widgetWithText(FilterChip, 'Money'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Orders'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Time'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Other'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Transport'), findsOneWidget);
    },
  );

  testWidgets(
    'no chip is selected by default',
    (tester) async {
      await _pumpDialog(tester);
      await _expandAllCapabilityGroups(tester);

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
      await _expandAllCapabilityGroups(tester);

      // Tap the "Money" chip.
      final moneyChipFinder = find.widgetWithText(FilterChip, 'Money');
      await tester.ensureVisible(moneyChipFinder);
      await tester.pumpAndSettle();
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
      HelpOfferDialogOutcome? outcome;

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
                  outcome = await HelpOfferMessageDialog.show(
                    context,
                    title: 'Offer Help',
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

      await tester.enterText(
        find.byKey(const Key('help-offer-search')),
        'time',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Time'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Offer help (1/4)'));
      await tester.pumpAndSettle();

      expect(outcome, isNotNull);
      expect(outcome!.helpTypesWire, equals(['time']));
    },
  );

  testWidgets(
    'submitting without chip selection yields null helpTypeWire',
    (tester) async {
      HelpOfferDialogOutcome? outcome;

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
                  outcome = await HelpOfferMessageDialog.show(
                    context,
                    title: 'Offer Help',
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
      await tester.tap(find.text('Offer help (0/4)'));
      await tester.pumpAndSettle();

      expect(outcome, isNotNull);
      expect(outcome!.helpTypesWire, isNull);
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
      HelpOfferDialogOutcome? outcome;

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
                  outcome = await HelpOfferMessageDialog.show(
                    context,
                    title: 'Offer Help',
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

      await tester.enterText(
        find.byKey(const Key('help-offer-search')),
        'physical help',
      );
      await tester.pumpAndSettle();
      final physicalHelpChip = find.widgetWithText(FilterChip, 'Physical help');
      await tester.tap(physicalHelpChip);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Offer help (1/4)'));
      await tester.pumpAndSettle();

      expect(outcome, isNotNull);
      expect(outcome!.helpTypesWire, equals(['physical_help']));
    },
  );

  testWidgets('search filters capabilities by tag label', (tester) async {
    await _pumpDialog(tester);

    await tester.enterText(
      find.byKey(const Key('help-offer-search')),
      'software',
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilterChip, 'Software'), findsOneWidget);
    expect(find.byKey(const ValueKey('technical:search')), findsOneWidget);
    expect(find.byKey(const ValueKey(CapabilityGroup.logistics)), findsNothing);
  });

  testWidgets('selection is capped at four capabilities', (tester) async {
    await _pumpDialog(tester);
    for (final label in [
      'Transport',
      'Storage',
      'Pickup / delivery',
      'Tools',
    ]) {
      await tester.enterText(
        find.byKey(const Key('help-offer-search')),
        label,
      );
      await tester.pumpAndSettle();
      final chip = find.widgetWithText(FilterChip, label);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    await tester.enterText(
      find.byKey(const Key('help-offer-search')),
      'Physical help',
    );
    await tester.pumpAndSettle();
    final fifth = find.widgetWithText(FilterChip, 'Physical help');
    await tester.ensureVisible(fifth);
    await tester.pumpAndSettle();

    expect(tester.widget<FilterChip>(fifth).selected, isFalse);
    expect(tester.widget<FilterChip>(fifth).onSelected, isNull);
    expect(find.text('Offer help (4/4)'), findsOneWidget);
  });
}
