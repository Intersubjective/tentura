// #623: on web the room chat list showed a grey error box after the author
// accepted an offer or changed status ("Null check operator used on a null
// value" in SelectionContainerDelegate.hasSize, from
// SelectableRegionState.add <- _SelectionContainerState.initState).
//
// Cause: Flutter's SelectableRegion wraps its content in an extra browser
// context-menu view only while BrowserContextMenu.enabled is true, and chat
// bubbles flip that flag on hover (#456). A rebuild of an existing region
// after a flip re-creates its inner SelectionContainer under a delegate that
// already holds text, which registers before layout and throws.
//
// kIsWeb is always false here, so Flutter's own crash cannot run in a VM
// test. Spec pinned instead: when the browser-menu flag differs from the last
// build, TenturaSelectionArea starts a fresh selection region (new state, so
// nothing stale re-registers) and the text stays selectable and keeps the
// #415 "not a Tab stop" focus node; with no flip the region is kept as is.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/widget/tentura_selection_area.dart';

const _body = 'Bring the ladder on Saturday';

Future<StateSetter> _pump(WidgetTester tester) async {
  late StateSetter rebuild;
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            // Not const: a list rebuild hands every message a new widget.
            // ignore: prefer_const_constructors
            return TenturaSelectionArea(child: Text(_body));
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return rebuild;
}

SelectableRegionState _region(WidgetTester tester) =>
    tester.state<SelectableRegionState>(find.byType(SelectableRegion));

void main() {
  late bool browserMenuOn;
  final original = TenturaSelectionArea.browserContextMenuEnabled;

  setUp(() {
    browserMenuOn = true;
    TenturaSelectionArea.browserContextMenuEnabled = () => browserMenuOn;
  });
  tearDown(() => TenturaSelectionArea.browserContextMenuEnabled = original);

  testWidgets(
    '#623 a rebuild after the browser-menu flag flips starts a fresh region',
    (tester) async {
      final rebuild = await _pump(tester);
      final before = _region(tester);

      // A bubble hover turns the browser menu off, then the list rebuilds
      // (a new system line after a status change / accepted offer).
      browserMenuOn = false;
      rebuild(() {});
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(
        identical(_region(tester), before),
        isFalse,
        reason:
            'the old region would re-create its inner SelectionContainer '
            'under a delegate that already has text, which throws on web',
      );

      // And back on (pointer left the bubble), rebuild again.
      final second = _region(tester);
      browserMenuOn = true;
      rebuild(() {});
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(identical(_region(tester), second), isFalse);

      // Still selectable, still not a Tab stop of its own (#415).
      final area = tester.widget<SelectionArea>(
        find.ancestor(
          of: find.text(_body),
          matching: find.byType(SelectionArea),
        ),
      );
      expect(area.focusNode?.skipTraversal, isTrue);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    '#623 guard: with no flag flip a rebuild keeps the same region',
    (tester) async {
      final rebuild = await _pump(tester);
      final before = _region(tester);

      rebuild(() {});
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(identical(_region(tester), before), isTrue);
    },
    variant: TargetPlatformVariant.desktop(),
  );
}
