import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/constellation_arrange_harness.dart';

/// Ctrl/Cmd+Z undoes and Ctrl/Cmd+Shift+Z redoes the last arrangement action
/// on the Field when the Arrange gate is on.

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey modifier, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

/// The user drags person one to (9, 9) and the write settles.
Future<void> _dragPersonOne(
  WidgetTester tester,
  ArrangeHarness harness,
) async {
  harness.placement.place(
    parent: arrangePersonOne,
    position: arrangePosition(9, 9),
    companions: const [],
  );
  await tester.pumpAndSettle();
  expect(harness.anchors.applies, hasLength(1));
}

void main() {
  for (final (name, modifier) in [
    ('Ctrl', LogicalKeyboardKey.control),
    ('Cmd', LogicalKeyboardKey.meta),
  ]) {
    group('$name+Z on the Field', () {
      testWidgets('undoes the last drag', (tester) async {
        final harness = await arrangeHarness();
        await pumpArrangeBody(tester, harness.cubit, arrangeV2Enabled: true);
        await _dragPersonOne(tester, harness);

        await _press(tester, modifier);

        expect(harness.anchors.applies, hasLength(2));
        expect(
          harness.anchors.anchors[arrangePersonOne],
          arrangeInitialAnchors()[arrangePersonOne],
        );
      });

      testWidgets('with Shift redoes the undone drag', (tester) async {
        final harness = await arrangeHarness();
        await pumpArrangeBody(tester, harness.cubit, arrangeV2Enabled: true);
        await _dragPersonOne(tester, harness);
        await _press(tester, modifier);

        await _press(tester, modifier, shift: true);

        expect(harness.anchors.applies, hasLength(3));
        expect(
          harness.anchors.anchors[arrangePersonOne],
          arrangePosition(9, 9),
        );
      });

      testWidgets('undoes a reset and Shift redoes it', (tester) async {
        final harness = await arrangeHarness();
        final before = {...harness.anchors.anchors};
        await pumpArrangeBody(tester, harness.cubit, arrangeV2Enabled: true);
        await harness.placement.resetAll(saveHistory: true);
        await tester.pumpAndSettle();
        expect(harness.anchors.anchors, isEmpty);

        await _press(tester, modifier);

        expect(harness.anchors.restores, hasLength(1));
        expect(harness.anchors.anchors, before);
        expect(harness.anchors.applies, isEmpty);

        await _press(tester, modifier, shift: true);

        expect(harness.anchors.restores, hasLength(2));
        expect(harness.anchors.anchors, isEmpty);
      });

      testWidgets('does nothing while the gate is off', (tester) async {
        final harness = await arrangeHarness();
        await pumpArrangeBody(tester, harness.cubit, arrangeV2Enabled: false);
        await _dragPersonOne(tester, harness);

        await _press(tester, modifier);

        expect(harness.anchors.applies, hasLength(1));
        expect(
          harness.anchors.anchors[arrangePersonOne],
          arrangePosition(9, 9),
        );
      });
    });
  }
}
