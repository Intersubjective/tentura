// #415 in the Forward footer (#784 review): the Forward Send button's
// semantics were one node (#723) but that node never said it had focus, so
// on the web Tab onto Send left the browser focus on the previous control.
// A Tab walk through the footer must find a focused node at every stop,
// Send included. #720: the disabled Send also tells a screen reader why.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/forward/ui/widget/forward_bottom_composer.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/a11y_tab_walk.dart';
import '../../support/semantics_identifier.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Set<String> selectedIds,
  required bool noteExpanded,
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
          builder: (context) => Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () {}, child: const Text('Before')),
              ForwardBottomComposer(
                selectedIds: selectedIds,
                noteExpanded: noteExpanded,
                onToggleNoteExpanded: () {},
                sharedNoteController: note,
                onSharedNoteChanged: (_) {},
                onForward: onForward,
                sendLabel: L10n.of(context)!.postCreateSendToCount,
              ),
              TextButton(onPressed: () {}, child: const Text('After')),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

SemanticsNode _sendNode() => find.semantics
    .byPredicate(
      (n) => n.getSemanticsData().identifier == TestIds.forwardSubmit,
    )
    .evaluate()
    .single;

void main() {
  testWidgets('Tab walk through the footer: every stop reports focus', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      selectedIds: const {'u1'},
      noteExpanded: true,
      onForward: () {},
    );

    final stops = await walkTabStops(tester, before: 'Before', after: 'After');
    expect(
      stops.where((s) => s.contains('Send to 1')),
      hasLength(1),
      reason: 'Send is one focused stop: $stops',
    );
    handle.dispose();
  });

  testWidgets('Tab onto Send marks its one node focused', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      selectedIds: const {'u1'},
      noteExpanded: false,
      onForward: () {},
    );

    expect(_sendNode(), isSemantics(label: 'Send to 1', isFocused: false));
    final stops = await walkTabStops(tester, before: 'Before', after: 'After');
    expect(stops.first, contains('Send to 1'));
    // Focus moved on to «After»: Send no longer says it has focus.
    await tester.pump();
    expect(_sendNode(), isSemantics(label: 'Send to 1', isFocused: false));
    handle.dispose();
  });

  testWidgets('nobody picked: the disabled Send node carries the hint', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, selectedIds: const {}, noteExpanded: false);

    expect(
      _sendNode(),
      allOf(
        isSemantics(
          label: 'Send to 0',
          hint: 'Select at least one recipient',
          isButton: true,
          isEnabled: false,
        ),
        hasSemanticsIdentifier(TestIds.forwardSubmit),
      ),
    );
    handle.dispose();
  });

  testWidgets('ru: the disabled Send node carries the hint', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      selectedIds: const {},
      noteExpanded: false,
      locale: const Locale('ru'),
    );

    expect(
      _sendNode(),
      isSemantics(
        label: 'Отправить (0)',
        hint: 'Выберите хотя бы одного получателя',
      ),
    );
    handle.dispose();
  });

  testWidgets('someone picked: no hint on Send', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      selectedIds: const {'u1'},
      noteExpanded: false,
      onForward: () {},
    );

    expect(_sendNode().getSemanticsData().hint, isEmpty);
    handle.dispose();
  });
}
