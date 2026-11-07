import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_hull_layer.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_tag_hull_drag_harness.dart';

// What these tests pin down, in user terms:
//  * A press and hold on empty hull space that cannot grab anything must not
//    leave the tag lifted or the Field stuck in a tag-area drag.
//  * Dragging a tag whose members all also belong to another tag moves every
//    member by the same share of the drag, whichever member the pointer
//    carries.

Finder _node(String id) => find.byKey(TestIds.key(TestIds.graphNode(id)));

Finder _hull(String id) => find.byKey(ConstellationTagHullLayer.hullKey(id));

/// A point the user sees as empty space inside the hull of [tagId].
Offset _emptyHullPoint(
  WidgetTester tester,
  String tagId, {
  List<String> outside = const [],
}) {
  final others = [
    for (final id in outside)
      (
        box: tester.renderObject<RenderBox>(_hull(id)),
        path: _paintedPath(tester, id),
      ),
  ];
  final box = tester.renderObject<RenderBox>(_hull(tagId));
  Path? path;
  expect(
    box,
    paints..something((method, arguments) {
      if (method != #drawPath) return false;
      if ((arguments[1] as Paint).style != PaintingStyle.fill) return false;
      path = arguments[0] as Path;
      return true;
    }),
    reason: 'the Field paints the hull of $tagId',
  );
  final viewport = tester.getRect(find.byType(InteractiveViewer)).deflate(40);
  final nodes = [
    for (final id in hullDragPeople) tester.getRect(_node(id)).inflate(32),
  ];
  for (var y = viewport.top + 4; y < viewport.bottom; y += 4) {
    for (var x = viewport.left + 4; x < viewport.right; x += 4) {
      final point = Offset(x, y);
      if (nodes.any((rect) => rect.contains(point))) continue;
      if (others.any((o) => o.path.contains(o.box.globalToLocal(point)))) {
        continue;
      }
      if (path!.contains(box.globalToLocal(point))) return point;
    }
  }
  fail('the hull of $tagId must contain visible empty space');
}

Path _paintedPath(WidgetTester tester, String tagId) {
  Path? path;
  expect(
    tester.renderObject<RenderBox>(_hull(tagId)),
    paints..something((method, arguments) {
      if (method != #drawPath) return false;
      if ((arguments[1] as Paint).style != PaintingStyle.fill) return false;
      path = arguments[0] as Path;
      return true;
    }),
    reason: 'the Field paints the hull of $tagId',
  );
  return path!;
}

/// Where the user sees the filled hull of [tagId] (scene space; the camera is
/// 1:1 in the fixture), read from what the Field paints.
Rect _hullBounds(WidgetTester tester, String tagId) {
  Path? path;
  expect(
    tester.renderObject<RenderBox>(_hull(tagId)),
    paints..something((method, arguments) {
      if (method != #drawPath) return false;
      if ((arguments[1] as Paint).style != PaintingStyle.fill) return false;
      path = arguments[0] as Path;
      return true;
    }),
    reason: 'the Field paints the hull of $tagId',
  );
  return path!.getBounds();
}

Map<String, Offset> _scenePositions(HullDragHarness h) => {
  for (final id in hullDragPeople)
    id: h.cubit.graphController.getPositionOrNullForId('fp:$id')!,
};

void _samePoint(Offset actual, Offset expected, {required String reason}) {
  expect((actual - expected).distance, lessThan(1), reason: reason);
}

/// The pointer's total travel after the hold, in screen pixels (1:1 camera).
const _dragTravel = Offset(56, 28);

Future<void> _moveBy(
  WidgetTester tester,
  TestGesture gesture,
  Offset from,
) async {
  for (var i = 1; i <= 8; i++) {
    await gesture.moveTo(from + _dragTravel * (i / 8));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<TestGesture> _holdThenDrag(
  WidgetTester tester,
  Offset point,
  PointerDeviceKind kind,
) async {
  final gesture = await tester.startGesture(point, kind: kind);
  await tester.pump(const Duration(milliseconds: 500));
  await _moveBy(tester, gesture, point);
  return gesture;
}

String? _liftedTag(WidgetTester tester) => tester
    .widget<ConstellationTagHullLayer>(find.byType(ConstellationTagHullLayer))
    .liftedTagId;

void _expectNoTagAreaDrag(WidgetTester tester, HullDragHarness h) {
  expect(
    h.cubit.state.placementPhase,
    ConstellationPlacementPhase.idle,
    reason: 'no tag-area drag stays active in the Field',
  );
  expect(h.cubit.state.activePlacementTarget, isNull);
  expect(_liftedTag(tester), isNull, reason: 'no hull is shown as lifted');
  final interaction = h.scene.interaction;
  expect(
    interaction.draggingNodeId,
    isNull,
    reason: 'nothing is being dragged',
  );
  expect(
    interaction.groupMemberGraphIds,
    isEmpty,
    reason: 'no tag member is still lifted with the dragged node',
  );
  expect(interaction.placementClusterGraphIds, isEmpty);
  expect(interaction.groupMemberWeights, isEmpty);
  expect(interaction.tagAreaMagnetTagId, isNull);
  expect(interaction.tagAreaMagnetStartScene, isNull);
}

/// Abe is in tag-a but the map draws no node for him; as the tag's first
/// member he becomes the handle of the lift, which then cannot be grabbed.
const _failedGrabMembers = {
  'tag-a': ['abe', 'ann', 'bob', 'cid'],
};

/// Asserts the fixture: Abe has no node on the map (a contact-only person),
/// yet the lift names him as the tag's handle, so the gesture layer cannot
/// resolve a position to grab: the grab fails after the app started the tag
/// drag, with no node drag start, end or cancel.
void _expectUngrabbableHandle(HullDragHarness h) {
  expect(
    h.cubit.graphController.renderSnapshot.resolvePosition('fp:abe'),
    isNull,
    reason: 'fixture: the handle has no position to grab it at',
  );
}

void main() {
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    group('a ${kind.name} hold on a hull whose grab does not complete', () {
      for (final ending in ['release', 'pointer cancel']) {
        testWidgets('ends with $ending: leaves no tag-area drag active and no '
            'hull lifted', (tester) async {
          await withHullDragField(
            tester,
            (h) async {
              _expectUngrabbableHandle(h);
              final before = _scenePositions(h);
              final initialAnchors = {...h.server.anchors};
              final point = _emptyHullPoint(tester, 'tag-a');
              final gesture = await tester.startGesture(point, kind: kind);
              await tester.pump(const Duration(milliseconds: 500));
              if (ending == 'release') {
                await gesture.up();
              } else {
                await gesture.cancel();
              }
              await flushHullDragWrites(tester);

              _expectNoTagAreaDrag(tester, h);
              for (final id in hullDragPeople) {
                _samePoint(
                  _scenePositions(h)[id]!,
                  before[id]!,
                  reason: '$id is where it was',
                );
              }
              expect(h.server.applies, isEmpty);
              expect(h.server.anchors, initialAnchors);
              expect(tester.takeException(), isNull);
            },
            arranging: false,
            tagMembers: _failedGrabMembers,
            unreachablePeerIds: const ['abe'],
            keepWireOpen: true,
          );
        });
      }

      testWidgets('a new hold-and-drag on the same hull still moves the whole '
          'tag and clears the drag on release', (tester) async {
        // The grab fails while an unplaced person is listed in the tag; the
        // person then leaves the tag and the user holds the hull again.
        final members = <String, List<String>>{
          'tag-a': ['abe', 'ann', 'bob', 'cid'],
        };
        await withHullDragField(
          tester,
          (h) async {
            _expectUngrabbableHandle(h);
            final failed = await tester.startGesture(
              _emptyHullPoint(tester, 'tag-a'),
              kind: kind,
            );
            await tester.pump(const Duration(milliseconds: 500));
            await failed.up();
            await flushHullDragWrites(tester);
            _expectNoTagAreaDrag(tester, h);

            members['tag-a'] = ['ann', 'bob', 'cid'];
            await tester.runAsync(() => GetIt.I<PeopleTagsCase>().load());
            await pumpHullDragFrames(tester);

            final before = _scenePositions(h);
            final point = _emptyHullPoint(tester, 'tag-a');
            final gesture = await _holdThenDrag(tester, point, kind);
            for (final id in hullDragMembers) {
              _samePoint(
                _scenePositions(h)[id]! - before[id]!,
                _dragTravel,
                reason: '$id moves with the tag by the full pointer travel',
              );
            }
            for (final id in ['dan', 'eve']) {
              _samePoint(
                _scenePositions(h)[id]!,
                before[id]!,
                reason: '$id is not in the tag and stays put',
              );
            }
            await gesture.up();
            await flushHullDragWrites(tester);

            _expectNoTagAreaDrag(tester, h);
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
            expect(tester.takeException(), isNull);
          },
          arranging: false,
          tagMembers: members,
          unreachablePeerIds: const ['abe'],
          keepWireOpen: true,
        );
      });

      testWidgets('leaves later single-person drags moving only that person', (
        tester,
      ) async {
        await withHullDragField(
          tester,
          (h) async {
            _expectUngrabbableHandle(h);
            final failed = await tester.startGesture(
              _emptyHullPoint(tester, 'tag-a'),
              kind: kind,
            );
            await tester.pump(const Duration(milliseconds: 500));
            await failed.up();
            await flushHullDragWrites(tester);

            final before = _scenePositions(h);
            final nodeGesture = await _holdThenDrag(
              tester,
              tester.getCenter(_node('ann')),
              kind,
            );
            final annDelta = _scenePositions(h)['ann']! - before['ann']!;
            expect(
              annDelta.distance,
              greaterThan(25),
              reason: 'the held person follows the pointer',
            );
            for (final id in hullDragPeople.where((id) => id != 'ann')) {
              _samePoint(
                _scenePositions(h)[id]!,
                before[id]!,
                reason: '$id does not follow Ann after the earlier failed hold',
              );
            }
            await nodeGesture.up();
            await flushHullDragWrites(tester);

            expect(h.server.applies, hasLength(1));
            expect(
              h.server.applies.single
                  .map((op) => op.target)
                  .where((t) => t.kind == ConstellationAnchorTargetKind.person),
              [ConstellationAnchorTarget.person('ann')],
              reason: 'only Ann is saved, not the tag members',
            );
            expect(tester.takeException(), isNull);
          },
          arranging: false,
          tagMembers: _failedGrabMembers,
          unreachablePeerIds: const ['abe'],
          keepWireOpen: true,
        );
      });
    });

    group('dragging a tag whose members all belong to two tags '
        '(${kind.name})', () {
      // Each member is in both tags, so each follows half of the drag; the
      // person the pointer carries is not special.
      final memberSets = {
        'the pointer carries the alphabetically first member': const [
          'ann',
          'bob',
          'cid',
        ],
        'the pointer carries a different member': const ['bob', 'dan', 'eve'],
      };
      for (final entry in memberSets.entries) {
        testWidgets('${entry.key}: every member moves half of the pointer '
            'travel', (tester) async {
          await withHullDragField(
            tester,
            (h) async {
              final before = _scenePositions(h);
              final hullBefore = _hullBounds(tester, 'tag-a');
              final point = _emptyHullPoint(tester, 'tag-a');
              final gesture = await _holdThenDrag(tester, point, kind);

              for (final id in hullDragPeople) {
                final expected = entry.value.contains(id)
                    ? _dragTravel * 0.5
                    : Offset.zero;
                _samePoint(
                  _scenePositions(h)[id]! - before[id]!,
                  expected,
                  reason: entry.value.contains(id)
                      ? '$id is in both tags and follows half of the drag'
                      : '$id is not in the tag and stays put',
                );
              }
              await gesture.up();
              await flushHullDragWrites(tester);
              _expectNoTagAreaDrag(tester, h);
              _samePoint(
                _hullBounds(tester, 'tag-a').center - hullBefore.center,
                _dragTravel * 0.5,
                reason: 'the tag block moves by the same half share, no more',
              );
              expect(tester.takeException(), isNull);
            },
            arranging: false,
            tagMembers: {'tag-a': entry.value, 'tag-b': entry.value},
          );
        });
      }
    });

    group('dragging a tag that has one member of its own and two shared '
        'members (${kind.name})', () {
      testWidgets(
        'the own member moves with the pointer and each shared member '
        'moves half as far',
        (tester) async {
          await withHullDragField(
            tester,
            (h) async {
              final before = _scenePositions(h);
              final point = _emptyHullPoint(
                tester,
                'tag-a',
                outside: const ['tag-b'],
              );
              final gesture = await _holdThenDrag(tester, point, kind);
              // The field edge may stop the carried member short of the full
              // pointer travel, so shares are taken from its own movement.
              final ownDelta = _scenePositions(h)['cid']! - before['cid']!;
              expect(
                ownDelta.distance,
                greaterThan(25),
                reason: 'the member only in this tag follows the pointer',
              );
              const share = {'ann': 0.5, 'bob': 0.5};
              for (final id in hullDragPeople.where((id) => id != 'cid')) {
                _samePoint(
                  _scenePositions(h)[id]! - before[id]!,
                  ownDelta * (share[id] ?? 0),
                  reason: share.containsKey(id)
                      ? '$id is shared with another tag: half of the own '
                            "member's movement"
                      : '$id is not in the tag and stays put',
                );
              }
              await gesture.up();
              await flushHullDragWrites(tester);
              _expectNoTagAreaDrag(tester, h);
              expect(tester.takeException(), isNull);
            },
            arranging: false,
            tagMembers: const {
              'tag-a': ['ann', 'bob', 'cid'],
              'tag-b': ['ann', 'bob', 'dan'],
            },
          );
        },
      );
    });
  }
}
