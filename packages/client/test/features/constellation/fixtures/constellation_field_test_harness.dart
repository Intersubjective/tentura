import 'package:flutter/gestures.dart';
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
/// field, call [startConstellationFieldGesture] (or
/// [enableConstellationTouchNodeDragsForTests] on the selection cubit). Pass
/// [touchNodeDragLocked: true] to [pumpConstellationBody] for locked-behaviour tests.
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

/// Applies the same policy to an existing cubit (e.g. after [pumpWidget]).
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
}) async {
  if (kind == PointerDeviceKind.touch || kind == PointerDeviceKind.stylus) {
    enableConstellationTouchNodeDragsForTests(
      selection ?? tester.constellationSelectionUnderTest(),
    );
    await tester.pump();
  }
  return tester.startGesture(globalPosition, kind: kind);
}
