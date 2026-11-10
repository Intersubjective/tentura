// ConstellationSceneController.fitWholeField — the camera behind
// «Показать всё поле» / «Show whole field» and the Field's automatic framing —
// frames every node drawn on the Field, whatever the layout holds:
//
// * a person arranged 20 000+ scene px from everyone else (Rearrange everyone
//   / Move area), even when that needs a zoom below the district-detail scale;
// * last layout positions of people no longer on the Field (hidden, removed)
//   and forward-tree overlay leftovers do not move the camera;
// * a NaN or infinite layout position for a node is refused, the node keeps
//   its last finite position, and fit-all still frames everyone;
// * a node whose placed footprint is not finite does not break the camera;
//   every other node is still framed.
//
// Positions come from a layout algorithm that returns the roster's own
// positions, so every case is exact and repeatable. A node position enters
// the scene only as a ScenePoint, which rejects non-finite coordinates; the
// placed footprint is the other per-node input to fit-all bounds and can
// carry a non-finite value, so it is tested too.
@TestOn('vm')
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_scene_controller.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

/// Phone viewport (375×667) and the Field's camera insets on it: top bar
/// strip, camera-control column on the right, bottom chrome.
const _viewport = Size(375, 667);
const _insets = EdgeInsets.fromLTRB(12, 64, 64, 96);

/// Scene canvas big enough to hold the far-away arrangements.
const _canvas = Size(120000, 120000);
const _centre = Offset(60000, 60000);

/// Gap between Zoe and the group: the criterion's 20 000 scene px.
const _farGap = 20000.0;

FieldPersonNode _person(String id, String name) => FieldPersonNode(
  person: Profile(id: id, displayName: name),
  ring: id == 'bob' ? 0 : 1,
  isKept: false,
);

FieldBeaconNode _post(String id, String authorId) => FieldBeaconNode(
  post: ConstellationPost(
    id: id,
    authorId: authorId,
    rootExcerpt: 'Пост $id',
    lastActivityAt: DateTime.utc(2026, 11, 8, 12),
  ),
);

final _bob = _person('bob', 'Боб');
final _zoe = _person('zoe', 'Зоя');
final _yan = _person('yan', 'Ян');
final _group = [
  _person('anna', 'Анна'),
  _person('boris', 'Борис'),
  _person('dima', 'Дима'),
  _person('kira', 'Кира'),
  _person('lena', 'Лена'),
  _person('misha', 'Миша'),
];
final _posts = [_post('post-bob', 'bob'), _post('post-anna', 'anna')];

/// The offending roster: Bob, his group, two Post satellites and Zoe placed
/// [_farGap] beyond the group on both axes.
Map<NodeDetails, Offset> _roster() {
  const ring = 170.0;
  return {
    _bob: _centre,
    for (final (i, person) in _group.indexed)
      person: _centre + Offset.fromDirection(i * math.pi / 3, ring),
    _posts[0]: _centre + const Offset(0, 56),
    _posts[1]: _centre + const Offset(ring, 56),
    _zoe: _centre + const Offset(ring + _farGap, ring + _farGap),
  };
}

/// Returns the roster's positions for every requested node.
final class _RosterLayout implements SceneLayoutAlgorithm {
  _RosterLayout(this.positions);

  final Map<GraphNodeId, Offset> positions;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: {
        for (final id in request.nodeIds)
          if (positions[id] case final p?) id: ScenePoint(x: p.dx, y: p.dy),
      },
      isTerminal: true,
    );
  }
}

/// A scene controller laid out with [roster] inside a phone-sized GraphView.
Future<ConstellationSceneController> _mount(
  WidgetTester tester,
  Map<NodeDetails, Offset> roster,
) async {
  final scene = ConstellationSceneController();
  addTearDown(scene.graphController.dispose);
  scene.graphController.reconcileTopology(
    roster.keys.toSet(),
    <EdgeDetails>{},
    layoutOnTopologyChange: false,
  );
  await tester.binding.setSurfaceSize(_viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox.fromSize(
        size: _viewport,
        child: GraphView<NodeDetails, EdgeDetails>(
          controller: scene.graphController,
          canvasSize: const GraphCanvasSize.fixed(_canvas),
          // Only fit-all's own limits are under test, not the viewer's zoom
          // bounds (GraphView defaults to 0.5).
          minScale: 0.001,
          layoutAlgorithm: _RosterLayout({
            for (final MapEntry(:key, :value) in roster.entries)
              key.graphNodeId: value,
          }),
          nodeBuilder: (_, node) => SizedBox.square(dimension: node.size),
        ),
      ),
    ),
  );
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 5));
    if (scene.graphController.scene.layoutOutcome
        is! GraphLayoutOutcomeRunning) {
      break;
    }
  }
  expect(scene.graphController.canLayout, isTrue);
  for (final node in roster.keys) {
    expect(
      scene.graphController.renderSnapshot.resolveTargetPosition(
        node.graphNodeId,
      ),
      isNotNull,
      reason: '${node.graphNodeId} is placed',
    );
  }
  return scene;
}

/// Fit-all as the Field runs it.
Future<void> _fitAll(
  WidgetTester tester,
  ConstellationSceneController scene,
) async {
  scene.fitWholeField(_insets);
  await tester.pump();
}

Rect _safeRect(ConstellationSceneController scene) =>
    _insets.deflateRect(Offset.zero & scene.graphController.viewportSize!);

/// [id]'s node body in viewport pixels through the current camera.
Rect _bodyOnScreen(ConstellationSceneController scene, GraphNodeId id) {
  final graph = scene.graphController;
  final node = graph.renderSnapshot.topology.nodesById[id]!;
  final point = graph.renderSnapshot.resolveTargetPosition(id)!;
  final body = Rect.fromCenter(
    center: Offset(point.x, point.y),
    width: node.size.width,
    height: node.size.height,
  );
  return Rect.fromPoints(
    graph.sceneToViewportLocal(body.topLeft),
    graph.sceneToViewportLocal(body.bottomRight),
  );
}

bool _inside(Rect outer, Rect inner) =>
    inner.left >= outer.left - 0.5 &&
    inner.top >= outer.top - 0.5 &&
    inner.right <= outer.right + 0.5 &&
    inner.bottom <= outer.bottom + 0.5;

void _expectBodiesInSafeRect(
  ConstellationSceneController scene,
  Iterable<NodeDetails> nodes, {
  required String when,
}) {
  final safe = _safeRect(scene);
  final scale = scene.graphController.cameraScale;
  for (final node in nodes) {
    final body = _bodyOnScreen(scene, node.graphNodeId);
    expect(
      _inside(safe, body),
      isTrue,
      reason:
          '$when: ${node.graphNodeId} body $body lies inside the safe '
          'viewport $safe (camera scale $scale)',
    );
  }
}

typedef _Camera = ({double scale, Offset centre});

/// The camera as scale plus the scene point at the centre of the safe rect.
_Camera _camera(ConstellationSceneController scene) => (
  scale: scene.graphController.cameraScale,
  centre: scene.graphController.viewportLocalToScene(_safeRect(scene).center),
);

void _expectSameCamera(
  _Camera actual,
  _Camera expected, {
  required String when,
}) {
  expect(
    actual.scale,
    closeTo(expected.scale, 1e-6),
    reason: '$when: same fit-all scale',
  );
  expect(
    (actual.centre - expected.centre).distance,
    lessThanOrEqualTo(1),
    reason:
        '$when: same fit-all centre (${actual.centre} vs ${expected.centre})',
  );
}

/// The fit-all camera of [roster] on its own scene.
Future<_Camera> _fitAllCameraOf(
  WidgetTester tester,
  Map<NodeDetails, Offset> roster,
) async {
  final scene = await _mount(tester, roster);
  await _fitAll(tester, scene);
  final camera = _camera(scene);
  await tester.pumpWidget(const SizedBox.shrink());
  return camera;
}

void main() {
  group('Fit-all frames a person arranged far from everyone else', () {
    testWidgets(
      'a person 20 000 scene px beyond the group is framed together with the '
      'viewer, the group and the Post satellites, below the district-detail '
      'scale',
      (tester) async {
        final roster = _roster();
        final scene = await _mount(tester, roster);
        final zoe = roster[_zoe]!;
        for (final MapEntry(:key, :value) in roster.entries) {
          if (key != _zoe) {
            expect(
              (zoe - value).distance,
              greaterThanOrEqualTo(_farGap),
              reason: 'Zoe is at least 20 000 px from ${key.graphNodeId}',
            );
          }
        }

        await _fitAll(tester, scene);

        expect(
          scene.graphController.cameraScale,
          lessThan(kConstellationDistrictDetailScale),
          reason: 'the camera is not left at the district-detail floor',
        );
        _expectBodiesInSafeRect(scene, roster.keys, when: 'after fit-all');
      },
    );

    testWidgets(
      'with people far away on both sides of the group, fit-all frames all '
      'of them with the viewer and the group',
      (tester) async {
        final roster = {
          ..._roster(),
          _yan: _centre - const Offset(_farGap, _farGap),
        };
        final scene = await _mount(tester, roster);

        await _fitAll(tester, scene);

        expect(
          scene.graphController.cameraScale,
          lessThan(kConstellationDistrictDetailScale),
        );
        _expectBodiesInSafeRect(scene, roster.keys, when: 'after fit-all');
      },
    );
  });

  group('Fit-all ignores layout positions of nodes not on the Field', () {
    testWidgets(
      'a person hidden from the Field whose last layout position is far away '
      'does not change the fit-all camera',
      (tester) async {
        final expected = await _fitAllCameraOf(tester, _roster());

        final withYan = {
          ..._roster(),
          _yan: _centre - const Offset(3 * _farGap, 3 * _farGap),
        };
        final scene = await _mount(tester, withYan);
        final layoutWithYan = Map<GraphNodeId, ScenePoint>.of(
          scene.graphController.renderSnapshot.layout!.positions,
        );

        // Yan is hidden: the Field no longer draws him, while his last layout
        // position stays in the scene.
        scene.graphController.reconcileTopology(
          _roster().keys.toSet(),
          <EdgeDetails>{},
          requestLayout: false,
          layoutOnTopologyChange: false,
        );
        scene.graphController.scene.setLayoutPositions(layoutWithYan);
        await tester.pump();
        expect(
          scene.graphController.renderSnapshot.topology.nodesById,
          isNot(contains(_yan.graphNodeId)),
          reason: 'Yan is not on the Field',
        );
        expect(
          scene.graphController.renderSnapshot.layout!.positions,
          contains(_yan.graphNodeId),
          reason: 'Yan’s far layout position is still in the scene',
        );

        await _fitAll(tester, scene);

        _expectSameCamera(_camera(scene), expected, when: 'Yan hidden');
        _expectBodiesInSafeRect(scene, _roster().keys, when: 'Yan hidden');
      },
    );

    testWidgets(
      'stale layout entries of a removed person and of a closed forward-tree '
      'overlay do not change the fit-all camera',
      (tester) async {
        final expected = await _fitAllCameraOf(tester, _roster());

        final scene = await _mount(tester, _roster());
        scene.graphController.scene.setLayoutPositions({
          ...scene.graphController.renderSnapshot.layout!.positions,
          'fp:removed-person': ScenePoint(x: -_farGap, y: -_farGap),
          'ft:forward-tree-leftover': ScenePoint(
            x: _canvas.width + _farGap,
            y: -_farGap,
          ),
        });
        await tester.pump();

        await _fitAll(tester, scene);

        _expectSameCamera(_camera(scene), expected, when: 'stale entries');
        _expectBodiesInSafeRect(
          scene,
          _roster().keys,
          when: 'stale entries',
        );
      },
    );
  });

  group('Fit-all after a NaN or infinite layout position for a node', () {
    for (final (name, value) in [
      ('a NaN', double.nan),
      ('an infinite', double.infinity),
    ]) {
      testWidgets(
        '$name position is refused and fit-all still frames every visible '
        'node with a finite camera',
        (tester) async {
          final roster = _roster();
          final scene = await _mount(tester, roster);
          final broken = _group.first.graphNodeId;
          final graph = scene.graphController;
          final before = Map<GraphNodeId, ScenePoint>.of(
            graph.renderSnapshot.layout!.positions,
          );

          expect(
            () => graph.scene.setLayoutPositions({
              ...before,
              broken: ScenePoint(x: value, y: value),
            }),
            throwsArgumentError,
            reason: 'a non-finite layout position never enters the scene',
          );
          await tester.pump();
          final kept = graph.renderSnapshot.resolveTargetPosition(broken)!;
          expect(
            Offset(kept.x, kept.y),
            Offset(before[broken]!.x, before[broken]!.y),
            reason: 'the node keeps its last finite position',
          );

          await _fitAll(tester, scene);

          final scale = graph.cameraScale;
          final translation = graph.sceneToViewportLocal(Offset.zero);
          expect(scale.isFinite && scale > 0, isTrue, reason: 'scale $scale');
          expect(
            translation.isFinite,
            isTrue,
            reason: 'translation $translation',
          );
          _expectBodiesInSafeRect(
            scene,
            roster.keys,
            when: 'after $name position',
          );
        },
      );
    }
  });

  group('Fit-all with a node whose placed footprint is not finite', () {
    for (final (name, value) in [
      ('a NaN', double.nan),
      ('an infinite', double.infinity),
    ]) {
      testWidgets(
        '$name footprint leaves a finite camera that frames every other '
        'visible node',
        (tester) async {
          final roster = _roster();
          final scene = await _mount(tester, roster);
          final broken = _group.first;
          scene.layoutFootprints = {
            broken.graphNodeId: (
              left: value,
              top: value,
              right: value,
              bottom: value,
            ),
          };

          await _fitAll(tester, scene);

          final scale = scene.graphController.cameraScale;
          final translation = scene.graphController.sceneToViewportLocal(
            Offset.zero,
          );
          expect(scale.isFinite && scale > 0, isTrue, reason: 'scale $scale');
          expect(
            translation.isFinite,
            isTrue,
            reason: 'translation $translation',
          );
          _expectBodiesInSafeRect(
            scene,
            roster.keys.where((n) => n != broken),
            when: 'with $name footprint',
          );
        },
      );
    }
  });
}
