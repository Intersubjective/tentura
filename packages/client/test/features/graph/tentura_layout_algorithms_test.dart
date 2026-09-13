import 'dart:ui' show Offset, Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/features/graph/ui/utils/tentura_layout_algorithms.dart';

import 'scene_layout_test_support.dart';

void main() {
  const canvasSize = Size(500, 500);

  final nodeA = UserNode(user: Profile(id: 'a'));
  final nodeB = UserNode(user: Profile(id: 'b'));
  final nodeC = UserNode(user: Profile(id: 'c'));
  final nodeD = UserNode(user: Profile(id: 'd'));
  final nodeE = UserNode(user: Profile(id: 'e'));
  final nodeF = UserNode(user: Profile(id: 'f'));

  NodeDetails nodeById(String id) => switch (id) {
    'a' => nodeA,
    'b' => nodeB,
    'c' => nodeC,
    'd' => nodeD,
    'e' => nodeE,
    'f' => nodeF,
    _ => throw ArgumentError.value(id),
  };

  EdgeDetails edge(String srcId, String dstId) {
    return EdgeDetails(
      source: nodeById(srcId),
      destination: nodeById(dstId),
      color: Colors.blue,
    );
  }

  ScenePoint pointFor(NodeDetails node, Map<GraphNodeId, ScenePoint> positions) =>
      positions[tenturaGraphNodeId(node)]!;

  group('RadialHopLayoutAlgorithm', () {
    test('equal instances compare equal', () {
      const first = RadialHopLayoutAlgorithm(
        rootId: 'a',
        ringGap: 170,
      );
      const second = RadialHopLayoutAlgorithm(
        rootId: 'a',
        ringGap: 170,
      );
      const different = RadialHopLayoutAlgorithm(rootId: 'b');

      expect(first, second);
      expect(first, isNot(different));
    });

    test('layout and relayout produce identical positions', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a');
      final nodes = {nodeA, nodeB, nodeC};
      final edges = {edge('a', 'b'), edge('b', 'c')};

      final initial = await layoutPositionsOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
      );
      final again = await layoutPositionsOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
        previous: sceneLayoutFromPositions(initial),
      );

      for (final node in nodes) {
        expect(pointFor(node, again), pointFor(node, initial));
      }
    });

    test('payload replacement keeps positions under the same graph id', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a');
      final nodes = {nodeA, nodeB};
      final edges = {edge('a', 'b')};
      final initial = await layoutPositionsOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
      );

      final refreshedB = UserNode(
        user: Profile(id: 'b', displayName: 'Renamed'),
        size: nodeB.size,
      );
      final refreshedNodes = {nodeA, refreshedB};
      final afterRefresh = await layoutPositionsOnce(
        algorithm,
        nodes: refreshedNodes,
        edges: {
          EdgeDetails(
            source: nodeA,
            destination: refreshedB,
            color: Colors.blue,
          ),
        },
        previous: sceneLayoutFromPositions(initial),
      );

      expect(
        pointFor(refreshedB, afterRefresh),
        pointFor(nodeB, initial),
      );
    });

    test('relayout keeps existing nodes pinned when the set shrinks', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a');
      final nodes = {nodeA, nodeB, nodeC};
      final edges = {edge('a', 'b'), edge('a', 'c')};

      final initial = await layoutPositionsOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
      );
      final shrunk = await layoutPositionsOnce(
        algorithm,
        nodes: {nodeA, nodeB},
        edges: {edge('a', 'b')},
        previous: sceneLayoutFromPositions(initial),
      );

      expect(pointFor(nodeA, shrunk), pointFor(nodeA, initial));
      expect(pointFor(nodeB, shrunk), pointFor(nodeB, initial));
    });

    test('relayout parks new children along the pinned branch direction', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a', ringGap: 170);
      final nodes = {nodeA, nodeB};
      const parentPos = Offset(250, 100);
      const childPos = Offset(250, 200);
      final previous = sceneLayoutFromPositions({
        tenturaGraphNodeId(nodeA): ScenePoint(x: parentPos.dx, y: parentPos.dy),
        tenturaGraphNodeId(nodeB): ScenePoint(x: childPos.dx, y: childPos.dy),
      });

      final grown = await layoutPositionsOnce(
        algorithm,
        nodes: {nodeA, nodeB, nodeC},
        edges: {edge('a', 'b'), edge('b', 'c')},
        previous: previous,
      );

      expect(pointFor(nodeB, grown).y, closeTo(childPos.dy, 1));
      final c = pointFor(nodeC, grown);
      expect(c.x, closeTo(childPos.dx, 1));
      expect(c.y, closeTo(childPos.dy + 170, 1));
    });

    test('relayout fans multiple siblings locally around the parent', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a', ringGap: 170);
      final previous = sceneLayoutFromPositions({
        tenturaGraphNodeId(nodeA): ScenePoint(x: 250, y: 100),
        tenturaGraphNodeId(nodeB): ScenePoint(x: 250, y: 200),
      });

      final grown = await layoutPositionsOnce(
        algorithm,
        nodes: {nodeA, nodeB, nodeC, nodeD},
        edges: {
          edge('a', 'b'),
          edge('b', 'c'),
          edge('b', 'd'),
        },
        previous: previous,
      );

      final b = pointFor(nodeB, grown);
      final c = pointFor(nodeC, grown);
      final d = pointFor(nodeD, grown);
      expect(_distance(b, c), closeTo(170, 1));
      expect(_distance(b, d), closeTo(170, 1));
      expect(c.y, greaterThan(b.y));
      expect(d.y, greaterThan(b.y));
      expect(_distance(c, d), lessThan(200));
    });

    test('repeated expand re-fans all siblings without overlap', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a', ringGap: 170);
      final previous = sceneLayoutFromPositions({
        tenturaGraphNodeId(nodeA): ScenePoint(x: 250, y: 100),
        tenturaGraphNodeId(nodeB): ScenePoint(x: 250, y: 200),
      });

      final firstBatch = await layoutPositionsOnce(
        algorithm,
        nodes: {nodeA, nodeB, nodeC, nodeD},
        edges: {
          edge('a', 'b'),
          edge('b', 'c'),
          edge('b', 'd'),
        },
        previous: previous,
      );

      final secondBatch = await layoutPositionsOnce(
        algorithm,
        nodes: {nodeA, nodeB, nodeC, nodeD, nodeE, nodeF},
        edges: {
          edge('a', 'b'),
          edge('b', 'c'),
          edge('b', 'd'),
          edge('b', 'e'),
          edge('b', 'f'),
        },
        previous: sceneLayoutFromPositions(firstBatch),
      );

      final b = pointFor(nodeB, secondBatch);
      final positions = [
        pointFor(nodeC, secondBatch),
        pointFor(nodeD, secondBatch),
        pointFor(nodeE, secondBatch),
        pointFor(nodeF, secondBatch),
      ];

      for (final pos in positions) {
        expect(_distance(b, pos), closeTo(170, 1));
      }
      for (var i = 0; i < positions.length; i++) {
        for (var j = i + 1; j < positions.length; j++) {
          expect(
            _distance(positions[i], positions[j]),
            greaterThan(20),
            reason: 'siblings must not overlap after incremental expand',
          );
        }
      }
    });

    test('relayout places root children from global hop sectors', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a', ringGap: 170);
      const largeCanvas = Size(4096, 4096);
      final nodes = {nodeA, nodeB, nodeC, nodeD};
      final edges = {
        edge('a', 'b'),
        edge('a', 'c'),
        edge('a', 'd'),
      };
      final cold = await layoutPositionsOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
        canvasSize: largeCanvas,
      );

      final pinned = sceneLayoutFromPositions({
        tenturaGraphNodeId(nodeA): pointFor(nodeA, cold),
        tenturaGraphNodeId(nodeB): pointFor(nodeB, cold),
      });

      final grown = await layoutPositionsOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
        canvasSize: largeCanvas,
        previous: pinned,
      );

      expect(pointFor(nodeC, grown), pointFor(nodeC, cold));
      expect(pointFor(nodeD, grown), pointFor(nodeD, cold));
      final centre = largeCanvas.center(Offset.zero);
      final c = pointFor(nodeC, grown);
      final d = pointFor(nodeD, grown);
      expect(_distanceScene(c, centre), closeTo(170, 1));
      expect(_distanceScene(d, centre), closeTo(170, 1));
      expect(c.y == centre.dy || d.y == centre.dy, isFalse);
    });

    test('every input node has a position', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a');
      final nodes = {nodeA, nodeB};
      final edges = {edge('a', 'b')};

      final layout = await layoutPositionsOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
      );

      for (final node in nodes) {
        expect(layout.containsKey(tenturaGraphNodeId(node)), isTrue);
      }
    });
  });

  group('LayeredDagLayoutAlgorithm', () {
    test('equal instances compare equal', () {
      const first = LayeredDagLayoutAlgorithm(
        rootIds: {'a'},
        layerGap: 150,
        columnGap: 130,
      );
      const second = LayeredDagLayoutAlgorithm(
        rootIds: {'a'},
        layerGap: 150,
        columnGap: 130,
      );
      const different = LayeredDagLayoutAlgorithm(rootIds: {'b'});

      expect(first, second);
      expect(first, isNot(different));
    });

    test('layout and relayout produce identical positions', () async {
      const algorithm = LayeredDagLayoutAlgorithm(rootIds: {'a'});
      final nodes = {nodeA, nodeB, nodeC};
      final edges = {edge('a', 'b'), edge('b', 'c')};

      final initial = await layoutPositionsOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
      );
      final again = await layoutPositionsOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
        previous: sceneLayoutFromPositions(initial),
      );

      for (final node in nodes) {
        expect(pointFor(node, again), pointFor(node, initial));
      }
    });

    test('every input node has a position', () async {
      const algorithm = LayeredDagLayoutAlgorithm(rootIds: {'a'});
      final nodes = {nodeA, nodeB};
      final edges = {edge('a', 'b')};

      final layout = await layoutPositionsOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
      );

      for (final node in nodes) {
        expect(layout.containsKey(tenturaGraphNodeId(node)), isTrue);
      }
    });
  });
}

double _distance(ScenePoint a, ScenePoint b) =>
    Offset(a.x - b.x, a.y - b.y).distance;

double _distanceScene(ScenePoint point, Offset center) =>
    Offset(point.x - center.dx, point.y - center.dy).distance;
