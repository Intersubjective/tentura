import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_arrangement_layout.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/tentura_layout_algorithms.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

import '../graph/scene_layout_test_support.dart';

const _egoId = 'ego';
const _canvas = Size(4200, 4200);

FieldPersonNode _person(String id, {int ring = 1}) => FieldPersonNode(
  person: Profile(id: id, displayName: id),
  ring: ring,
  isKept: true,
);

EdgeDetails _forward(FieldPersonNode from, FieldPersonNode to) => EdgeDetails(
  source: from,
  destination: to,
  color: Colors.grey,
);

/// The scene's own base algorithm: saved people sit on trust paths, the
/// tree-only people (kept, but on no path) get the residual seats.
ConstellationSceneLayoutAlgorithm _baseAlgorithm({
  required Set<String> pathIds,
  required Set<String> keptIds,
}) => ConstellationSceneLayoutAlgorithm(
  egoId: _egoId,
  paths: resolveConstellationPaths(
    egoId: _egoId,
    visiblePeerIds: pathIds.difference({_egoId}),
    holderIds: pathIds,
    edges: const [],
  ),
  keptPeerIds: keptIds,
  maxHops: 3,
  visibleRequestsByAuthor: const {},
  egoOwnRequestIds: const {},
);

Rect _body(String id, Map<String, ScenePoint> at, Map<String, double> sizes) {
  final p = at[id]!;
  final s = sizes[id]!;
  return Rect.fromCenter(center: Offset(p.x, p.y), width: s, height: s);
}

double _overlapArea(Rect a, Rect b) {
  final i = a.intersect(b);
  return i.width > 0 && i.height > 0 ? i.width * i.height : 0;
}

double _dist(ScenePoint a, ScenePoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

void main() {
  final ego = _person(_egoId, ring: 0);
  final forwarder = _person('a');
  final other1 = _person('p1');
  final other2 = _person('p2');
  final treeB = _person('b'); // forwarded by `a`, not saved
  final treeC = _person('c'); // forwarded by `b`, not saved

  final nodes = {ego, forwarder, other1, other2, treeB, treeC};
  final edges = {_forward(forwarder, treeB), _forward(treeB, treeC)};
  final sizes = {for (final n in nodes) n.graphNodeId: n.size};

  final base = _baseAlgorithm(
    pathIds: {_egoId, 'a', 'p1', 'p2'},
    keptIds: {'a', 'p1', 'p2', 'b', 'c'},
  );

  final idEgo = ego.graphNodeId;
  final idA = forwarder.graphNodeId;
  final idP1 = other1.graphNodeId;
  final idP2 = other2.graphNodeId;
  final idB = treeB.graphNodeId;
  final idC = treeC.graphNodeId;

  /// Saved positions: the forwarder was dragged far from where the base
  /// layout alone would seat it, and two other people stand exactly on the
  /// seats the base layout alone would give the tree-only people.
  Future<Map<String, ScenePoint>> savedPositions() async {
    final alone = await layoutPositionsOnce(
      base,
      nodes: nodes,
      edges: const {},
      canvasSize: _canvas,
    );
    final movedA = ScenePoint(x: alone[idA]!.x + 1500, y: alone[idA]!.y + 1500);
    expect(_dist(movedA, alone[idA]!), greaterThanOrEqualTo(1000));
    return {
      idEgo: alone[idEgo]!,
      idA: movedA,
      idP1: alone[idB]!,
      idP2: alone[idC]!,
    };
  }

  Future<List<GraphLayoutFrame>> frames(
    Map<String, ScenePoint> saved, {
    required bool conflictingPrevious,
  }) {
    final previous = conflictingPrevious
        ? sceneLayoutFromPositions({
            for (final e in saved.entries)
              e.key: ScenePoint(x: e.value.x + 300, y: e.value.y - 200),
          })
        : null;
    final request = sceneLayoutRequest(
      nodes: nodes,
      edges: edges,
      previous: previous,
      canvasSize: _canvas,
    );
    return ConstellationFixedLayout(saved, fillMissingWith: () => base)
        .layout(request)
        .toList()
        .timeout(const Duration(seconds: 20));
  }

  group('ConstellationFixedLayout fillMissingWith', () {
    for (final conflictingPrevious in [false, true]) {
      final variant = conflictingPrevious
          ? 'when the request carries conflicting previous positions'
          : 'when the request has no previous layout';

      group(variant, () {
        test('places every node with finite coordinates and keeps saved '
            'positions exact in every frame', () async {
          final saved = await savedPositions();
          final result = await frames(
            saved,
            conflictingPrevious: conflictingPrevious,
          );
          expect(result, isNotEmpty);
          expect(result.last.isTerminal, isTrue);
          for (final frame in result) {
            for (final entry in saved.entries) {
              expect(
                frame.positions[entry.key],
                entry.value,
                reason: '${entry.key} must stay at its saved position',
              );
            }
          }
          final terminal = result.last.positions;
          expect(
            terminal.keys,
            containsAll(nodes.map((n) => n.graphNodeId)),
          );
          for (final p in terminal.values) {
            expect(p.x.isFinite && p.y.isFinite, isTrue);
          }
        });

        test('tree-only people do not overlap any saved node', () async {
          final saved = await savedPositions();
          final terminal = (await frames(
            saved,
            conflictingPrevious: conflictingPrevious,
          )).last.positions;
          for (final treeId in [idB, idC]) {
            for (final savedId in saved.keys) {
              expect(
                _overlapArea(
                  _body(treeId, terminal, sizes),
                  _body(savedId, terminal, sizes),
                ),
                0,
                reason: '$treeId lands on saved $savedId',
              );
            }
          }
        });

        test('each tree-only person lands nearer its forwarder than any '
            'saved node outside its forward path', () async {
          final saved = await savedPositions();
          final terminal = (await frames(
            saved,
            conflictingPrevious: conflictingPrevious,
          )).last.positions;

          // B is forwarded by A: closer to A than to ego / p1 / p2.
          final toForwarder = _dist(terminal[idB]!, terminal[idA]!);
          for (final otherId in [idEgo, idP1, idP2]) {
            expect(
              toForwarder,
              lessThan(_dist(terminal[idB]!, terminal[otherId]!)),
              reason: 'b should sit nearer its forwarder a than saved $otherId',
            );
          }
          // C is forwarded by B (itself tree-only): closer to B than to the
          // saved nodes outside its path (ego / p1 / p2; A is on the path).
          final cToB = _dist(terminal[idC]!, terminal[idB]!);
          for (final otherId in [idEgo, idP1, idP2]) {
            expect(
              cToB,
              lessThan(_dist(terminal[idC]!, terminal[otherId]!)),
              reason: 'c should sit nearer its forwarder b than saved $otherId',
            );
          }
        });
      });
    }

    test('every node saved: one terminal frame with the saved positions and '
        'the fallback is never built', () async {
      final savedNodes = {ego, forwarder, other1, other2};
      final saved = {
        idEgo: ScenePoint(x: 100, y: 100),
        idA: ScenePoint(x: 1500, y: 1700),
        idP1: ScenePoint(x: 400, y: 900),
        idP2: ScenePoint(x: 2200, y: 300),
      };
      var factoryCalls = 0;
      final request = sceneLayoutRequest(
        nodes: savedNodes,
        edges: const {},
        canvasSize: _canvas,
      );
      final result =
          await ConstellationFixedLayout(
                saved,
                fillMissingWith: () {
                  factoryCalls++;
                  return base;
                },
              )
              .layout(request)
              .toList()
              .timeout(const Duration(seconds: 20));
      expect(result, hasLength(1));
      expect(result.single.sequence, 0);
      expect(result.single.isTerminal, isTrue);
      expect(result.single.positions, saved);
      expect(factoryCalls, 0);
    });
  });
}
