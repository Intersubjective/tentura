// #605 (from #406): a notice bar is placed once, when it is shown. If the
// screen's body-bottom action (the room composer, a Forward bar) only appears
// after the bar is up — the "X shared a post with you" bar is shown while the
// post is still loading — or grows while it is up (a second line typed into
// the composer), the bar stayed where it was and covered the action.
//
// Spec: while a bar shown through `showSnackBar` is up, a body-bottom action
// in a SnackBarClearance that appears or grows under it moves the bar so it
// sits just above the action again; the same bar (text and action) stays,
// and only one bar is shown.
//
// PR #819 review: a move is a remove + a new bar, so it slides in again and
// screen readers announce it again (the bar is a live region). The bar is
// only moved once the action's height has settled, and only when the action
// would now reach under it: a shrink, or a growth that still clears it,
// leaves the bar alone.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/snack_bar_clearance.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'snack_bar_clearance_support.dart';

const _notice = 'Alice shared a post with you.';

final _bodyKey = GlobalKey(debugLabel: 'screen body');

final _actionKey = GlobalKey(debugLabel: 'body-bottom action');

/// null: no action yet (still loading); else the action's height.
final _actionHeight = ValueNotifier<double?>(null);

Future<void> _pump(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(Logger('test'));
    addTearDown(GetIt.I.reset);
  }
  _actionHeight.value = null;
  await tester.pumpWidget(
    MaterialApp(
      scaffoldMessengerKey: snackbarKey,
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        key: _bodyKey,
        body: ValueListenableBuilder<double?>(
          valueListenable: _actionHeight,
          builder: (context, height, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: SizedBox()),
              if (height != null)
                SnackBarClearance(
                  child: SizedBox(
                    height: height,
                    child: ColoredBox(
                      key: _actionKey,
                      color: TenturaTheme.light().colorScheme.surface,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _settleBar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  // A move waits for the action's height to settle (the bar is replaced in
  // this frame) ...
  await tester.pump(const Duration(milliseconds: 400));
  // ... then the new bar's entry animation starts on the next frame (its
  // ticker takes its start time there) and runs to the end. Without this
  // frame the bar is still at the start of its entry: drawn in place, but
  // laid out zero high, so a tap goes through it.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 750));
}

/// Every distinct bar shown, in order: a new [SnackBar] is a new live region
/// (announced again by screen readers) and slides in again.
final _shownBars = <SnackBar>[];

void _recordBar(WidgetTester tester) {
  final finder = find.byType(SnackBar);
  if (finder.evaluate().isEmpty) return;
  final bar = tester.widget<SnackBar>(finder.first);
  if (_shownBars.isEmpty || !identical(_shownBars.last, bar)) {
    _shownBars.add(bar);
  }
}

/// The composer takes [height] (a line typed or removed) and a frame or two
/// pass, recording each bar on screen.
Future<void> _typeTo(
  WidgetTester tester,
  double height, {
  Duration wait = const Duration(milliseconds: 100),
}) async {
  _actionHeight.value = height;
  await tester.pump();
  _recordBar(tester);
  await tester.pump();
  _recordBar(tester);
  await tester.pump(wait);
  _recordBar(tester);
}

Future<void> _showBar(WidgetTester tester, {VoidCallback? onOpen}) async {
  showSnackBar(
    tester.element(find.byKey(_bodyKey)),
    text: _notice,
    action: SnackBarAction(label: 'Open post', onPressed: onOpen ?? () {}),
  );
  await _settleBar(tester);
}

void _expectClear(WidgetTester tester) {
  final bar = visibleSnackBarRect(tester);
  final action = tester.getRect(find.byKey(_actionKey));
  expect(
    bar.overlaps(action),
    isFalse,
    reason: 'bar $bar is drawn over the body-bottom action $action',
  );
  expect(bar.bottom, lessThanOrEqualTo(action.top + 0.5));
  expect(
    find.descendant(
      of: find.byType(SnackBar),
      matching: find.text(_notice, findRichText: true),
    ),
    findsOneWidget,
  );
  expect(find.text('Open post'), findsOneWidget);
}

void main() {
  testWidgets('an action that appears after the bar is up lifts the bar', (
    tester,
  ) async {
    await _pump(tester);
    await _showBar(tester);
    expect(find.byType(SnackBar), findsOneWidget);

    // The page finishes loading and its composer comes in under the bar.
    _actionHeight.value = 72;
    await _settleBar(tester);

    _expectClear(tester);
  });

  testWidgets('an action that grows while the bar is up lifts the bar again', (
    tester,
  ) async {
    await _pump(tester);
    _actionHeight.value = 72;
    await tester.pump();
    await _showBar(tester);
    _expectClear(tester);

    // A second line in the composer makes it taller.
    _actionHeight.value = 180;
    await _settleBar(tester);

    _expectClear(tester);
  });

  testWidgets('the moved bar keeps its action', (tester) async {
    var opened = 0;
    await _pump(tester);
    await _showBar(tester, onOpen: () => opened++);

    // The composer comes in under the bar: the bar is moved (a new bar).
    _actionHeight.value = 72;
    await _settleBar(tester);
    _expectClear(tester);
    await tester.tap(find.text('Open post'));
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('a bar closed by hand is not brought back by a later change', (
    tester,
  ) async {
    await _pump(tester);
    await _showBar(tester);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    _actionHeight.value = 72;
    await _settleBar(tester);

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'composer changes that keep the bar clear do not show it again',
    (tester) async {
      await _pump(tester);
      _shownBars.clear();
      // Shown over a tall composer (a reply preview and a few lines).
      _actionHeight.value = 180;
      await tester.pump();
      final controller = showSnackBar(
        tester.element(find.byKey(_bodyKey)),
        text: _notice,
        action: SnackBarAction(label: 'Open post', onPressed: () {}),
      )!;
      var closed = false;
      unawaited(controller.closed.then((_) => closed = true));
      await _settleBar(tester);
      _recordBar(tester);
      _expectClear(tester);

      // The reply preview is dropped, then lines are typed back in; none
      // reaches the bar (186 still leaves it a margin).
      for (final height in [72.0, 100.0, 120.0, 150.0, 186.0]) {
        await _typeTo(tester, height);
      }
      await _settleBar(tester);
      _recordBar(tester);

      expect(
        _shownBars,
        hasLength(1),
        reason: 'the bar must not vanish and slide in (and be announced) again',
      );
      expect(closed, isFalse);
      _expectClear(tester);
    },
  );

  testWidgets(
    'lines typed in a row move the bar once, after the height settles',
    (tester) async {
      await _pump(tester);
      _shownBars.clear();
      _actionHeight.value = 72;
      await tester.pump();
      await _showBar(tester);
      _recordBar(tester);

      // Three lines typed quickly, each reaching under the bar.
      for (final height in [100.0, 128.0, 156.0]) {
        await _typeTo(tester, height);
      }
      expect(
        _shownBars,
        hasLength(1),
        reason: 'the bar must wait for the composer to stop growing',
      );

      await _settleBar(tester);
      _recordBar(tester);

      expect(_shownBars, hasLength(2), reason: 'moved exactly once');
      _expectClear(tester);
    },
  );
}
