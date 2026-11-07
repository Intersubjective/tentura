import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting show debugDisableShadows;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
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
    reason: 'the fixture renders the actual filled hull for $id',
  );
  return (path: path!, box: box);
}

/// The visible fill footprint and elevation of the single-tag fixture.
/// Observes painting, including canvas and widget transforms, without
/// requiring a particular animation widget. An outline alone is not a lift.
({Rect fillBounds, bool outlined, bool castsShadow}) _hullVisual(
  WidgetTester tester,
) {
  final box = tester.renderObject<RenderBox>(
    find.byType(ConstellationTagHullLayer),
  );
  var transform = box.getTransformTo(null);
  final savedTransforms = <Matrix4>[];
  Rect? fillBounds;
  var outlined = false;
  var castsShadow = false;
  expect(
    box,
    paints..everything((method, arguments) {
      switch (method) {
        case #save || #saveLayer:
          savedTransforms.add(transform.clone());
        case #restore:
          transform = savedTransforms.removeLast();
        case #translate:
          transform.multiply(
            Matrix4.identity()..setTranslationRaw(
              (arguments[0] as num).toDouble(),
              (arguments[1] as num).toDouble(),
              0,
            ),
          );
        case #scale:
          final x = (arguments[0] as num).toDouble();
          final y = arguments.length > 1
              ? (arguments[1] as num?)?.toDouble() ?? x
              : x;
          transform.multiply(Matrix4.diagonal3Values(x, y, 1));
        case #transform:
          transform.multiply(Matrix4.fromList(arguments[0] as List<double>));
        case #rotate:
          transform.rotateZ((arguments[0] as num).toDouble());
        case #drawPath:
          final paint = arguments[1] as Paint;
          if (paint.color.a > 0 && paint.maskFilter == null) {
            if (paint.style == PaintingStyle.stroke) {
              outlined = true;
            } else {
              final bounds = (arguments[0] as Path)
                  .transform(transform.storage)
                  .getBounds();
              fillBounds = fillBounds?.expandToInclude(bounds) ?? bounds;
            }
          }
        case #drawShadow:
          castsShadow |=
              (arguments[1] as Color).a > 0 && (arguments[2] as num) > 0;
      }
      // BoxShadow paints a blurred shape rather than Canvas.drawShadow.
      if (const {
        #drawPath,
        #drawRect,
        #drawRRect,
        #drawDRRect,
        #drawCircle,
        #drawOval,
      }.contains(method)) {
        castsShadow |= arguments.whereType<Paint>().any(
          (paint) =>
              paint.style == PaintingStyle.fill &&
              paint.color.a > 0 &&
              paint.maskFilter != null,
        );
      }
      return true;
    }),
  );
  expect(fillBounds, isNotNull, reason: 'the tag has a visible painted fill');
  return (
    fillBounds: fillBounds!,
    outlined: outlined,
    castsShadow: castsShadow,
  );
}

/// The tag among [candidates] whose hull fill is painted last on the canvas,
/// i.e. the one the user sees on top where the hulls overlap.
String _topmostPaintedHull(WidgetTester tester, Set<String> candidates) {
  final bounds = {
    for (final id in candidates) id: _paintedHull(tester, id).path.getBounds(),
  };
  final fills = <Rect>[];
  expect(
    tester.renderObject<RenderBox>(find.byType(ConstellationTagHullLayer)),
    paints..everything((method, arguments) {
      if (method == #drawPath &&
          (arguments[1] as Paint).style == PaintingStyle.fill &&
          (arguments[1] as Paint).color.a > 0) {
        fills.add((arguments[0] as Path).getBounds());
      }
      return true;
    }),
  );
  for (final fill in fills.reversed) {
    for (final entry in bounds.entries) {
      if ((fill.topLeft - entry.value.topLeft).distance < 0.5 &&
          (fill.bottomRight - entry.value.bottomRight).distance < 0.5) {
        return entry.key;
      }
    }
  }
  fail('no painted hull fill matches ${candidates.join(', ')}');
}

/// Choose a point from what the user sees, away from every node, rather than
/// using the hull's rectangular bounds or calling a gesture callback.
Offset _emptyHullPoint(
  WidgetTester tester, {
  Set<String> inside = const {'tag-a'},
}) {
  final hulls = [for (final id in inside) _paintedHull(tester, id)];
  final viewport = tester.getRect(find.byType(InteractiveViewer)).deflate(40);
  final nodes = [
    for (final id in hullDragPeople) tester.getRect(_node(id)).inflate(32),
  ];
  for (var y = viewport.top + 4; y < viewport.bottom; y += 4) {
    for (var x = viewport.left + 4; x < viewport.right; x += 4) {
      final point = Offset(x, y);
      if (nodes.any((rect) => rect.contains(point))) continue;
      if (hulls.every(
        (hull) => hull.path.contains(hull.box.globalToLocal(point)),
      )) {
        return point;
      }
    }
  }
  fail(
    'fixture must contain visible empty space inside ${inside.join(' and ')}',
  );
}

Map<String, Offset> _positions(HullDragHarness h) => {
  for (final id in hullDragPeople)
    id: h.cubit.graphController.getPositionOrNullForId('fp:$id')!,
};

Matrix4 _camera(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .clone();

void _samePoint(Offset actual, Offset expected, {required String reason}) {
  expect((actual - expected).distance, lessThan(0.5), reason: reason);
}

Future<void> _move(
  WidgetTester tester,
  TestGesture gesture,
  Offset from,
) async {
  for (var i = 1; i <= 8; i++) {
    await gesture.moveTo(from + Offset(56 * i / 8, 28 * i / 8));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// The hold the acceptance criteria name: half a second, at least the
/// platform long-press timeout, before the pointer moves.
const _halfSecondHold = Duration(milliseconds: 500);

Future<TestGesture> _holdThenMove(
  WidgetTester tester,
  Offset point,
  PointerDeviceKind kind,
) async {
  // Do not use startConstellationFieldGesture: it silently enables Arranging
  // for touch and would erase half this test matrix.
  final gesture = await tester.startGesture(point, kind: kind);
  await tester.pump(_halfSecondHold);
  await _move(tester, gesture, point);
  return gesture;
}

/// Every member of the lifted tag moves by the area's offset divided by the
/// number of own tags with people on the Field that the member belongs to
/// (#1021: a person in two tags moves half way); everyone else stays put.
/// [moveFactor] maps each lifted member to that fraction.
void _expectAreaMoved(
  WidgetTester tester,
  HullDragHarness h,
  Map<String, Offset> before,
  Map<String, Offset> screenBefore,
  Map<String, double> moveFactor,
) {
  final after = _positions(h);
  final handle = moveFactor.entries.firstWhere((e) => e.value == 1).key;
  final delta = after[handle]! - before[handle]!;
  expect(
    delta.distance,
    greaterThan(25),
    reason: 'holding empty hull space must lift and move the tag, not pan',
  );
  for (final id in hullDragPeople) {
    final expected = delta * (moveFactor[id] ?? 0);
    _samePoint(
      after[id]!,
      before[id]! + expected,
      reason: moveFactor.containsKey(id)
          ? '$id follows the area by ${moveFactor[id]} of its offset'
          : '$id is not in the lifted tag and stays put',
    );
    final onScreen = tester.getCenter(_node(id)) - screenBefore[id]!;
    _samePoint(
      onScreen,
      expected,
      reason: 'the visible node for $id follows its scene position',
    );
  }
  expect(
    h.server.applies,
    isEmpty,
    reason: 'lifting writes nothing before drop',
  );
}

/// People pinned by the single drop batch (satellite Posts may ride along).
Iterable<ConstellationAnchorTarget> _pinnedPeople(HullDragHarness h) => h
    .server
    .applies
    .single
    .map((op) => op.target)
    .where((t) => t.kind == ConstellationAnchorTargetKind.person);

final _singleTagMembers = {for (final id in hullDragMembers) id: 1.0};

/// Taps the Undo the user sees right after the drop, in whichever mode the
/// drop happened: the Arranging toolbar's Undo or an Undo snack bar action.
/// Never turns Arranging on itself, so outside Arranging an Undo must be
/// offered without the user first switching modes.
Future<void> _undoAfterDrop(WidgetTester tester, HullDragHarness h) async {
  final l10n = L10n.of(tester.element(find.byType(ConstellationBody)))!;
  expect(l10n.constellationUndo, isNot(contains('Undo')));
  final toolbarUndo = find.byKey(const Key('constellation.arranging.undo'));
  final snackUndo = find.byWidgetPredicate(
    (widget) =>
        widget is SnackBarAction &&
        (widget.label == l10n.constellationUndo ||
            widget.label == l10n.peopleTagsUndo),
  );
  final toolbarEnabled =
      toolbarUndo.evaluate().isNotEmpty &&
      tester.widget<IconButton>(toolbarUndo).onPressed != null;
  expect(
    toolbarEnabled || snackUndo.evaluate().isNotEmpty,
    isTrue,
    reason:
        'an Undo is offered right after the drop '
        '(arranging=${h.selection.state.arranging}, '
        'canUndo=${h.cubit.canUndoArrangement}, '
        'phase=${h.cubit.state.placementPhase})',
  );
  await tester.tap(toolbarEnabled ? toolbarUndo : snackUndo.first);
  await flushHullDragWrites(tester);
}

Future<void> _undoViaKeyboard(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await flushHullDragWrites(tester);
}

Map<String, Offset> _screenPositions(WidgetTester tester) => {
  for (final id in hullDragPeople) id: tester.getCenter(_node(id)),
};

/// What a screen reader announces for the tag hull of [tagId]: the text of
/// every semantics node that mentions [tagName] and sits on the hull's
/// visible area, with the tag name itself removed (user data, not copy).
/// People nodes (and their larger tap targets) are skipped: their own labels
/// already list their tags.
List<String> _hullAnnouncements(
  WidgetTester tester, {
  required String tagId,
  required String tagName,
}) {
  final hull = _paintedHull(tester, tagId);
  final hullOnScreen = MatrixUtils.transformRect(
    hull.box.getTransformTo(null),
    hull.path.getBounds(),
  );
  final dpr = tester.view.devicePixelRatio;
  final people = [
    for (final id in hullDragPeople) tester.getRect(_node(id)).inflate(8),
  ];
  final found = <String>[];
  void visit(SemanticsNode node, Matrix4 parent) {
    final transform = node.transform == null
        ? parent
        : (parent.clone()..multiply(node.transform!));
    final physical = MatrixUtils.transformRect(transform, node.rect);
    final logical = Rect.fromLTRB(
      physical.left / dpr,
      physical.top / dpr,
      physical.right / dpr,
      physical.bottom / dpr,
    );
    final data = node.getSemanticsData();
    final text = <String>[
      data.label,
      data.value,
      data.hint,
      data.tooltip,
    ].where((t) => t.isNotEmpty).join(' ');
    final onPerson = people.any(
      (rect) =>
          rect.contains(logical.topLeft) && rect.contains(logical.bottomRight),
    );
    if (text.contains(tagName) &&
        !onPerson &&
        hullOnScreen.contains(logical.center)) {
      found.add(text.replaceAll(tagName, '').trim());
    }
    node.visitChildren((child) {
      visit(child, transform);
      return true;
    });
  }

  final root =
      tester.binding.renderViews.first.owner!.semanticsOwner?.rootSemanticsNode;
  expect(root, isNotNull, reason: 'semantics are enabled for this test');
  visit(root!, Matrix4.identity());
  return found;
}

final _latin = RegExp('[A-Za-z]');
final _cyrillic = RegExp('[А-Яа-яЁё]');

void main() {
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    for (final arranging in [false, true]) {
      final mode = arranging ? 'while Arranging' : 'outside Arranging';
      final input = '${kind.name} $mode at 375x667 in Russian';

      group('tag hull group dragging', () {
        testWidgets('$input: quick empty-space drag pans, then a half-second '
            'hold moves all members, drops their pins and one Undo restores', (
          tester,
        ) async {
          await withHullDragField(tester, (h) async {
            final initialAnchors = {...h.server.anchors};
            expect(
              h.cubit.isAnchored(ConstellationAnchorTarget.person('cid')),
              isFalse,
              reason:
                  'the drop must create a pin for the initially free member',
            );
            final point = _emptyHullPoint(tester);
            final beforePan = _positions(h);
            final cameraBeforePan = _camera(tester);
            final pan = await tester.startGesture(point, kind: kind);
            await _move(tester, pan, point);
            // Once the initial movement has crossed gesture slop, the map
            // must track the next pointer step at the fixture's 1:1 scale.
            // Measure before release so fling settling cannot affect it.
            final screenWhilePanning = _screenPositions(tester);
            final cameraWhilePanning = _camera(tester);
            const panStep = Offset(20, 10);
            await pan.moveBy(panStep);
            await tester.pump(const Duration(milliseconds: 16));
            final cameraAfterStep = _camera(tester);
            _samePoint(
              MatrixUtils.transformPoint(cameraAfterStep, Offset.zero) -
                  MatrixUtils.transformPoint(cameraWhilePanning, Offset.zero),
              panStep,
              reason: 'the camera follows the pointer direction and distance',
            );
            for (final id in hullDragPeople) {
              _samePoint(
                tester.getCenter(_node(id)) - screenWhilePanning[id]!,
                panStep,
                reason: 'a quick pan visibly moves $id with the pointer',
              );
            }
            await pan.up();
            await flushHullDragWrites(tester);
            expect(
              _camera(tester),
              isNot(cameraBeforePan),
              reason: 'quick drag pans',
            );
            expect(
              h.server.applies,
              isEmpty,
              reason: 'panning saves no anchors',
            );
            for (final id in hullDragPeople) {
              _samePoint(
                _positions(h)[id]!,
                beforePan[id]!,
                reason: '$id is not dragged',
              );
            }
            expect(h.selection.state.arranging, arranging);

            final before = _positions(h);
            final screenBefore = _screenPositions(tester);
            final cameraBefore = _camera(tester);
            final grab = _emptyHullPoint(tester);
            final gesture = await _holdThenMove(tester, grab, kind);
            expect(
              h.server.anchors,
              initialAnchors,
              reason: 'stored pins stay unchanged until the pointer releases',
            );
            _expectAreaMoved(
              tester,
              h,
              before,
              screenBefore,
              _singleTagMembers,
            );
            expect(
              _camera(tester),
              cameraBefore,
              reason: 'the held hull does not pan',
            );
            await gesture.up();
            await flushHullDragWrites(tester);

            expect(h.server.applies, hasLength(1), reason: 'one group drop');
            expect(
              _pinnedPeople(h),
              unorderedEquals([
                for (final id in hullDragMembers)
                  ConstellationAnchorTarget.person(id),
              ]),
            );
            final moved = _positions(h);
            for (final id in hullDragMembers) {
              final target = ConstellationAnchorTarget.person(id);
              expect(
                h.cubit.isAnchored(target),
                isTrue,
                reason: '$id is pinned on release',
              );
              final saved = h.server.anchors[target]!;
              _samePoint(
                Offset(
                  kConstellationCanvasCentre +
                      saved.xUnits * kConstellationRingUnitPixels,
                  kConstellationCanvasCentre +
                      saved.yUnits * kConstellationRingUnitPixels,
                ),
                moved[id]!,
                reason: '$id persists at the visible drop position',
              );
            }

            expect(
              h.selection.state.arranging || !arranging,
              isTrue,
              reason: 'a drop inside Arranging stays in Arranging',
            );
            await _undoAfterDrop(tester, h);
            expect(
              h.server.applies,
              hasLength(2),
              reason: 'one Undo restores the whole group',
            );
            expect(h.server.anchors, initialAnchors);
            for (final id in hullDragPeople) {
              _samePoint(
                _positions(h)[id]!,
                before[id]!,
                reason: 'Undo restores $id on the map',
              );
            }
            expect(tester.takeException(), isNull);
          }, arranging: arranging);
        });
      });

      group('node and hull long presses choose different drag targets', () {
        testWidgets('$input: a node hold moves only that person, and an '
            'empty-hull hold moves the whole tag', (tester) async {
          await withHullDragField(tester, (h) async {
            final beforeNode = _positions(h);
            final nodePoint = tester.getCenter(_node('ann'));
            final nodeGesture = await _holdThenMove(tester, nodePoint, kind);
            final nodeDelta = _positions(h)['ann']! - beforeNode['ann']!;
            expect(
              nodeDelta.distance,
              greaterThan(25),
              reason: 'holding a node inside the hull lifts that node',
            );
            for (final id in hullDragPeople.where((id) => id != 'ann')) {
              _samePoint(
                _positions(h)[id]!,
                beforeNode[id]!,
                reason: 'a node hold leaves $id alone, not the whole tag',
              );
            }
            await nodeGesture.up();
            await flushHullDragWrites(tester);
            expect(h.server.applies, hasLength(1));
            expect(_pinnedPeople(h), [
              ConstellationAnchorTarget.person('ann'),
            ]);
            await _undoViaKeyboard(tester);
            expect(h.server.applies, hasLength(2));
            _samePoint(
              _positions(h)['ann']!,
              beforeNode['ann']!,
              reason: 'keyboard Undo resets the node before testing the hull',
            );
            h.server.applies.clear();
            if (!arranging) h.selection.exitArranging();
            await pumpHullDragFrames(tester);
            expect(h.selection.state.arranging, arranging);

            final before = _positions(h);
            final screenBefore = _screenPositions(tester);
            final grab = _emptyHullPoint(tester);
            final groupGesture = await _holdThenMove(tester, grab, kind);
            _expectAreaMoved(
              tester,
              h,
              before,
              screenBefore,
              _singleTagMembers,
            );
            await groupGesture.up();
            await flushHullDragWrites(tester);
            expect(h.server.applies, hasLength(1));
            expect(
              _pinnedPeople(h),
              unorderedEquals([
                for (final id in hullDragMembers)
                  ConstellationAnchorTarget.person(id),
              ]),
            );
            expect(tester.takeException(), isNull);
          }, arranging: arranging);
        });
      });

      group('overlapping tag hulls respect visible paint order', () {
        testWidgets('$input: holding the overlap lifts only the '
            'visually topmost tag', (
          tester,
        ) async {
          await withHullDragField(
            tester,
            (h) async {
              final topmost = _topmostPaintedHull(tester, {'tag-a', 'tag-b'});
              // Ann and Bob are in both tags, so they move half way;
              // Cid and Dan are each in one tag and move with the area.
              final members = {
                'tag-a': {'ann': 0.5, 'bob': 0.5, 'cid': 1.0},
                'tag-b': {'ann': 0.5, 'bob': 0.5, 'dan': 1.0},
              }[topmost]!;
              final grab = _emptyHullPoint(
                tester,
                inside: {'tag-a', 'tag-b'},
              );
              final before = _positions(h);
              final screenBefore = _screenPositions(tester);
              final gesture = await _holdThenMove(tester, grab, kind);
              _expectAreaMoved(tester, h, before, screenBefore, members);
              await gesture.up();
              await flushHullDragWrites(tester);
              expect(h.server.applies, hasLength(1));
              expect(
                _pinnedPeople(h),
                unorderedEquals([
                  for (final id in members.keys)
                    ConstellationAnchorTarget.person(id),
                ]),
              );
              expect(tester.takeException(), isNull);
            },
            arranging: arranging,
            overlapping: true,
          );
        });
      });

      group('held tag hull feedback', () {
        testWidgets('$input: a held tag visibly lifts or scales before '
            'movement and loses the lift when cancelled', (tester) async {
          final disabledShadows = painting.debugDisableShadows;
          painting.debugDisableShadows = false;
          try {
            await withHullDragField(tester, (h) async {
              final before = _hullVisual(tester);
              final positions = _positions(h);
              final initialAnchors = {...h.server.anchors};
              final camera = _camera(tester);
              final grab = _emptyHullPoint(tester);
              final gesture = await tester.startGesture(grab, kind: kind);
              await tester.pump(
                kLongPressTimeout - const Duration(milliseconds: 1),
              );
              expect(
                _hullVisual(tester),
                before,
                reason: 'a short press has not lifted the tag',
              );
              await tester.pump(const Duration(milliseconds: 1));
              await tester.pump(const Duration(milliseconds: 200));
              await tester.pump(const Duration(milliseconds: 200));
              final held = _hullVisual(tester);
              expect(
                held.fillBounds.width > before.fillBounds.width + 0.5 ||
                    held.fillBounds.height > before.fillBounds.height + 0.5 ||
                    held.fillBounds.top < before.fillBounds.top - 0.5 ||
                    (!before.castsShadow && held.castsShadow),
                isTrue,
                reason:
                    'the held tag visibly lifts or scales; an outline alone '
                    'does not provide the lift cue',
              );
              expect(
                _camera(tester),
                camera,
                reason: 'the visual cue comes from the tag, not camera motion',
              );
              for (final id in hullDragPeople) {
                _samePoint(
                  _positions(h)[id]!,
                  positions[id]!,
                  reason: 'the lift cue leaves $id at its scene position',
                );
              }
              expect(h.server.applies, isEmpty);
              expect(h.server.anchors, initialAnchors);
              await gesture.cancel();
              await pumpHullDragFrames(tester);
              expect(
                _hullVisual(tester),
                before,
                reason: 'cancelling lowers the tag to its resting appearance',
              );
              expect(tester.takeException(), isNull);
            }, arranging: arranging);
          } finally {
            painting.debugDisableShadows = disabledShadows;
          }
        });

        testWidgets(
          kind == PointerDeviceKind.touch
              ? '$input: lifting empty hull space requests haptic feedback '
                    'at the long-press deadline'
              : '$input: lifting empty hull space with a mouse requests no '
                    'haptic feedback',
          (tester) async {
            final haptics = <Object?>[];
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              (call) async {
                if (call.method == 'HapticFeedback.vibrate') {
                  haptics.add(call.arguments);
                }
                return null;
              },
            );
            addTearDown(() {
              tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                SystemChannels.platform,
                null,
              );
            });
            await withHullDragField(tester, (h) async {
              haptics.clear();
              final grab = _emptyHullPoint(tester);
              final gesture = await tester.startGesture(grab, kind: kind);
              await tester.pump(
                kLongPressTimeout - const Duration(milliseconds: 1),
              );
              expect(haptics, isEmpty, reason: 'a short press has not lifted');
              await tester.pump(const Duration(milliseconds: 1));
              await tester.pump(const Duration(milliseconds: 16));
              expect(
                _hullVisual(tester).outlined,
                isTrue,
                reason: 'the hold lifted the hull (it is highlighted)',
              );
              if (kind == PointerDeviceKind.touch) {
                expect(
                  haptics,
                  isNotEmpty,
                  reason: 'a touch hull lift requests platform haptic feedback',
                );
              } else {
                expect(
                  haptics,
                  isEmpty,
                  reason: 'a mouse has no haptics; the lift must not ask',
                );
              }
              expect(h.server.applies, isEmpty);
              await gesture.cancel();
              await pumpHullDragFrames(tester);
              expect(tester.takeException(), isNull);
            }, arranging: arranging);
          },
        );

        testWidgets('$input: an unselected hull gains an outline after the '
            'long-press deadline without moving its members or writing', (
          tester,
        ) async {
          await withHullDragField(tester, (h) async {
            final before = _positions(h);
            final initialAnchors = {...h.server.anchors};
            expect(
              _hullVisual(tester).outlined,
              isFalse,
              reason: 'an unselected resting hull has no outline',
            );
            final grab = _emptyHullPoint(tester);
            final gesture = await tester.startGesture(grab, kind: kind);
            await tester.pump(
              kLongPressTimeout - const Duration(milliseconds: 1),
            );
            expect(h.server.applies, isEmpty);
            expect(h.lens.state.selectedOwn, isEmpty);
            expect(
              _hullVisual(tester).outlined,
              isFalse,
              reason: 'a short press must not highlight the hull early',
            );
            await tester.pump(const Duration(milliseconds: 1));
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              _hullVisual(tester).outlined,
              isTrue,
              reason: 'the held hull visibly highlights at kLongPressTimeout',
            );
            for (final id in hullDragPeople) {
              _samePoint(
                _positions(h)[id]!,
                before[id]!,
                reason: 'a stationary hold does not move $id',
              );
            }
            expect(h.server.applies, isEmpty);
            await gesture.up();
            await flushHullDragWrites(tester);
            expect(
              h.server.applies,
              isEmpty,
              reason: 'releasing a hold that never moved saves nothing',
            );
            expect(
              h.server.anchors,
              initialAnchors,
              reason: 'no pin is added or moved by a stationary hold',
            );
            for (final id in hullDragPeople) {
              _samePoint(
                _positions(h)[id]!,
                before[id]!,
                reason: 'releasing a stationary hold leaves $id in place',
              );
            }
            expect(tester.takeException(), isNull);
          }, arranging: arranging);
        });
      });
    }
  }

  group('tag hull accessibility copy', () {
    testWidgets('in Russian a tag hull tells screen readers its tag and how '
        'to move it by press and hold, with no English', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await withHullDragField(tester, (h) async {
          final l10n = L10n.of(tester.element(find.byType(ConstellationBody)))!;
          expect(l10n.localeName, startsWith('ru'));
          final announced = _hullAnnouncements(
            tester,
            tagId: 'tag-a',
            tagName: 'Соседи',
          ).where(_cyrillic.hasMatch).toList();
          expect(
            announced,
            isNotEmpty,
            reason:
                'the hull of «Соседи» announces the tag and a Russian hint '
                'that it can be moved by press and hold',
          );
          for (final text in announced) {
            expect(
              _latin.hasMatch(text),
              isFalse,
              reason:
                  'Russian hull semantics must not contain English: '
                  '«$text»',
            );
          }
          expect(tester.takeException(), isNull);
        }, arranging: false);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('in English a tag hull tells screen readers its tag and how '
        'to move it by press and hold', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await withHullDragField(
          tester,
          (h) async {
            final l10n = L10n.of(
              tester.element(find.byType(ConstellationBody)),
            )!;
            expect(l10n.localeName, startsWith('en'));
            final announced = _hullAnnouncements(
              tester,
              tagId: 'tag-a',
              tagName: 'Соседи',
            ).where(_latin.hasMatch).toList();
            expect(
              announced,
              isNotEmpty,
              reason:
                  'the hull of «Соседи» announces the tag and an English '
                  'hint that it can be moved by press and hold',
            );
            for (final text in announced) {
              expect(
                _cyrillic.hasMatch(text),
                isFalse,
                reason: 'English hull copy is not left in Russian: «$text»',
              );
            }
            expect(tester.takeException(), isNull);
          },
          arranging: false,
          locale: const Locale('en'),
        );
      } finally {
        semantics.dispose();
      }
    });
  });
}
