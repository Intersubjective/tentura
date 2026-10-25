import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three ways a person opens a row's "Add to tag…" menu: the visible
/// overflow button, a touch long press and a mouse secondary tap.
enum PersonMenuOpenWay {
  overflowButton,
  touchLongPress,
  mouseSecondaryTap;

  /// Opens the menu of the row whose [overflow] button (needed only for
  /// [overflowButton]) and [target] (the place a long press or right click
  /// lands on) are given.
  Future<void> open(
    WidgetTester tester, {
    required Finder target,
    Finder? overflow,
  }) async {
    switch (this) {
      case overflowButton:
        await tester.tap(overflow!);
      case touchLongPress:
        await tester.longPress(target);
      case mouseSecondaryTap:
        final gesture = await tester.startGesture(
          tester.getCenter(target),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await gesture.up();
    }
    await tester.pumpAndSettle();
  }
}

/// Asserts that neither gesture trigger (touch long press, mouse secondary
/// tap) on [target] opens the person menu: no entry reading [entry] and none
/// of [otherEntries] (the menu's other items, e.g. "Profile") appears. The
/// overflow-button trigger is asserted by the caller as an absent button.
Future<void> expectNoPersonMenuFromGestures(
  WidgetTester tester, {
  required Finder target,
  String entry = 'Add to tag…',
  List<String> otherEntries = const [],
}) async {
  for (final way in [
    PersonMenuOpenWay.touchLongPress,
    PersonMenuOpenWay.mouseSecondaryTap,
  ]) {
    await way.open(tester, target: target);
    for (final text in [entry, ...otherEntries]) {
      expect(
        find.text(text),
        findsNothing,
        reason: 'the person menu ("$text") must not open by ${way.name}',
      );
    }
  }
}
