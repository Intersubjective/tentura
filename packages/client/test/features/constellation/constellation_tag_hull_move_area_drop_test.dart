import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_tag_hull_drag_harness.dart';

// What these tests pin down, in user terms (#1021, «Move area»):
//  * The click (or tap) that drops an area lifted from the hull menu only
//    drops it: it saves every member in one batch, offers one Undo, and does
//    not open the panel of the person under the pointer — whether that is a
//    member carried along or a non-member the area was dropped onto.
//  * The same holds on the 375×667 phone in Russian.
//  * One Undo tap reverts the whole area move: one more write, every member
//    back at its pre-move anchor, and Undo no longer offered for it.
//  * Outside Arranging, choosing «Move area» enters Arranging, and Arranging
//    stays open after the drop with Undo enabled.
// The fake anchor server here cannot show the drop surviving «Done» and a
// Field reload; the web integration test
// integration_test/constellation_tag_hull_move_area_drop_test.dart proves
// that on the real stack.

const _desktop = Size(1280, 800);
const _travel = Offset(56, 28);
const _undoKey = Key('constellation.arranging.undo');

Finder _node(String id) => find.byKey(TestIds.key(TestIds.graphNode(id)));

/// Empty space inside the «Соседи» area: the middle of its three members.
Offset _emptyHullPoint(WidgetTester tester) {
  final centres = [
    for (final id in hullDragMembers) tester.getCenter(_node(id)),
  ];
  final middle = centres.reduce((a, b) => a + b) / centres.length.toDouble();
  for (final id in hullDragPeople) {
    expect(
      tester.getRect(_node(id)).inflate(16).contains(middle),
      isFalse,
      reason: 'the middle of the area is empty space, not on $id',
    );
  }
  return middle;
}

String _menuLabel(WidgetTester tester, [String tagName = 'Соседи']) => L10n.of(
  tester.element(find.byType(ConstellationBody)),
)!.constellationTagHullMoveArea(tagName);

Map<String, Offset> _positions(HullDragHarness h) => {
  for (final id in hullDragPeople)
    id: h.cubit.graphController.getPositionOrNullForId('fp:$id')!,
};

/// Right click on empty hull space, then pick «Move area» with a left click,
/// as a user with a mouse does. Returns the left-button mouse (the device
/// that hovers and clicks to drop), the hull point, and where everyone stood
/// right after the menu lifted the area (before the mouse moved on).
Future<({TestGesture mouse, Offset point, Map<String, Offset> lifted})>
_menuMoveArea(
  WidgetTester tester,
  HullDragHarness h, {
  String tagName = 'Соседи',
}) async {
  final point = _emptyHullPoint(tester);
  final rightClick = await tester.startGesture(
    point,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pump();
  await rightClick.up();
  await tester.pumpAndSettle();
  await rightClick.removePointer();
  expect(find.text(_menuLabel(tester, tagName)), findsOneWidget);
  final item = tester.getCenter(find.text(_menuLabel(tester, tagName)));
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: item);
  await tester.pump();
  await mouse.down(item);
  await tester.pump();
  await mouse.up();
  await tester.pumpAndSettle();
  return (mouse: mouse, point: point, lifted: _positions(h));
}

/// Hovers (no button held) from [from] to [to] and clicks there once with
/// the left button.
Future<void> _hoverAndClick(
  WidgetTester tester,
  TestGesture mouse,
  Offset from,
  Offset to, {
  required List<String> onPersons,
}) async {
  await mouse.moveTo(from);
  await tester.pump();
  for (var i = 1; i <= 8; i++) {
    await mouse.moveTo(Offset.lerp(from, to, i / 8)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    onPersons.any((id) => tester.getRect(_node(id)).contains(to)),
    isTrue,
    reason: 'the drop click lands on a person node ($onPersons)',
  );
  await mouse.down(to);
  await tester.pump();
  await mouse.up();
  await tester.pump();
  await flushHullDragWrites(tester);
}

/// The centre of the first of [ids] a finger can actually tap: on screen,
/// with nothing drawn over it, so the tap reaches that node.
Offset _tappableNodeCentre(WidgetTester tester, List<String> ids) {
  for (final id in ids) {
    final centre = tester.getCenter(_node(id));
    final node = tester.renderObject(_node(id));
    if (tester
        .hitTestOnBinding(centre)
        .path
        .any((entry) => entry.target == node)) {
      return centre;
    }
  }
  fail('none of $ids can be tapped on screen');
}

void _expectUndoEnabled(WidgetTester tester) {
  final undo = find.byKey(_undoKey);
  expect(undo, findsOneWidget, reason: 'the Arranging Undo is shown');
  expect(
    tester.widget<IconButton>(undo).onPressed,
    isNotNull,
    reason: 'the drop offers one Undo',
  );
}

void _expectOneBatchOfMembers(HullDragHarness h) {
  expect(h.server.applies, hasLength(1), reason: 'one batch write');
  expect(
    h.server.applies.single
        .map((op) => op.target)
        .where((t) => t.kind == ConstellationAnchorTargetKind.person),
    unorderedEquals([
      for (final id in hullDragMembers) ConstellationAnchorTarget.person(id),
    ]),
    reason: 'the batch pins exactly the members of the tag',
  );
}

/// One Undo tap: one more write puts every anchor back as it was before the
/// move, and Undo is no longer offered for that move.
Future<void> _expectOneUndoRestores(
  WidgetTester tester,
  HullDragHarness h,
  Map<ConstellationAnchorTarget, Object?> initialAnchors, {
  required bool undoBefore,
}) async {
  await tester.tap(find.byKey(_undoKey));
  await flushHullDragWrites(tester);
  expect(h.server.applies, hasLength(2), reason: 'one Undo, one more write');
  expect(
    h.server.anchors,
    initialAnchors,
    reason: 'one Undo puts every member back at its pre-move anchor',
  );
  expect(
    h.cubit.canUndoArrangement,
    undoBefore,
    reason: 'the move is undone; Undo offers only what it offered before it',
  );
}

void _expectNoPanelOpened(HullDragHarness h) {
  expect(
    h.cubit.state.selectedPersonId,
    isNull,
    reason: 'the drop click opens no person panel',
  );
  expect(h.cubit.state.selectedRequestId, isNull);
  expect(
    find.byType(GraphPersonContextPanel),
    findsNothing,
    reason: 'no person panel is shown',
  );
}

/// The area landed where it was dropped: the handle member (the one under
/// the pointer, moving at full speed) is at [dropGlobal]; every member moved
/// from where the lift left it by the handle's travel times its weight (1, or
/// 1/k for a member of k tags); people outside the tag did not move.
void _expectDroppedAt(
  WidgetTester tester,
  HullDragHarness h,
  Map<String, Offset> lifted, {
  required String handle,
  required Offset dropGlobal,
  required String reason,
  Map<String, double> weights = const {},
}) {
  final now = _positions(h);
  final dropScene = h.cubit.graphController.globalToScene(dropGlobal)!;
  expect(
    (now[handle]! - dropScene).distance,
    lessThan(2),
    reason: '$reason: $handle is at the drop point',
  );
  final travel = now[handle]! - lifted[handle]!;
  expect(
    travel.distance,
    greaterThan(25),
    reason: '$reason: the area travelled',
  );
  for (final id in hullDragPeople) {
    final weight = hullDragMembers.contains(id) ? weights[id] ?? 1.0 : 0.0;
    expect(
      (now[id]! - lifted[id]! - travel * weight).distance,
      lessThan(1.5),
      reason: weight == 0
          ? '$reason: $id is not in the tag and stays put'
          : '$reason: $id moved with the area (weight $weight)',
    );
  }
}

void main() {
  group('the click that drops a «Move area» area only drops it', () {
    for (final arranging in [false, true]) {
      final mode = arranging ? 'in Arranging' : 'outside Arranging';
      testWidgets(
        'desktop $mode: a click on a carried member writes one batch, '
        'enables Undo and opens no person panel',
        (tester) async {
          await withHullDragField(
            tester,
            (h) async {
              final initialAnchors = {...h.server.anchors};
              final undoBefore = h.cubit.canUndoArrangement;
              final started = await _menuMoveArea(tester, h);
              expect(
                h.selection.state.arranging,
                isTrue,
                reason: 'choosing «Move area» enters Arranging',
              );
              final to = started.point + _travel;
              await _hoverAndClick(
                tester,
                started.mouse,
                started.point,
                to,
                // The handle member follows the pointer, so the click lands
                // on a member node.
                onPersons: hullDragMembers,
              );
              _expectOneBatchOfMembers(h);
              _expectUndoEnabled(tester);
              _expectNoPanelOpened(h);
              _expectDroppedAt(
                tester,
                h,
                started.lifted,
                handle: 'ann',
                dropGlobal: to,
                reason: 'after the click drop',
              );
              expect(
                h.selection.state.arranging,
                isTrue,
                reason: 'Arranging stays open after the drop',
              );
              await _expectOneUndoRestores(
                tester,
                h,
                initialAnchors,
                undoBefore: undoBefore,
              );
              expect(tester.takeException(), isNull);
            },
            arranging: arranging,
            surface: _desktop,
          );
        },
      );
    }

    testWidgets(
      'desktop outside Arranging: dropping the area onto a non-member writes '
      'one batch of members and opens no panel for that person',
      (tester) async {
        await withHullDragField(
          tester,
          (h) async {
            final initialAnchors = {...h.server.anchors};
            final undoBefore = h.cubit.canUndoArrangement;
            final eve = tester.getCenter(_node('eve'));
            final started = await _menuMoveArea(tester, h);
            await _hoverAndClick(
              tester,
              started.mouse,
              started.point,
              eve,
              onPersons: const ['eve'],
            );
            _expectOneBatchOfMembers(h);
            _expectUndoEnabled(tester);
            _expectNoPanelOpened(h);
            // Eve is checked to stay put among the people outside the tag.
            _expectDroppedAt(
              tester,
              h,
              started.lifted,
              handle: 'ann',
              dropGlobal: eve,
              reason: 'after the drop onto Eve',
            );
            await _expectOneUndoRestores(
              tester,
              h,
              initialAnchors,
              undoBefore: undoBefore,
            );
            expect(tester.takeException(), isNull);
          },
          arranging: false,
          surface: _desktop,
        );
      },
    );

    testWidgets(
      'desktop outside Arranging, a member shared with another tag: the '
      'left click drops one batch of every member and enables Undo',
      (tester) async {
        await withHullDragField(
          tester,
          (h) async {
            final initialAnchors = {...h.server.anchors};
            final undoBefore = h.cubit.canUndoArrangement;
            // Ann is also in a second tag, so she rides at half speed.
            final started = await _menuMoveArea(
              tester,
              h,
              tagName: 'Тег tag-a',
            );
            await _hoverAndClick(
              tester,
              started.mouse,
              started.point,
              started.point + _travel,
              onPersons: hullDragMembers,
            );
            _expectOneBatchOfMembers(h);
            _expectUndoEnabled(tester);
            _expectNoPanelOpened(h);
            // Bob is the first member in this tag only: he is the handle
            // under the pointer; Ann (two tags) moves half as far.
            _expectDroppedAt(
              tester,
              h,
              started.lifted,
              handle: 'bob',
              dropGlobal: started.point + _travel,
              weights: const {'ann': 0.5},
              reason: 'after the click drop',
            );
            await _expectOneUndoRestores(
              tester,
              h,
              initialAnchors,
              undoBefore: undoBefore,
            );
            expect(tester.takeException(), isNull);
          },
          arranging: false,
          tagMembers: const {
            'tag-a': hullDragMembers,
            'tag-b': ['ann', 'eve'],
          },
          surface: _desktop,
        );
      },
    );

    testWidgets(
      '375×667 RU: the menu offers one «Переместить область» entry; a tap '
      'drops the area in one batch, enables Undo and opens no panel',
      (tester) async {
        await withHullDragField(tester, (h) async {
          final initialAnchors = {...h.server.anchors};
          final undoBefore = h.cubit.canUndoArrangement;
          final point = _emptyHullPoint(tester);
          final mouse = await tester.startGesture(
            point,
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await tester.pump();
          await mouse.up();
          await tester.pumpAndSettle();
          expect(find.text('Переместить область «Соседи»'), findsOneWidget);
          expect(find.byType(PopupMenuItem<bool>), findsOneWidget);
          await tester.tap(find.text('Переместить область «Соседи»'));
          await tester.pumpAndSettle();
          expect(h.selection.state.arranging, isTrue);
          final lifted = _positions(h);
          // A finger has no hover: the tap itself says where the area goes.
          // It lands on a person node other than the handle (Ann, already
          // under the lift point), so the area travels: a carried member
          // when one is on screen and uncovered, else a person outside it.
          final to = _tappableNodeCentre(tester, ['bob', 'cid', 'dan', 'eve']);
          await tester.tapAt(to);
          await tester.pump();
          await flushHullDragWrites(tester);
          _expectOneBatchOfMembers(h);
          _expectUndoEnabled(tester);
          _expectNoPanelOpened(h);
          _expectDroppedAt(
            tester,
            h,
            lifted,
            handle: 'ann',
            dropGlobal: to,
            reason: 'after the tap drop',
          );
          await _expectOneUndoRestores(
            tester,
            h,
            initialAnchors,
            undoBefore: undoBefore,
          );
          expect(tester.takeException(), isNull);
        }, arranging: false);
      },
    );
  });
}
