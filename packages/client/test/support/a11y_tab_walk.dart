import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'a11y_focus.dart';

String _describeFocus() {
  final focus = FocusManager.instance.primaryFocus;
  return '${focus?.debugLabel ?? focus?.runtimeType} '
      '(${focus?.context?.widget.runtimeType})';
}

/// Tabs from the control whose text is [before] to the one whose text is
/// [after] (#415). At every stop, expects a focused semantics node, and a
/// different one than at the previous stop: on the web that is what moves
/// the browser's focus once per press. Returns what each stop's focused
/// node says, in Tab order (the last entry is [after]).
///
/// Requires semantics to be on (`tester.ensureSemantics()`).
Future<List<String>> walkTabStops(
  WidgetTester tester, {
  required String before,
  required String after,
}) async {
  final afterNode = Focus.of(tester.element(find.text(after)));
  Focus.of(tester.element(find.text(before))).requestFocus();
  // requestFocus applies in a microtask after this pump's (absent) frame;
  // the second pump rebuilds Focus's semantics with the new focus.
  await tester.pump();
  await tester.pump();
  var previous = focusedSemanticsNodes().map((n) => n.id).toSet();
  expect(previous, isNotEmpty, reason: 'precondition: «$before» is focused');
  final seen = <String>[];
  for (var i = 0; i < 40; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final nodes = focusedSemanticsNodes();
    final said = nodes.map(describeSemanticsNode).join(' + ');
    final ids = nodes.map((n) => n.id).toSet();
    expect(
      ids,
      isNotEmpty,
      reason:
          'Tab ${i + 1} focused ${_describeFocus()}, but no semantics node '
          'says it has focus: on the web the browser keeps focus on the '
          'previous control (${seen.isEmpty ? before : seen.last}). '
          'Stops so far: $seen',
    );
    expect(
      ids,
      isNot(equals(previous)),
      reason:
          'Tab ${i + 1} (${_describeFocus()}) left the browser focus on the '
          'same node as the previous press ($said). Stops so far: $seen',
    );
    seen.add(said);
    previous = ids;
    if (identical(FocusManager.instance.primaryFocus, afterNode)) return seen;
  }
  fail('Tab never reached «$after»: $seen');
}
