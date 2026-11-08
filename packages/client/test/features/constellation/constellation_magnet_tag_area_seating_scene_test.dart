import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';
import 'package:tentura/features/constellation/domain/constellation_drag_cluster.dart';
import 'package:tentura/features/constellation/domain/layout/constellation_magnet_layout.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_magnet_layout.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/util/graph_scene_ids.dart';
import 'package:tentura/features/graph/ui/util/tentura_layout_algorithms.dart';

import '../graph/scene_layout_test_support.dart';

const _egoId = 'ego';

ConstellationPathResolution _paths(Set<String> peers) =>
    resolveConstellationPaths(
      egoId: _egoId,
      visiblePeerIds: peers,
      holderIds: {_egoId, ...peers},
      edges: const [],
    );

FieldPersonNode _p(String id, {bool pinned = false}) => FieldPersonNode(
  person: Profile(id: id, displayName: id),
  ring: 1,
  isKept: true,
  pinned: pinned,
);

Future<Map<GraphNodeId, ScenePoint>> _run(
  ConstellationMagnetLayout algo,
  Set<NodeDetails> nodes,
) => layoutPositionsOnce(
  algo,
  nodes: nodes,
  edges: const {},
  canvasSize: const Size(4200, 4200),
);

/// 7abw.9 (#1020): after rearrange, tag-area seating nudges newcomers without priors.
void main() {
  group('ConstellationMagnetLayout tag-area seating (7abw.9)', () {
    Set<String> peopleInTag(String tagId) => switch (tagId) {
      'tagA' => {'m1', 'm2', 'n1', 'n2', 'ego'},
      'tagB' => {'m3', 'm4', 'n2', 'ego'},
      _ => const <String>{},
    };

    Set<String> tagsOf(String id) => switch (id) {
      'm1' => {'tagA'},
      'm2' => {'tagA'},
      'm3' => {'tagB'},
      'm4' => {'tagB'},
      'n1' => {'tagA'},
      'n2' => {'tagA', 'tagB'},
      'u1' => <String>{},
      _ => <String>{},
    };

    test(
      'single-tag newcomer sits within tag disk around centroid without overlap',
      () async {
        final base = ConstellationSceneLayoutAlgorithm(
          egoId: _egoId,
          paths: _paths({'m1', 'm2', 'n1', 'ego'}),
          keptPeerIds: const {'m1', 'm2', 'n1', 'ego'},
          maxHops: 3,
          visibleRequestsByAuthor: const {},
          egoOwnRequestIds: const {},
        );
        final algo = ConstellationMagnetLayout(
          base: base,
          viewerId: _egoId,
          tagsOfPerson: tagsOf,
          peopleInTag: peopleInTag,
          priors: const {},
          magnetsByPerson: const {},
          followers: const {},
        );
        final ego = _p('ego');
        final m1 = _p('m1');
        final m2 = _p('m2');
        final n1 = _p('n1');
        final seated = await layoutPositionsOnce(
          base,
          nodes: {ego, m1, m2},
          edges: const {},
          canvasSize: const Size(4200, 4200),
        );
        final previous = sceneLayoutFromPositions({
          tenturaGraphNodeId(ego): seated[tenturaGraphNodeId(ego)]!,
          tenturaGraphNodeId(m1): seated[tenturaGraphNodeId(m1)]!,
          tenturaGraphNodeId(m2): seated[tenturaGraphNodeId(m2)]!,
        });
        final pos = await layoutPositionsOnce(
          algo,
          nodes: {ego, m1, m2, n1},
          edges: const {},
          previous: previous,
          canvasSize: const Size(4200, 4200),
        );
        final n1p = pos[tenturaGraphNodeId(n1)]!;
        final cA = constellationTagMemberCentroidScene(
          tagId: 'tagA',
          peopleOfTag: peopleInTag,
          personCentreById: {
            'm1': (
              x: pos[tenturaGraphNodeId(m1)]!.x,
              y: pos[tenturaGraphNodeId(m1)]!.y,
            ),
            'm2': (
              x: pos[tenturaGraphNodeId(m2)]!.x,
              y: pos[tenturaGraphNodeId(m2)]!.y,
            ),
            'ego': (
              x: pos[tenturaGraphNodeId(ego)]!.x,
              y: pos[tenturaGraphNodeId(ego)]!.y,
            ),
          },
          egoId: _egoId,
          excludePersonIds: const {'n1'},
        )!;
        final cell = kConstellationDragPersonBodySize.width + 16;
        final r = constellationTagAreaRadiusForSeating(
          memberCount: peopleInTag(
            'tagA',
          ).where((id) => id != 'ego' && id != 'n1').length,
          maxCell: cell,
        );
        final dx = n1p.x - cA.x;
        final dy = n1p.y - cA.y;
        expect(dx * dx + dy * dy, lessThan(r * r + 1e-6));

        for (final other in [m1, m2, ego]) {
          final op = pos[tenturaGraphNodeId(other)]!;
          final ex = n1p.x - op.x;
          final ey = n1p.y - op.y;
          expect(
            ex * ex + ey * ey,
            greaterThan(35 * 35),
            reason: 'no node overlap between n1 and ${other.person.id}',
          );
        }
      },
    );

    test(
      'two-tag newcomer is near the midpoint of the two tag centroids',
      () async {
        final base = ConstellationSceneLayoutAlgorithm(
          egoId: _egoId,
          paths: _paths({'m1', 'm2', 'm3', 'm4', 'n2', 'ego'}),
          keptPeerIds: const {'m1', 'm2', 'm3', 'm4', 'n2', 'ego'},
          maxHops: 3,
          visibleRequestsByAuthor: const {},
          egoOwnRequestIds: const {},
        );
        final algo = ConstellationMagnetLayout(
          base: base,
          viewerId: _egoId,
          tagsOfPerson: tagsOf,
          peopleInTag: peopleInTag,
          priors: const {},
          magnetsByPerson: const {},
          followers: const {},
        );
        final ego = _p('ego');
        final m1n = _p('m1');
        final m2n = _p('m2');
        final m3n = _p('m3');
        final m4n = _p('m4');
        final n2n = _p('n2');
        final established = await layoutPositionsOnce(
          base,
          nodes: {ego, m1n, m2n, m3n, m4n},
          edges: const {},
          canvasSize: const Size(4200, 4200),
        );
        final previous = sceneLayoutFromPositions({
          for (final n in [ego, m1n, m2n, m3n, m4n])
            tenturaGraphNodeId(n): established[tenturaGraphNodeId(n)]!,
        });
        final nodes = {ego, m1n, m2n, m3n, m4n, n2n};
        final pos = await layoutPositionsOnce(
          algo,
          nodes: nodes,
          edges: const {},
          previous: previous,
          canvasSize: const Size(4200, 4200),
        );
        final n2 = pos[tenturaGraphNodeId(n2n)]!;
        LPoint c(String tag) => constellationTagMemberCentroidScene(
          tagId: tag,
          peopleOfTag: peopleInTag,
          personCentreById: {
            'm1': (
              x: pos[tenturaGraphNodeId(m1n)]!.x,
              y: pos[tenturaGraphNodeId(m1n)]!.y,
            ),
            'm2': (
              x: pos[tenturaGraphNodeId(m2n)]!.x,
              y: pos[tenturaGraphNodeId(m2n)]!.y,
            ),
            'm3': (
              x: pos[tenturaGraphNodeId(m3n)]!.x,
              y: pos[tenturaGraphNodeId(m3n)]!.y,
            ),
            'm4': (
              x: pos[tenturaGraphNodeId(m4n)]!.x,
              y: pos[tenturaGraphNodeId(m4n)]!.y,
            ),
            'ego': (
              x: pos[tenturaGraphNodeId(ego)]!.x,
              y: pos[tenturaGraphNodeId(ego)]!.y,
            ),
          },
          egoId: _egoId,
          excludePersonIds: const {'n2'},
        )!;
        final mid = (
          (c('tagA').x + c('tagB').x) / 2,
          (c('tagA').y + c('tagB').y) / 2,
        );
        final dx = n2.x - mid.$1;
        final dy = n2.y - mid.$2;
        expect(dx * dx + dy * dy, lessThan(240 * 240));
      },
    );

    test('untagged newcomer is not moved by tag seating', () async {
      final base = ConstellationSceneLayoutAlgorithm(
        egoId: _egoId,
        paths: _paths({'m1', 'u1', 'ego'}),
        keptPeerIds: const {'m1', 'u1', 'ego'},
        maxHops: 3,
        visibleRequestsByAuthor: const {},
        egoOwnRequestIds: const {},
      );
      final algo = ConstellationMagnetLayout(
        base: base,
        viewerId: _egoId,
        tagsOfPerson: tagsOf,
        peopleInTag: peopleInTag,
        priors: const {},
        magnetsByPerson: const {},
        followers: const {},
      );
      final ego = _p('ego');
      final m1 = _p('m1');
      final u1 = _p('u1');
      final two = await layoutPositionsOnce(
        base,
        nodes: {ego, m1},
        edges: const {},
        canvasSize: const Size(4200, 4200),
      );
      final previous = sceneLayoutFromPositions({
        tenturaGraphNodeId(ego): two[tenturaGraphNodeId(ego)]!,
        tenturaGraphNodeId(m1): two[tenturaGraphNodeId(m1)]!,
      });
      final bare = await layoutPositionsOnce(
        base,
        nodes: {ego, m1, u1},
        edges: const {},
        previous: previous,
        canvasSize: const Size(4200, 4200),
      );
      final wrapped = await layoutPositionsOnce(
        algo,
        nodes: {ego, m1, u1},
        edges: const {},
        previous: previous,
        canvasSize: const Size(4200, 4200),
      );
      final uBare = bare[tenturaGraphNodeId(u1)]!;
      final uWrap = wrapped[tenturaGraphNodeId(u1)]!;
      expect(uWrap.x, closeTo(uBare.x, 0.5));
      expect(uWrap.y, closeTo(uBare.y, 0.5));
    });

    test(
      'a cold layout seats nobody: tagged people keep the base layout',
      () async {
        // The first layout after load has no previous arrangement, so nobody
        // is a newcomer; seating everyone squeezed each tag into a small disk
        // until the next relayout spread it again (owner report 2026-11-07).
        final base = ConstellationSceneLayoutAlgorithm(
          egoId: _egoId,
          paths: _paths({'m1', 'm2', 'm3', 'm4', 'n1', 'n2', 'ego'}),
          keptPeerIds: const {'m1', 'm2', 'm3', 'm4', 'n1', 'n2', 'ego'},
          maxHops: 3,
          visibleRequestsByAuthor: const {},
          egoOwnRequestIds: const {},
        );
        final algo = ConstellationMagnetLayout(
          base: base,
          viewerId: _egoId,
          tagsOfPerson: tagsOf,
          peopleInTag: peopleInTag,
          priors: const {},
          magnetsByPerson: const {},
          followers: const {},
        );
        final nodes = {
          for (final id in ['ego', 'm1', 'm2', 'm3', 'm4', 'n1', 'n2']) _p(id),
        };
        final cold = await layoutPositionsOnce(
          base,
          nodes: nodes,
          edges: const {},
          canvasSize: const Size(4200, 4200),
        );
        final wrapped = await _run(algo, nodes);
        for (final node in nodes) {
          final id = tenturaGraphNodeId(node);
          expect(wrapped[id]!.x, closeTo(cold[id]!.x, 0.5), reason: id);
          expect(wrapped[id]!.y, closeTo(cold[id]!.y, 0.5), reason: id);
        }
      },
    );

    test('pinned people are not moved by tag seating', () async {
      final base = ConstellationSceneLayoutAlgorithm(
        egoId: _egoId,
        paths: _paths({'m1', 'm2', 'n1', 'ego'}),
        keptPeerIds: const {'m1', 'm2', 'n1', 'ego'},
        maxHops: 3,
        visibleRequestsByAuthor: const {},
        egoOwnRequestIds: const {},
      );
      final ego = _p('ego');
      final m1 = _p('m1', pinned: true);
      final m2 = _p('m2');
      final n1 = _p('n1');
      final cold = await layoutPositionsOnce(
        base,
        nodes: {ego, m1, m2, n1},
        edges: const {},
        canvasSize: const Size(4200, 4200),
      );
      final algo = ConstellationMagnetLayout(
        base: base,
        viewerId: _egoId,
        tagsOfPerson: tagsOf,
        peopleInTag: peopleInTag,
        priors: const {},
        magnetsByPerson: const {},
        followers: const {},
      );
      final pos = await layoutPositionsOnce(
        algo,
        nodes: {ego, m1, m2, n1},
        edges: const {},
        canvasSize: const Size(4200, 4200),
      );
      final m1Cold = cold[tenturaGraphNodeId(m1)]!;
      expect(pos[tenturaGraphNodeId(m1)]!.x, closeTo(m1Cold.x, 0.5));
      expect(pos[tenturaGraphNodeId(m1)]!.y, closeTo(m1Cold.y, 0.5));
    });
  });
}
