// #447 (residual): the step sheet's title and details fields must reach
// assistive tech as labelled text fields, each with a stable identifier
// (`flt-semantics-identifier` on the web) on that same node.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_step_edit_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

const _people = [Profile(id: 'ME', displayName: 'Ivan')];

Future<void> _pump(
  WidgetTester tester, {
  required Locale locale,
  required PlanStepSnapshot step,
  bool isNew = false,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: PlanStepEditSheet(step: step, people: _people, isNew: isNew),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The one semantics node that carries [identifier].
SemanticsNode _nodeById(String identifier) {
  final found = find.semantics
      .byPredicate((node) => node.identifier == identifier)
      .evaluate();
  expect(found, hasLength(1), reason: 'one node with identifier $identifier');
  return found.single;
}

/// On web a button or text-field node hides everything inside it, so no
/// ancestor of a field may be one.
void _expectNoButtonOrFieldAncestor(SemanticsNode node, String what) {
  for (var p = node.parent; p != null; p = p.parent) {
    final flags = p.getSemanticsData().flagsCollection;
    expect(
      flags.isButton || flags.isTextField,
      isFalse,
      reason: '$what sits inside a button/text-field node "${p.label}"',
    );
  }
}

void _expectNamedTextField(String identifier, String label) {
  final node = _nodeById(identifier);
  expect(
    node.label,
    contains(label),
    reason: 'the $identifier node is the field and carries its label',
  );
  expect(
    node,
    isSemantics(isTextField: true, isFocusable: true, hasTapAction: true),
  );
  _expectNoButtonOrFieldAncestor(node, identifier);
}

Iterable<SemanticsNode> _unnamedTextFields() => find.semantics
    .byPredicate(
      (node) =>
          node.getSemanticsData().flagsCollection.isTextField &&
          node.label.isEmpty,
    )
    .evaluate();

void main() {
  for (final locale in const [Locale('en'), Locale('ru')]) {
    final l10n = lookupL10n(locale);

    testWidgets('new step: title and details are labelled text fields '
        '(${locale.languageCode})', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        locale: locale,
        step: const PlanStepSnapshot(id: 'N', title: ''),
        isNew: true,
      );

      _expectNamedTextField(TestIds.planStepTitle, l10n.planFieldTitle);
      _expectNamedTextField(
        TestIds.planStepDescription,
        l10n.planFieldDescription,
      );
      expect(_unnamedTextFields(), isEmpty);
      handle.dispose();
    });

    testWidgets('filled step: fields stay labelled and each clear x names '
        'its time (${locale.languageCode})', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        locale: locale,
        step: PlanStepSnapshot(
          id: 'A',
          title: 'Buy bread',
          description: 'Rye, two loaves',
          startAt: DateTime.utc(2026, 10, 12, 9),
          endAt: DateTime.utc(2026, 10, 12, 10),
        ),
      );

      _expectNamedTextField(TestIds.planStepTitle, l10n.planFieldTitle);
      _expectNamedTextField(
        TestIds.planStepDescription,
        l10n.planFieldDescription,
      );
      expect(_unnamedTextFields(), isEmpty);
      // Guard for the half of #447 fixed earlier: both x buttons are named
      // after the time they clear, not «No time».
      expect(
        find.byTooltip(l10n.planFieldClearTimeOf(l10n.planFieldStart)),
        findsOneWidget,
      );
      expect(
        find.byTooltip(l10n.planFieldClearTimeOf(l10n.planFieldEnd)),
        findsOneWidget,
      );
      expect(find.byTooltip(l10n.planFieldClearTime), findsNothing);
      handle.dispose();
    });
  }
}
