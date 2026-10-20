import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';

const _hint = 'How will you help?';

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
              hintText: _hint,
              showHelpTypeChips: true,
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

L10n _l10n(WidgetTester tester) =>
    L10n.of(tester.element(find.byType(HelpOfferMessageDialog)))!;

/// The one semantics node that carries [identifier].
SemanticsNode _nodeById(String identifier) {
  final found = find.semantics
      .byPredicate((node) => node.identifier == identifier)
      .evaluate();
  expect(found, hasLength(1), reason: 'one node with identifier $identifier');
  return found.single;
}

/// Text-field nodes that a screen reader would announce without a name.
Iterable<SemanticsNode> _unnamedTextFields() => find.semantics
    .byPredicate(
      (node) =>
          node.getSemanticsData().flagsCollection.isTextField &&
          node.label.isEmpty,
    )
    .evaluate();

/// Button nodes that a screen reader would announce without a name.
Iterable<SemanticsNode> _unnamedButtons() => find.semantics
    .byPredicate(
      (node) =>
          node.getSemanticsData().flagsCollection.isButton &&
          node.label.isEmpty &&
          node.tooltip.isEmpty,
    )
    .evaluate();

/// On web a `button` (or text-field) node hides everything inside it from
/// assistive tech, so no ancestor of a control may be one.
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

/// #360 (residual of B024) — on the helper side, the "Offer help" sheet's
/// text field and categories must be present in the semantics tree as
/// labelled controls, not hidden behind an unnamed wrapper node.
void main() {
  testWidgets('message field is one labelled text field', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpDialog(tester);

    _expectNamedTextField(TestIds.helpOfferMessage, _hint);
    expect(_unnamedTextFields(), isEmpty);
    handle.dispose();
  });

  testWidgets('Browse categories and Submit are named buttons', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpDialog(tester);
    final l10n = _l10n(tester);

    // Submit starts disabled (empty message), so it is not focusable yet.
    final focusable = {
      l10n.helpOfferBrowseCategories: true,
      l10n.buttonCancel: true,
      l10n.helpOfferSubmitAction: false,
    };
    for (final MapEntry(key: label, value: isFocusable) in focusable.entries) {
      expect(
        find.semantics.byLabel(label),
        findsOne,
        reason: '$label should be one semantics node',
      );
      expect(
        find.semantics.byLabel(label).evaluate().single,
        isFocusable
            ? isSemantics(isButton: true, isFocusable: true)
            : isSemantics(isButton: true),
        reason: '$label should be a button',
      );
    }
    expect(_unnamedButtons(), isEmpty);

    // The (i) hint next to the categories is its own named button.
    final hint = find.semantics.byLabel(l10n.helpOfferOptionalEnrichmentLabel);
    expect(hint, findsOne);
    expect(
      hint.evaluate().single,
      isSemantics(isButton: true, isFocusable: true, hasTapAction: true),
    );
    handle.dispose();
  });

  testWidgets('search field and category chips are labelled and tappable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpDialog(tester);
    final l10n = _l10n(tester);

    tester.semantics.tap(
      find.semantics.byLabel(l10n.helpOfferBrowseCategories),
    );
    await tester.pumpAndSettle();

    _expectNamedTextField(TestIds.helpOfferSearch, l10n.helpOfferSearchLabel);
    expect(_unnamedTextFields(), isEmpty);

    // Expand one category group and check its chips.
    final groupLabel = l10n.capabilityGroupLogistics;
    await tester.ensureVisible(find.text(groupLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(groupLabel));
    await tester.pumpAndSettle();

    final tag = CapabilityTag.values.firstWhere(
      (t) => t.group == CapabilityGroup.logistics,
    );
    final chipLabel = '${tag.labelOf(l10n)}, $groupLabel';
    await tester.ensureVisible(
      find.byKey(TestIds.key(TestIds.capabilityChip(tag.slug))),
    );
    await tester.pumpAndSettle();
    expect(
      find.semantics.byLabel(chipLabel),
      findsOne,
      reason: 'the chip is one node named with its category',
    );
    expect(
      find.semantics.byLabel(chipLabel).evaluate().single,
      isSemantics(
        label: chipLabel,
        isButton: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );
    expect(
      _nodeById(TestIds.capabilityChip(tag.slug)).label,
      chipLabel,
      reason: 'the e2e identifier stays on the named chip node',
    );
    _expectNoButtonOrFieldAncestor(
      find.semantics.byLabel(chipLabel).evaluate().single,
      chipLabel,
    );
    expect(_unnamedButtons(), isEmpty);

    // Selecting through semantics works and is reflected on the same node.
    tester.semantics.tap(find.semantics.byLabel(chipLabel));
    await tester.pumpAndSettle();
    expect(
      find.semantics.byLabel(chipLabel).evaluate().single,
      isSemantics(hasSelectedState: true, isSelected: true),
    );
    handle.dispose();
  });
}
