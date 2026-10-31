import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

// #436: in the Requirements picker the expanded chip rows were centred (the
// fold's children sit in a centre-aligned column) and selected chips took the
// group's own saturated tint (indigo for Logistics) instead of the app accent.

final _l10n = lookupL10n(const Locale('en'));

Finder _chip(CapabilityTag tag) =>
    find.byKey(TestIds.key(TestIds.capabilityChip(tag.slug)));

Future<void> _pumpChipSet(
  WidgetTester tester, {
  Set<String> initial = const {},
}) async {
  var selected = Set<String>.from(initial);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => CapabilityChipSet(
              selectedSlugs: selected,
              onChanged: (s) => setState(() => selected = s),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Groups start folded unless they hold a selected tag (#436); open
  // Logistics like the user in the report did.
  if (_chip(CapabilityTag.transport).evaluate().isEmpty) {
    await tester.tap(find.text(_l10n.capabilityGroupLogistics));
    await tester.pumpAndSettle();
  }
}

Widget _host({
  Set<String> selected = const {},
  Set<String> automatic = const {},
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  theme: TenturaTheme.light(),
  home: Scaffold(
    body: SingleChildScrollView(
      child: CapabilityChipSet(
        selectedSlugs: selected,
        automaticSlugs: automatic,
        onChanged: (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'expanded chips start at the left edge of the picker, not centred',
    (tester) async {
      // Wide enough that all Logistics chips fit in one run, so a centred run
      // sits far from the left edge.
      tester.view
        ..physicalSize = const Size(1600, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _pumpChipSet(tester);

      final firstChip = _chip(CapabilityTag.transport);
      expect(firstChip, findsOneWidget);
      final setLeft = tester.getTopLeft(find.byType(CapabilityChipSet)).dx;
      final setRight = tester.getTopRight(find.byType(CapabilityChipSet)).dx;
      final chipLeft = tester.getTopLeft(firstChip).dx;
      final lastChipRight = tester
          .getTopRight(
            _chip(CapabilityTag.physicalHelp),
          )
          .dx;
      final tt = tester.element(find.byType(CapabilityChipSet)).tt;

      // Vacuity guard: the run is much narrower than the picker, so centring
      // would show as a large left offset.
      expect(setRight - lastChipRight, greaterThan(tt.screenHPadding * 4));

      // Left-aligned: the first chip is at most a header inset from the edge.
      expect(chipLeft - setLeft, lessThanOrEqualTo(tt.screenHPadding));
    },
  );

  testWidgets('a selected chip uses the app primary accent', (tester) async {
    await _pumpChipSet(tester, initial: {CapabilityTag.transport.slug});

    final scheme = TenturaTheme.light().colorScheme;
    final swatch = TenturaCapabilityColors.light.logistics;
    // Vacuity guard: the group tint really differs from the accent.
    expect(swatch.onContainer, isNot(scheme.primary));

    final selected = tester.widget<FilterChip>(_chip(CapabilityTag.transport));
    expect(selected.selected, isTrue);
    expect(selected.selectedColor, scheme.primary);
    expect(selected.labelStyle?.color, scheme.onPrimary);
    expect((selected.avatar! as Icon).color, scheme.onPrimary);
  });

  testWidgets('unselected chips keep their group tint', (tester) async {
    // Guard: only the selection moves to the accent; idle chips still read as
    // their category.
    await _pumpChipSet(tester, initial: {CapabilityTag.transport.slug});

    final swatch = TenturaCapabilityColors.light.logistics;
    final idle = tester.widget<FilterChip>(_chip(CapabilityTag.storage));
    expect(idle.selected, isFalse);
    expect(idle.backgroundColor, swatch.container.withValues(alpha: 0.4));
    expect((idle.avatar! as Icon).color, swatch.onContainer);
    expect(idle.labelStyle?.color, swatch.onContainer);
  });

  group('#436 a group holding a choice starts open', () {
    testWidgets('a selected tag opens its group, and only that one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(selected: {CapabilityTag.tools.slug}),
      );
      await tester.pumpAndSettle();

      expect(_chip(CapabilityTag.tools), findsOneWidget);
      expect(
        tester.widget<FilterChip>(_chip(CapabilityTag.tools)).selected,
        isTrue,
      );
      // Accordion: the other groups stay folded.
      expect(_chip(CapabilityTag.money), findsNothing);
    });

    testWidgets('a pre-existing tag opens its group', (tester) async {
      await tester.pumpWidget(
        _host(automatic: {CapabilityTag.money.slug}),
      );
      await tester.pumpAndSettle();

      expect(_chip(CapabilityTag.money), findsOneWidget);
      expect(_chip(CapabilityTag.tools), findsNothing);
    });

    testWidgets('with nothing chosen only the first group is open (#741)', (
      tester,
    ) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(_chip(CapabilityTag.transport), findsOneWidget);
      expect(_chip(CapabilityTag.calls), findsNothing);
      expect(_chip(CapabilityTag.money), findsNothing);
    });
  });
}
