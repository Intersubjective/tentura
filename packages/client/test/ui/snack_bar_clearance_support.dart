import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shared checks for #406: a notice bar must never be drawn over a screen's
/// primary bottom action.

/// The visible surface of the one snack bar on screen (its outer `Material`,
/// without a floating bar's transparent margin).
Rect visibleSnackBarRect(WidgetTester tester) {
  expect(find.byType(SnackBar), findsOneWidget);
  return tester.getRect(
    find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first,
  );
}

/// Asserts that the bar with [message] is fully on screen and sits above
/// [button], and that a tap on the centre of [button] reaches the button
/// rather than the bar.
void expectSnackBarClearsButton(
  WidgetTester tester, {
  required String message,
  required Finder button,
}) {
  expect(
    find.descendant(
      of: find.byType(SnackBar),
      matching: find.text(message, findRichText: true),
    ),
    findsOneWidget,
    reason: 'the notice itself must still be shown',
  );
  expect(button, findsOneWidget);

  final screen =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final bar = visibleSnackBarRect(tester);
  final target = tester.getRect(button);

  expect(bar.height, greaterThan(0));
  expect(
    bar.top >= screen.top && bar.bottom <= screen.bottom,
    isTrue,
    reason: 'the bar must stay fully on screen, got $bar in $screen',
  );
  expect(
    target.top >= screen.top && target.bottom <= screen.bottom,
    isTrue,
    reason: 'the primary button must stay fully on screen, got $target',
  );
  expect(
    bar.overlaps(target),
    isFalse,
    reason: 'bar $bar is drawn over the primary button $target',
  );
  expect(
    bar.bottom,
    lessThanOrEqualTo(target.top + 0.5),
    reason: 'the bar must sit above the bottom action bar',
  );

  final hit = tester.hitTestOnBinding(target.center);
  final buttonBox = tester.renderObject(button);
  expect(
    hit.path.any((entry) => identical(entry.target, buttonBox)),
    isTrue,
    reason: 'a tap on the primary button must reach it, not the bar',
  );
}

/// Asserts that the one bar on screen sits where a screen with no bottom
/// action puts it today: a fixed, full-width bar flush with the bottom of
/// the screen — no clearance left over from a picker that is covered by
/// another route or already gone (#406 regression guard).
void expectSnackBarAtDefaultPlacement(
  WidgetTester tester, {
  required String message,
}) {
  expect(
    find.descendant(
      of: find.byType(SnackBar),
      matching: find.text(message, findRichText: true),
    ),
    findsOneWidget,
    reason: 'the notice itself must be shown',
  );
  final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
  expect(
    snackBar.behavior,
    isNot(SnackBarBehavior.floating),
    reason: 'a plain notice here must stay a fixed bar',
  );
  expect(snackBar.margin, isNull, reason: 'no lift margin may leak here');

  final screen =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final bar = visibleSnackBarRect(tester);
  expect(bar.height, greaterThan(0));
  expect(
    bar.bottom,
    moreOrLessEquals(screen.bottom, epsilon: 0.5),
    reason: 'bar $bar must sit flush with the screen bottom $screen',
  );
  expect(bar.left, moreOrLessEquals(screen.left, epsilon: 0.5));
  expect(bar.right, moreOrLessEquals(screen.right, epsilon: 0.5));
}
