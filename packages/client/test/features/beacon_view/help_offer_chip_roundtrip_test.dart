import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
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

const _capabilityGroupLabels = [
  'Logistics',
  'Communication',
  'Knowledge',
  'Care & support',
  'Resources',
  'Technical',
  'Help that does not fit another category',
];

Future<void> _expandCapabilityGroup(WidgetTester tester, String label) async {
  final tile = find.text(label);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _expandAllCapabilityGroups(WidgetTester tester) async {
  for (final label in _capabilityGroupLabels) {
    await _expandCapabilityGroup(tester, label);
  }
}

Future<int> _countChipsAcrossAllGroups(WidgetTester tester) async {
  var total = 0;
  for (final label in _capabilityGroupLabels) {
    await _expandCapabilityGroup(tester, label);
    total += tester.widgetList<FilterChip>(find.byType(FilterChip)).length;
  }
  return total;
}

void main() {
  testWidgets(
    'dialog renders a FilterChip for every CapabilityTag value',
    (tester) async {
      await _pumpDialog(tester);
      expect(
        await _countChipsAcrossAllGroups(tester),
        CapabilityTag.values.length,
      );
    },
  );

  testWidgets(
    'all chip labels match expected l10n strings',
    (tester) async {
      await _pumpDialog(tester);
      await _expandCapabilityGroup(tester, 'Resources');
      expect(find.widgetWithText(FilterChip, 'Money'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Time'), findsOneWidget);
      await _expandCapabilityGroup(tester, 'Logistics');
      expect(find.widgetWithText(FilterChip, 'Transport'), findsOneWidget);
      await _expandCapabilityGroup(
        tester,
        'Help that does not fit another category',
      );
      expect(find.widgetWithText(FilterChip, 'Orders'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Other'), findsOneWidget);
    },
  );

  testWidgets(
    'no chip is selected by default',
    (tester) async {
      await _pumpDialog(tester);
      await _expandCapabilityGroup(tester, 'Logistics');
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
      await _expandCapabilityGroup(tester, 'Resources');
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
    'submit button is disabled until at least one chip is selected',
    (tester) async {
      await _pumpDialog(tester);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Offer help (0/4)'),
      );
      expect(button.onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('help-offer-search')),
        'time',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Time'));
      await tester.pumpAndSettle();

      final enabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Offer help (1/4)'),
      );
      expect(enabled.onPressed, isNotNull);
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
    expect(
      find.text('Technology, repair, software, design, and admin'),
      findsOneWidget,
    );
    expect(find.text('Logistics'), findsNothing);
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
