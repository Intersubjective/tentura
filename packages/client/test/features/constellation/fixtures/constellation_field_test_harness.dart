import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';

/// Field body widget tests after #938 touch node-drag lock.
///
/// Production: touch drags on saved nodes require Arranging (`touchNodeDragLocked`
/// is false only while arranging). Mouse/trackpad are exempt in the graph package.
///
/// [constellationSelectionForFieldBodyTests] only supplies the cubit most widget
/// tests need. Before simulated **touch** node drags on a saved (non-composing)
/// field, call startConstellationFieldGesture (or
/// enableConstellationTouchNodeDragsForTests on the selection cubit). Use
/// pumpConstellationBody touchNodeDragLocked for locked-behaviour tests.
ConstellationSelectionCubit constellationSelectionForFieldBodyTests() {
  return ConstellationSelectionCubit();
}

/// Puts the Field into Arranging so touch node drags behave like pre-#938 tests.
void enableConstellationTouchNodeDragsForTests(
  ConstellationSelectionCubit selection,
) {
  if (!selection.state.arranging) {
    selection.enterArranging();
  }
}

/// Field «Arranging» must be active before the select tool or overflow menu (#938).
void enterConstellationArrangingForTests(
  ConstellationSelectionCubit selection,
) {
  enableConstellationTouchNodeDragsForTests(selection);
}

/// Turns on the select tool without entering Arranging (keeps the selection bar).
void enableConstellationSelectToolForTests(
  ConstellationSelectionCubit selection,
) {
  if (!selection.state.selecting) {
    selection.setSelecting(true);
  }
}

/// Rubber-band box selection while Arranging (embedded selection UI).
void enableConstellationBoxSelectionForTests(
  ConstellationSelectionCubit selection,
) {
  enterConstellationArrangingForTests(selection);
  enableConstellationSelectToolForTests(selection);
}

/// Opens the Arrange overflow menu from the arranging toolbar or camera control.
Future<void> openConstellationArrangeOverflowMenu(WidgetTester tester) async {
  final toolbar = find.byKey(const Key('constellation.arranging.toolbar'));
  if (toolbar.evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('constellation.camera.arrange')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('constellation.arranging.more')));
  await tester.pumpAndSettle();
}

/// Taps a localized row in the Arrange overflow menu.
Future<void> tapConstellationArrangeOverflowAction(
  WidgetTester tester,
  String label,
) async {
  await openConstellationArrangeOverflowMenu(tester);
  final action = find.text(label);
  expect(action, findsOneWidget, reason: 'overflow menu shows $label');
  await tester.ensureVisible(action);
  await tester.tap(action, warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// Applies the same policy to an existing cubit (e.g. after pumpWidget).
void applyConstellationTouchDragTestPolicy(
  ConstellationSelectionCubit selection, {
  bool touchNodeDragLocked = false,
}) {
  if (touchNodeDragLocked) {
    if (selection.state.arranging) {
      selection.exitArranging();
    }
    return;
  }
  enableConstellationTouchNodeDragsForTests(selection);
}

extension ConstellationFieldTestHarnessWidgetTester on WidgetTester {
  ConstellationSelectionCubit constellationSelectionUnderTest() {
    return element(
      find.byType(ConstellationBody),
    ).read<ConstellationSelectionCubit>();
  }
}

/// Starts a pointer on the Field map; touch kinds enter Arranging first (#938).
Future<TestGesture> startConstellationFieldGesture(
  WidgetTester tester,
  Offset globalPosition, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
  ConstellationSelectionCubit? selection,
  bool unlockTouchNodeDrags = true,
}) async {
  if (unlockTouchNodeDrags &&
      (kind == PointerDeviceKind.touch || kind == PointerDeviceKind.stylus)) {
    enableConstellationTouchNodeDragsForTests(
      selection ?? tester.constellationSelectionUnderTest(),
    );
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }
  return tester.startGesture(globalPosition, kind: kind);
}
