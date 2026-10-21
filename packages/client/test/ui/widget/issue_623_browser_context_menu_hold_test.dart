// #623 / owner review on #626: the browser's own context menu was turned
// off and on by every chat-bubble hover (#456). Flutter's SelectableRegion
// wraps its content in a browser-menu view only while that menu is on, so a
// flip under a mounted message crashed its next rebuild (an accepted offer
// or a status change inserting a system line) into a grey error box.
//
// Spec: BrowserContextMenuHold turns the browser menu off ONCE while it is
// mounted (on web only), builds its child only after the menu is off (so no
// selectable text is ever built across the flip), counts holds so stacked or
// nested rooms never turn it back on in between, and turns it back on when
// the last hold goes. Off the web it is a plain pass-through.
//
// kIsWeb is always false here and BrowserContextMenu asserts web, so the
// web check and the two menu calls go through the widget's test seams.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/widget/browser_context_menu_hold.dart';

const _room = 'Room messages';

void main() {
  final originalIsWeb = BrowserContextMenuHold.isWeb;
  final originalDisable = BrowserContextMenuHold.disableMenu;
  final originalEnable = BrowserContextMenuHold.enableMenu;

  late List<String> calls;
  late Completer<void> menuOff;
  late bool menuOffAtOnce;

  setUp(() {
    calls = [];
    menuOffAtOnce = false;
    BrowserContextMenuHold.isWeb = () => true;
    // The completer is made here, inside the test's fake clock: one made in
    // setUp would complete on the real event loop, which pumps never run.
    BrowserContextMenuHold.disableMenu = () {
      calls.add('disable');
      if (menuOffAtOnce) return Future<void>.value();
      menuOff = Completer<void>();
      return menuOff.future;
    };
    BrowserContextMenuHold.enableMenu = () async {
      calls.add('enable');
    };
  });

  tearDown(() {
    BrowserContextMenuHold.isWeb = originalIsWeb;
    BrowserContextMenuHold.disableMenu = originalDisable;
    BrowserContextMenuHold.enableMenu = originalEnable;
  });

  Future<void> pumpHolds(WidgetTester tester, List<Key> keys) =>
      tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              for (final key in keys)
                BrowserContextMenuHold(key: key, child: const Text(_room)),
            ],
          ),
        ),
      );

  Future<void> unmountAll(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(BrowserContextMenuHold.activeHolds, 0);
  }

  testWidgets(
    '#623 on web the menu goes off once and the room is built only after',
    (tester) async {
      await pumpHolds(tester, const [ValueKey('a')]);
      expect(calls, ['disable']);
      expect(
        find.text(_room),
        findsNothing,
        reason: 'no selectable text may be built while the menu still flips',
      );

      menuOff.complete();
      await tester.pumpAndSettle();
      expect(find.text(_room), findsOneWidget);

      // Ordinary rebuilds of the room do not touch the menu again.
      await pumpHolds(tester, const [ValueKey('a')]);
      await tester.pumpAndSettle();
      expect(calls, ['disable']);

      await unmountAll(tester);
      expect(calls, ['disable', 'enable']);
    },
  );

  testWidgets(
    '#623 stacked rooms share one hold: the menu comes back with the last',
    (tester) async {
      menuOffAtOnce = true;
      await pumpHolds(tester, const [ValueKey('a')]);
      await tester.pumpAndSettle();
      await pumpHolds(tester, const [ValueKey('a'), ValueKey('b')]);
      await tester.pumpAndSettle();
      expect(calls, ['disable']);
      expect(
        find.text(_room),
        findsNWidgets(2),
        reason: 'a second room while the menu is already off builds at once',
      );
      expect(BrowserContextMenuHold.activeHolds, 2);

      await pumpHolds(tester, const [ValueKey('b')]);
      await tester.pumpAndSettle();
      expect(calls, ['disable'], reason: 'one room is still up');

      await unmountAll(tester);
      expect(calls, ['disable', 'enable']);
    },
  );

  testWidgets(
    '#623 switching rooms (a remount) never turns the menu back on between',
    (tester) async {
      menuOffAtOnce = true;
      await pumpHolds(tester, const [ValueKey('a')]);
      await tester.pumpAndSettle();
      await pumpHolds(tester, const [ValueKey('b')]);
      await tester.pumpAndSettle();
      expect(calls, ['disable']);
      expect(find.text(_room), findsOneWidget);

      await unmountAll(tester);
      expect(calls, ['disable', 'enable']);
    },
  );

  testWidgets(
    '#623 a disable call that never returns does not leave the room blank',
    (tester) async {
      await pumpHolds(tester, const [ValueKey('a')]);
      expect(find.text(_room), findsNothing);

      await tester.pump(BrowserContextMenuHold.menuOffWait);
      expect(
        find.text(_room),
        findsOneWidget,
        reason: 'the room is built once the wait runs out',
      );

      await unmountAll(tester);
      expect(calls, ['disable', 'enable']);
    },
  );

  testWidgets('#623 guard: off the web the hold is a plain pass-through', (
    tester,
  ) async {
    BrowserContextMenuHold.isWeb = () => false;
    await pumpHolds(tester, const [ValueKey('a')]);
    expect(find.text(_room), findsOneWidget);
    expect(BrowserContextMenuHold.activeHolds, 0);

    await unmountAll(tester);
    expect(calls, isEmpty);
  });
}
