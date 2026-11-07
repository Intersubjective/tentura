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

Finder _node(String id) => find.byKey(TestIds.key(TestIds.graphNode(id)));

Finder _hull(String id) => find.byKey(ConstellationTagHullLayer.hullKey(id));

({Path path, RenderBox box}) _paintedHull(WidgetTester tester, String id) {
  Path? path;
  final box = tester.renderObject<RenderBox>(_hull(id));
  expect(
    box,
    paints..something((method, arguments) {
      if (method != #drawPath) return false;
      if ((arguments[1] as Paint).style != PaintingStyle.fill) return false;
      path = arguments[0] as Path;
      return true;
    }),
    reason: 'the fixture renders the filled hull for $id',
  );
  return (path: path!, box: box);
}

Offset _emptyHullPoint(WidgetTester tester) {
  final hull = _paintedHull(tester, 'tag-a');
  final viewport = tester.getRect(find.byType(InteractiveViewer)).deflate(40);
  final nodes = [
    for (final id in hullDragPeople) tester.getRect(_node(id)).inflate(32),
  ];
  for (var y = viewport.top + 4; y < viewport.bottom; y += 4) {
    for (var x = viewport.left + 4; x < viewport.right; x += 4) {
      final point = Offset(x, y);
      if (nodes.any((rect) => rect.contains(point))) continue;
      if (hull.path.contains(hull.box.globalToLocal(point))) return point;
    }
  }
  fail('fixture must contain visible empty space inside tag-a');
}

Future<void> _secondaryTapAt(WidgetTester tester, Offset global) async {
  final gesture = await tester.startGesture(
    global,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Map<String, Offset> _positions(HullDragHarness h) => {
  for (final id in hullDragPeople)
    id: h.cubit.graphController.getPositionOrNullForId('fp:$id')!,
};

void _samePoint(Offset actual, Offset expected, {required String reason}) {
  expect((actual - expected).distance, lessThan(1), reason: reason);
}

Future<void> _mouseDragBy(
  WidgetTester tester,
  Offset from,
  Offset to,
) async {
  await tester.sendEventToBinding(
    PointerDownEvent(position: from, kind: PointerDeviceKind.mouse),
  );
  await tester.pump();
  const steps = 8;
  final delta = to - from;
  for (var i = 1; i <= steps; i++) {
    final pos = from + delta * (i / steps);
    await tester.sendEventToBinding(
      PointerMoveEvent(position: pos, kind: PointerDeviceKind.mouse),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.sendEventToBinding(
    PointerUpEvent(position: to, kind: PointerDeviceKind.mouse),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'RU 375×667 mouse: secondary tap in tag hull opens move-area menu, '
    'hover moves members, click drops one batch with Undo; Esc cancels',
    (tester) async {
      await withHullDragField(tester, (h) async {
        final l10n = L10n.of(tester.element(find.byType(ConstellationBody)))!;
        final menuLabel = l10n.constellationTagHullMoveArea('Соседи');
        expect(
          l10n.constellationTagHullMoveArea('Соседи'),
          'Переместить область «Соседи»',
        );

        final before = _positions(h);
        final initialAnchors = {...h.server.anchors};
        final point = _emptyHullPoint(tester);
        await _secondaryTapAt(tester, point);
        expect(find.text(menuLabel), findsOneWidget);
        await tester.tap(find.text(menuLabel));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<ConstellationTagHullLayer>(
                find.byType(ConstellationTagHullLayer),
              )
              .liftedTagId,
          'tag-a',
        );

        const travel = Offset(56, 28);
        await _mouseDragBy(tester, point, point + travel);
        for (final id in hullDragMembers) {
          expect(
            (_positions(h)[id]! - before[id]!).distance,
            greaterThan(25),
            reason: '$id follows the pointer through menu drag',
          );
        }

        await flushHullDragWrites(tester);

        expect(h.server.applies, hasLength(1), reason: 'one group drop');
        expect(
          h.server.applies.single
              .map((op) => op.target)
              .where((t) => t.kind == ConstellationAnchorTargetKind.person),
          unorderedEquals([
            for (final id in hullDragMembers)
              ConstellationAnchorTarget.person(id),
          ]),
        );

        final toolbarUndo = find.byKey(
          const Key('constellation.arranging.undo'),
        );
        final snackUndo = find.byWidgetPredicate(
          (w) =>
              w is SnackBarAction &&
              (w.label == l10n.constellationUndo ||
                  w.label == l10n.peopleTagsUndo),
        );
        final toolbarEnabled =
            toolbarUndo.evaluate().isNotEmpty &&
            tester.widget<IconButton>(toolbarUndo).onPressed != null;
        expect(
          toolbarEnabled || snackUndo.evaluate().isNotEmpty,
          isTrue,
          reason: 'Undo is offered after the group drop',
        );
        await tester.tap(toolbarEnabled ? toolbarUndo : snackUndo.first);
        await flushHullDragWrites(tester);
        expect(h.server.applies, hasLength(2));
        expect(h.server.anchors, initialAnchors);

        // Esc during menu-follow cancels with no write.
        await _secondaryTapAt(tester, point);
        await tester.tap(find.text(menuLabel));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await flushHullDragWrites(tester);
        expect(h.server.applies, hasLength(2), reason: 'Esc does not write');
        for (final id in hullDragPeople) {
          _samePoint(
            _positions(h)[id]!,
            before[id]!,
            reason: 'Esc restores $id in place',
          );
        }
        expect(tester.takeException(), isNull);
      }, arranging: false);
    },
  );

  testWidgets(
    'RU phone: secondary tap on a person node does not open the hull move menu',
    (tester) async {
      await withHullDragField(tester, (h) async {
        final l10n = L10n.of(tester.element(find.byType(ConstellationBody)))!;
        await _secondaryTapAt(tester, tester.getCenter(_node('ann')));
        expect(
          find.text(l10n.constellationTagHullMoveArea('Соседи')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }, arranging: false);
    },
  );
}
