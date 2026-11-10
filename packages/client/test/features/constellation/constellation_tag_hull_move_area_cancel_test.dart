import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_hull_layer.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_tag_hull_drag_harness.dart';

// What these tests pin down, in user terms:
//  * «Move area» is offered by a right click on a tag's hull whether or not
//    the Field is in Arranging, and a right click on the hull opens no panel.
//  * Esc during a move (area move from the menu, held hull drag, held node
//    drag) puts everything back exactly where it was, writes nothing, adds no
//    Undo step, and does not leave Arranging.

const _desktop = Size(1280, 800);
const _travel = Offset(56, 28);
const _undoKey = Key('constellation.arranging.undo');
// The fixture's layout keeps every Post at one fixed point, so a Post riding
// along with its author cannot be observed here (that needs the web
// integration test); the Posts are only checked to be where they were.
const _postsOfMembers = ['fr:post-ann', 'fr:post-bob', 'fr:post-cid'];

Finder _node(String id) => find.byKey(TestIds.key(TestIds.graphNode(id)));

bool _insideTriangle(Offset p, Offset a, Offset b, Offset c) {
  double side(Offset p1, Offset p2, Offset p3) =>
      (p1.dx - p3.dx) * (p2.dy - p3.dy) - (p2.dx - p3.dx) * (p1.dy - p3.dy);
  final d1 = side(p, a, b);
  final d2 = side(p, b, c);
  final d3 = side(p, c, a);
  final hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
  final hasPos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(hasNeg && hasPos);
}

/// A point the user sees as empty space inside the tag-a area: the middle of
/// the three members. The area encloses the members, so the point lies in it
/// because it lies inside the triangle the members span (checked), and it is
/// clear of every drawn node (checked).
Offset _emptyHullPoint(WidgetTester tester) {
  final centres = [
    for (final id in hullDragMembers) tester.getCenter(_node(id)),
  ];
  final middle = centres.reduce((a, b) => a + b) / centres.length.toDouble();
  expect(
    _insideTriangle(middle, centres[0], centres[1], centres[2]),
    isTrue,
    reason: 'the point is inside the area the three members span',
  );
  for (final id in hullDragPeople) {
    expect(
      tester.getRect(_node(id)).inflate(16).contains(middle),
      isFalse,
      reason: 'the middle of the area is empty space, not on $id',
    );
  }
  return middle;
}

/// The texts the open context menu shows: everything drawn on the menu's
/// panel, found as the outermost Material around the «Move area» label that
/// is smaller than the screen.
List<String> _menuTexts(WidgetTester tester) {
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  Element? panel;
  tester
      .element(find.text('Переместить область «Соседи»'))
      .visitAncestorElements(
        (e) {
          if (e.widget is Material) {
            final size = (e.renderObject! as RenderBox).size;
            if (size.width < screen.width && size.height < screen.height) {
              panel = e;
            }
          }
          return true;
        },
      );
  expect(panel, isNotNull, reason: 'the menu has a panel');
  final texts = <String>[];
  void visit(Element e) {
    final w = e.widget;
    if (w is Text && w.data != null) texts.add(w.data!);
    e.visitChildren(visit);
  }

  visit(panel!);
  return texts;
}

Future<TestGesture> _secondaryTapAt(WidgetTester tester, Offset global) async {
  final gesture = await tester.startGesture(
    global,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
  return gesture;
}

Map<String, Offset> _positions(HullDragHarness h) => {
  for (final id in [
    ...hullDragPeople.map((id) => 'fp:$id'),
    ..._postsOfMembers,
  ])
    id: h.cubit.graphController.getPositionOrNullForId(id)!,
};

void _expectBack(
  HullDragHarness h,
  Map<String, Offset> before, {
  required String reason,
}) {
  final now = _positions(h);
  for (final id in before.keys) {
    expect(
      (now[id]! - before[id]!).distance,
      lessThan(1),
      reason: '$reason: $id is back where it was',
    );
  }
}

String? _liftedTag(WidgetTester tester) => tester
    .widget<ConstellationTagHullLayer>(find.byType(ConstellationTagHullLayer))
    .liftedTagId;

String _menuLabel(WidgetTester tester) => L10n.of(
  tester.element(find.byType(ConstellationBody)),
)!.constellationTagHullMoveArea('Соседи');

Future<void> _hoverBy(
  WidgetTester tester,
  TestGesture mouse,
  Offset from,
) async {
  for (var i = 1; i <= 8; i++) {
    await mouse.moveTo(from + _travel * (i / 8));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Right click on the hull, pick «Move area», and carry the area by [_travel]
/// with the mouse (no button held). Returns the mouse, the start point, and
/// where everything stood right after the menu lifted the area (the area
/// first snaps under the pointer), before the mouse moved on.
Future<({TestGesture mouse, Offset point, Map<String, Offset> lifted})>
_menuMoveAreaStarted(WidgetTester tester, HullDragHarness h) async {
  final point = _emptyHullPoint(tester);
  final mouse = await _secondaryTapAt(tester, point);
  await tester.tap(find.text(_menuLabel(tester)));
  await tester.pumpAndSettle();
  await mouse.moveTo(point);
  await tester.pump();
  final lifted = _positions(h);
  await _hoverBy(tester, mouse, point);
  return (mouse: mouse, point: point, lifted: lifted);
}

/// The area follows the pointer: the mouse moved by [_travel], so every
/// member moved by [_travel] from where the lift left it.
void _expectCarriedByMouse(HullDragHarness h, Map<String, Offset> lifted) {
  final now = _positions(h);
  for (final id in hullDragMembers) {
    expect(
      ((now['fp:$id']! - lifted['fp:$id']!) - _travel).distance,
      lessThan(1.5),
      reason: '$id follows the mouse by its full travel with no button held',
    );
  }
  for (final id in ['dan', 'eve']) {
    expect(
      (now['fp:$id']! - lifted['fp:$id']!).distance,
      lessThan(1),
      reason: '$id is not in the tag and stays put',
    );
  }
}

Future<void> _clickAt(
  WidgetTester tester,
  TestGesture mouse,
  Offset at,
) async {
  await mouse.moveTo(at);
  await tester.pump();
  await mouse.down(at);
  await tester.pump();
  await mouse.up();
  await tester.pump();
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await flushHullDragWrites(tester);
}

Future<void> _tapUndo(WidgetTester tester) async {
  await tester.tap(find.byKey(_undoKey));
  await flushHullDragWrites(tester);
}

void _expectMembersMoved(HullDragHarness h, Map<String, Offset> before) {
  final now = _positions(h);
  for (final id in hullDragMembers) {
    expect(
      (now['fp:$id']! - before['fp:$id']!).distance,
      greaterThan(25),
      reason: '$id has visibly moved with the area',
    );
  }
}

void _expectArrangingStillOpen(HullDragHarness h) {
  expect(h.selection.state.arranging, isTrue, reason: 'Esc keeps Arranging');
  expect(find.byKey(_undoKey), findsOneWidget);
}

void main() {
  group('secondary click on a tag hull outside Arranging', () {
    testWidgets(
      'desktop RU: offers only «Move area» (one menu entry) and opens no panel',
      (
        tester,
      ) async {
        await withHullDragField(
          tester,
          (h) async {
            await _secondaryTapAt(tester, _emptyHullPoint(tester));
            expect(find.text('Переместить область «Соседи»'), findsOneWidget);
            expect(_menuTexts(tester), ['Переместить область «Соседи»']);
            expect(h.cubit.state.selectedPersonId, isNull);
            expect(h.cubit.state.selectedRequestId, isNull);
            expect(tester.takeException(), isNull);
          },
          arranging: false,
          surface: _desktop,
        );
      },
    );

    testWidgets(
      '375×667 RU: offers only «Move area» (one menu entry) and opens no panel',
      (
        tester,
      ) async {
        await withHullDragField(tester, (h) async {
          await _secondaryTapAt(tester, _emptyHullPoint(tester));
          expect(find.text('Переместить область «Соседи»'), findsOneWidget);
          expect(_menuTexts(tester), ['Переместить область «Соседи»']);
          expect(h.cubit.state.selectedPersonId, isNull);
          expect(h.cubit.state.selectedRequestId, isNull);
          expect(tester.takeException(), isNull);
        }, arranging: false);
      },
    );

    testWidgets(
      'desktop: moving the mouse carries every member, a click drops one '
      'batch, one Undo restores the anchors',
      (tester) async {
        await withHullDragField(
          tester,
          (h) async {
            final initialAnchors = {...h.server.anchors};
            final started = await _menuMoveAreaStarted(tester, h);
            _expectCarriedByMouse(h, started.lifted);
            final carried = _positions(h);
            await _clickAt(tester, started.mouse, started.point + _travel);
            await flushHullDragWrites(tester);
            for (final id in hullDragMembers) {
              expect(
                (_positions(h)['fp:$id']! - carried['fp:$id']!).distance,
                lessThan(1.5),
                reason: '$id is dropped where the mouse carried it',
              );
            }
            expect(h.server.applies, hasLength(1));
            expect(
              h.server.applies.single
                  .map((op) => op.target)
                  .where((t) => t.kind == ConstellationAnchorTargetKind.person),
              unorderedEquals([
                for (final id in hullDragMembers)
                  ConstellationAnchorTarget.person(id),
              ]),
            );
            await _tapUndo(tester);
            expect(h.server.applies, hasLength(2));
            expect(h.server.anchors, initialAnchors);
            expect(tester.takeException(), isNull);
          },
          arranging: false,
          surface: _desktop,
        );
      },
    );
  });

  testWidgets(
    'desktop in Arranging: right click still offers «Move area» and the '
    'click drops one batch',
    (tester) async {
      await withHullDragField(
        tester,
        (h) async {
          final started = await _menuMoveAreaStarted(tester, h);
          _expectCarriedByMouse(h, started.lifted);
          await _clickAt(tester, started.mouse, started.point + _travel);
          await flushHullDragWrites(tester);
          expect(h.server.applies, hasLength(1));
          expect(tester.takeException(), isNull);
        },
        arranging: true,
        surface: _desktop,
      );
    },
  );

  group('Esc during a move', () {
    for (final arranging in [false, true]) {
      testWidgets(
        'after the menu move carried the area '
        '${arranging ? 'in' : 'outside'} Arranging: restores the members, writes nothing, and a later click drops nothing',
        (tester) async {
          await withHullDragField(
            tester,
            (h) async {
              final before = _positions(h);
              final started = await _menuMoveAreaStarted(tester, h);
              final (mouse, point) = (started.mouse, started.point);
              _expectMembersMoved(h, before);
              _expectCarriedByMouse(h, started.lifted);
              expect(_liftedTag(tester), 'tag-a', reason: 'the area is lifted');
              await _escape(tester);
              expect(h.server.applies, isEmpty, reason: 'Esc writes nothing');
              _expectBack(h, before, reason: 'after Esc');
              expect(_liftedTag(tester), isNull, reason: 'hull is lowered');

              await mouse.moveTo(point + _travel * 2);
              await tester.pump();
              await _clickAt(tester, mouse, point + _travel * 2);
              await flushHullDragWrites(tester);
              _expectBack(h, before, reason: 'after a later move and click');
              expect(h.server.applies, isEmpty);
              expect(tester.takeException(), isNull);
            },
            arranging: arranging,
            surface: _desktop,
          );
        },
      );
    }

    testWidgets(
      'guard: a held hull drag lifted by long press in Arranging is put back '
      'by Esc, Arranging stays open, and releasing writes nothing',
      (tester) async {
        await withHullDragField(
          tester,
          (h) async {
            final before = _positions(h);
            final point = _emptyHullPoint(tester);
            final gesture = await tester.startGesture(
              point,
              kind: PointerDeviceKind.mouse,
            );
            await tester.pump(const Duration(milliseconds: 500));
            for (var i = 1; i <= 8; i++) {
              await gesture.moveTo(point + _travel * (i / 8));
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(_liftedTag(tester), 'tag-a', reason: 'the hold lifted it');
            _expectMembersMoved(h, before);
            await _escape(tester);
            _expectBack(h, before, reason: 'after Esc with the button held');
            expect(_liftedTag(tester), isNull);
            _expectArrangingStillOpen(h);
            // The user keeps the button down and keeps moving: the cancelled
            // move must not resume.
            for (var i = 1; i <= 8; i++) {
              await gesture.moveTo(point + _travel * (1 + i / 8));
              await tester.pump(const Duration(milliseconds: 16));
            }
            _expectBack(h, before, reason: 'moving on after Esc');
            await gesture.up();
            await flushHullDragWrites(tester);
            expect(h.server.applies, isEmpty);
            _expectBack(h, before, reason: 'after release');
            _expectArrangingStillOpen(h);
            expect(tester.takeException(), isNull);
          },
          arranging: true,
          surface: _desktop,
        );
      },
    );

    testWidgets(
      'guard: a held node drag in Arranging is put back by Esc, nothing else '
      'moves, Arranging stays open, and releasing writes nothing',
      (tester) async {
        await withHullDragField(
          tester,
          (h) async {
            final before = _positions(h);
            final start = tester.getCenter(_node('ann'));
            final gesture = await tester.startGesture(
              start,
              kind: PointerDeviceKind.mouse,
            );
            await tester.pump();
            for (var i = 1; i <= 8; i++) {
              await gesture.moveTo(start + _travel * (i / 8));
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(
              (_positions(h)['fp:ann']! - before['fp:ann']!).distance,
              greaterThan(25),
              reason: 'the node follows the pointer',
            );
            await _escape(tester);
            _expectBack(h, before, reason: 'after Esc with the button held');
            _expectArrangingStillOpen(h);
            for (var i = 1; i <= 8; i++) {
              await gesture.moveTo(start + _travel * (1 + i / 8));
              await tester.pump(const Duration(milliseconds: 16));
            }
            _expectBack(h, before, reason: 'moving on after Esc');
            await gesture.up();
            await flushHullDragWrites(tester);
            expect(h.server.applies, isEmpty);
            _expectBack(h, before, reason: 'after release');
            _expectArrangingStillOpen(h);
            expect(tester.takeException(), isNull);
          },
          arranging: true,
          surface: _desktop,
        );
      },
    );

    testWidgets(
      'a cancelled menu move in Arranging puts the area back, lowers the '
      'hull and keeps Arranging open',
      (tester) async {
        await withHullDragField(
          tester,
          (h) async {
            final before = _positions(h);
            final started = await _menuMoveAreaStarted(tester, h);
            _expectCarriedByMouse(h, started.lifted);
            await _escape(tester);
            _expectBack(h, before, reason: 'after Esc');
            expect(_liftedTag(tester), isNull);
            expect(h.server.applies, isEmpty);
            _expectArrangingStillOpen(h);
            expect(tester.takeException(), isNull);
          },
          arranging: true,
          surface: _desktop,
        );
      },
    );

    testWidgets(
      'a cancelled move adds no Undo step: one Undo goes back past the '
      'earlier drop',
      (tester) async {
        await withHullDragField(
          tester,
          (h) async {
            final initialAnchors = {...h.server.anchors};
            final point = _emptyHullPoint(tester);
            final drag = await tester.startGesture(
              point,
              kind: PointerDeviceKind.mouse,
            );
            await tester.pump(const Duration(milliseconds: 500));
            for (var i = 1; i <= 8; i++) {
              await drag.moveTo(point + _travel * (i / 8));
              await tester.pump(const Duration(milliseconds: 16));
            }
            await drag.up();
            await flushHullDragWrites(tester);
            expect(h.server.applies, hasLength(1));
            final afterDrop = _positions(h);

            final started = await _menuMoveAreaStarted(tester, h);
            _expectCarriedByMouse(h, started.lifted);
            await _escape(tester);
            _expectBack(h, afterDrop, reason: 'after Esc');
            expect(_liftedTag(tester), isNull);
            expect(h.server.applies, hasLength(1));

            await _tapUndo(tester);
            expect(h.server.applies, hasLength(2));
            expect(h.server.anchors, initialAnchors);
            expect(tester.takeException(), isNull);
          },
          arranging: true,
          surface: _desktop,
        );
      },
    );
  });
}
