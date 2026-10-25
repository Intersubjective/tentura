// #720: on a recipients step with nobody picked, the disabled send button
// read «Select recipients», which looks like an action. It now keeps its
// action label («Send to 0») with a helper line «Select at least one
// recipient» beside it.
// #723: the send button sat inside a second «button» node (the wrapper that
// carries its e2e identifier), so the accessibility tree showed a Send button
// inside a Send button. One node now carries name, tap and identifier.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/forward/ui/widget/forward_bottom_composer.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/semantics_identifier.dart';

final _sendButton = find.byKey(TestIds.key(TestIds.forwardSubmit));

Future<void> _pump(
  WidgetTester tester, {
  required Set<String> selectedIds,
  VoidCallback? onForward,
  Locale locale = const Locale('en'),
}) async {
  final note = TextEditingController();
  addTearDown(note.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Align(
            alignment: Alignment.bottomCenter,
            child: ForwardBottomComposer(
              selectedIds: selectedIds,
              noteExpanded: false,
              onToggleNoteExpanded: () {},
              sharedNoteController: note,
              onSharedNoteChanged: (_) {},
              onForward: onForward,
              sendLabel: L10n.of(context)!.postCreateSendToCount,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Every semantics node in the tree.
List<SemanticsNode> _allNodes() =>
    find.semantics.byPredicate((_) => true).evaluate().toList();

bool _isButton(SemanticsNode node) =>
    node.getSemanticsData().flagsCollection.isButton;

void main() {
  testWidgets('nobody picked: Send to 0, disabled, with a helper line', (
    tester,
  ) async {
    await _pump(tester, selectedIds: const {});

    expect(
      find.descendant(of: _sendButton, matching: find.text('Send to 0')),
      findsOneWidget,
    );
    expect(tester.widget<OutlinedButton>(_sendButton).onPressed, isNull);
    expect(find.text('Select at least one recipient'), findsOneWidget);
    expect(
      find.descendant(
        of: _sendButton,
        matching: find.text('Select at least one recipient'),
      ),
      findsNothing,
    );
  });

  testWidgets('ru: nobody picked: Otpravit (0) and the helper line', (
    tester,
  ) async {
    await _pump(tester, selectedIds: const {}, locale: const Locale('ru'));

    expect(
      find.descendant(of: _sendButton, matching: find.text('Отправить (0)')),
      findsOneWidget,
    );
    expect(find.text('Выберите хотя бы одного получателя'), findsOneWidget);
  });

  testWidgets('someone picked: no helper line', (tester) async {
    var sent = 0;
    await _pump(tester, selectedIds: const {'u1'}, onForward: () => sent++);

    expect(find.text('Select at least one recipient'), findsNothing);
    await tester.tap(_sendButton);
    expect(sent, 1);
  });

  testWidgets('the send button is one semantics node with its identifier', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var sent = 0;
    await _pump(tester, selectedIds: const {'u1'}, onForward: () => sent++);

    final withId = _allNodes()
        .where((n) => n.getSemanticsData().identifier == TestIds.forwardSubmit)
        .toList();
    expect(withId, hasLength(1));
    final node = withId.single;
    expect(
      node,
      allOf(
        isSemantics(label: 'Send to 1', isButton: true, hasTapAction: true),
        hasSemanticsIdentifier(TestIds.forwardSubmit),
      ),
    );
    final nested = <SemanticsNode>[];
    bool collect(SemanticsNode n) {
      if (_isButton(n)) nested.add(n);
      n.visitChildren(collect);
      return true;
    }

    node.visitChildren(collect);
    expect(nested, isEmpty, reason: 'no button inside the send button');
    expect(_allNodes().where(_isButton), hasLength(1));

    tester.semantics.tap(find.semantics.byLabel('Send to 1'));
    await tester.pump();
    expect(sent, 1);
    handle.dispose();
  });
}
