import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/capability/offer_help_classification.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/capability/ui/widget/capability_tag_chip.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

Future<void> _pumpDialog(
  WidgetTester tester, {
  Set<String> automaticSlugs = const {},
  bool allowEmptyMessage = false,
}) async {
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
              hintText: 'How will you help?',
              showHelpTypeChips: true,
              allowEmptyMessage: allowEmptyMessage,
              automaticSlugs: automaticSlugs,
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

Future<void> _openBrowse(WidgetTester tester) async {
  await tester.tap(find.text('Browse all categories'));
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

Future<int> _countChipsAcrossAllGroups(WidgetTester tester) async {
  var total = 0;
  final chipSet = find.byType(CapabilityChipSet);
  for (final label in _capabilityGroupLabels) {
    await _expandCapabilityGroup(tester, label);
    total += tester
        .widgetList<FilterChip>(
          find.descendant(
            of: chipSet,
            matching: find.byType(FilterChip),
          ),
        )
        .length;
  }
  return total;
}

void main() {
  testWidgets(
    'text-only submit succeeds without selecting chips',
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
                    hintText: 'How will you help?',
                    showHelpTypeChips: true,
                    allowEmptyMessage: false,
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

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Offer help'),
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(TestIds.key(TestIds.helpOfferMessage)),
        'I can help with the costume',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Offer help'));
      await tester.pumpAndSettle();

      expect(outcome, isNotNull);
      expect(outcome!.message, 'I can help with the costume');
      expect(outcome!.helpTypesWire, isNull);
      expect(
        outcome!.classificationPath,
        OfferHelpClassificationPath.textOnly,
      );
    },
  );

  testWidgets(
    'submit is disabled on empty message when offering',
    (tester) async {
      await _pumpDialog(tester);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Offer help'),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'automaticSlugs do not show chips until browse is opened',
    (tester) async {
      await _pumpDialog(
        tester,
        automaticSlugs: {CapabilityTag.transport.slug},
      );
      expect(find.widgetWithText(FilterChip, 'Transport'), findsNothing);
      expect(find.byType(CapabilityTagIconChip), findsNothing);
      expect(find.byKey(TestIds.key(TestIds.helpOfferSearch)), findsNothing);

      await _openBrowse(tester);
      await tester.enterText(
        find.byKey(TestIds.key(TestIds.helpOfferSearch)),
        'transport',
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'Transport'), findsOneWidget);
    },
  );

  testWidgets(
    'selected chips appear as icon chips in browse row when collapsed',
    (tester) async {
      await _pumpDialog(tester, allowEmptyMessage: true);
      await _openBrowse(tester);
      await tester.enterText(
        find.byKey(TestIds.key(TestIds.helpOfferSearch)),
        'time',
      );
      await tester.pumpAndSettle();
      final timeChipKey = TestIds.key(TestIds.capabilityChip('time'));
      final timeInBrowser = find.descendant(
        of: find.byType(CapabilityChipSet),
        matching: find.byKey(timeChipKey),
      );
      await tester.ensureVisible(timeInBrowser);
      await tester.pumpAndSettle();
      await tester.tap(timeInBrowser);
      await tester.pumpAndSettle();

      expect(tester.widget<FilterChip>(timeInBrowser).selected, isTrue);
      expect(find.byType(CapabilityTagIconChip), findsOneWidget);

      // Collapse browse — icon chip stays in the browse row.
      await tester.tap(find.text('Hide categories'));
      await tester.pumpAndSettle();

      expect(find.byType(CapabilityChipSet), findsNothing);
      expect(find.byType(CapabilityTagIconChip), findsOneWidget);
      expect(find.text('1'), findsNothing);
    },
  );

  testWidgets(
    'browse reveals full taxonomy and search',
    (tester) async {
      await _pumpDialog(tester);
      await _openBrowse(tester);
      expect(find.byKey(TestIds.key(TestIds.helpOfferSearch)), findsOneWidget);
      expect(
        await _countChipsAcrossAllGroups(tester),
        CapabilityTag.values.length,
      );
    },
  );

  testWidgets(
    'selecting a chip via browse and submitting passes wire keys',
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
                    hintText: 'How will you help?',
                    showHelpTypeChips: true,
                    allowEmptyMessage: false,
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
        find.byKey(TestIds.key(TestIds.helpOfferMessage)),
        'I have time',
      );
      await tester.pumpAndSettle();

      await _openBrowse(tester);
      await tester.enterText(
        find.byKey(TestIds.key(TestIds.helpOfferSearch)),
        'time',
      );
      await tester.pumpAndSettle();
      final timeChip = find.descendant(
        of: find.byType(CapabilityChipSet),
        matching: find.widgetWithText(FilterChip, 'Time'),
      );
      await tester.ensureVisible(timeChip);
      await tester.pumpAndSettle();
      await tester.tap(timeChip);
      await tester.pumpAndSettle();

      final submit = find.byKey(TestIds.key(TestIds.helpOfferSubmit));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(outcome, isNotNull);
      expect(outcome!.helpTypesWire, equals(['time']));
      expect(
        outcome!.classificationPath,
        OfferHelpClassificationPath.fullBrowser,
      );
    },
  );

  testWidgets(
    'preselected suggested slug without browse is suggestedChip path',
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
                    hintText: 'How will you help?',
                    showHelpTypeChips: true,
                    allowEmptyMessage: false,
                    automaticSlugs: {CapabilityTag.money.slug},
                    initialHelpTypeSlugs: {CapabilityTag.money.slug},
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
        find.byKey(TestIds.key(TestIds.helpOfferMessage)),
        'I can contribute money',
      );
      await tester.pumpAndSettle();

      expect(find.byType(CapabilityTagIconChip), findsOneWidget);

      await tester.tap(find.text('Offer help'));
      await tester.pumpAndSettle();

      expect(outcome!.helpTypesWire, equals(['money']));
      expect(
        outcome!.classificationPath,
        OfferHelpClassificationPath.suggestedChip,
      );
    },
  );

  testWidgets(
    'slug round-trip: every CapabilityTag.slug is non-empty and unique',
    (tester) async {
      final slugs = CapabilityTag.values.map((t) => t.slug).toList();
      for (final slug in slugs) {
        expect(slug, isNotEmpty);
      }
      expect(slugs.toSet().length, equals(CapabilityTag.values.length));
      expect(CapabilityTag.fromSlug('manual_work'), CapabilityTag.manualWork);
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
                    hintText: 'How will you help?',
                    showHelpTypeChips: true,
                    allowEmptyMessage: false,
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
        find.byKey(TestIds.key(TestIds.helpOfferMessage)),
        'I can carry things',
      );
      await tester.pumpAndSettle();

      await _openBrowse(tester);
      await tester.enterText(
        find.byKey(TestIds.key(TestIds.helpOfferSearch)),
        'physical help',
      );
      await tester.pumpAndSettle();
      final physicalHelpChip = find.descendant(
        of: find.byType(CapabilityChipSet),
        matching: find.widgetWithText(FilterChip, 'Physical help'),
      );
      await tester.ensureVisible(physicalHelpChip);
      await tester.pumpAndSettle();
      await tester.tap(physicalHelpChip);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(TestIds.key(TestIds.helpOfferSubmit)));
      await tester.pumpAndSettle();

      expect(outcome!.helpTypesWire, equals(['physical_help']));
    },
  );

  testWidgets('search filters capabilities by tag label', (tester) async {
    await _pumpDialog(tester);
    await _openBrowse(tester);

    await tester.enterText(
      find.byKey(TestIds.key(TestIds.helpOfferSearch)),
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
    await _pumpDialog(tester, allowEmptyMessage: true);
    await _openBrowse(tester);
    for (final label in [
      'Transport',
      'Storage',
      'Pickup / delivery',
      'Tools',
    ]) {
      await tester.enterText(
        find.byKey(TestIds.key(TestIds.helpOfferSearch)),
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
      find.byKey(TestIds.key(TestIds.helpOfferSearch)),
      'Physical help',
    );
    await tester.pumpAndSettle();
    final fifth = find.widgetWithText(FilterChip, 'Physical help');
    await tester.ensureVisible(fifth);
    await tester.pumpAndSettle();

    expect(tester.widget<FilterChip>(fifth).selected, isFalse);
    expect(tester.widget<FilterChip>(fifth).onSelected, isNull);
  });

  testWidgets('Manual work chip is available under Technical', (tester) async {
    await _pumpDialog(tester);
    await _openBrowse(tester);
    await tester.enterText(
      find.byKey(TestIds.key(TestIds.helpOfferSearch)),
      'manual',
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'Manual work'), findsOneWidget);
  });
}
