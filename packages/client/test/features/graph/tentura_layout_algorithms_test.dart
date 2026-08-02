import 'dart:ui' show Offset, Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/tentura_layout_algorithms.dart';

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

  EdgeDetails<NodeDetails> edge(String srcId, String dstId) {
    return EdgeDetails(
      source: nodeById(srcId),
      destination: nodeById(dstId),
      color: Colors.blue,
    );
  }

  Future<GraphLayout> layoutOnce(
    GraphLayoutAlgorithm algorithm, {
    required Set<NodeDetails> nodes,
    required Set<EdgeDetails<NodeDetails>> edges,
  }) async {
    final stream = algorithm.layout(
      nodes: nodes,
      edges: edges,
      size: canvasSize,
    );
    return stream.first;
  }

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

      final initial = await layoutOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
      );
      final again = await algorithm.relayout(
        existingLayout: initial,
        nodes: nodes,
        edges: edges,
        size: canvasSize,
      ).first;

      for (final node in nodes) {
        expect(again.getPosition(node), initial.getPosition(node));
      }
    });

    test('relayout keeps existing nodes pinned when the set shrinks', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a');
      final nodes = {nodeA, nodeB, nodeC};
      final edges = {edge('a', 'b'), edge('a', 'c')};

      final initial = await layoutOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
      );
      final shrunk = await algorithm
          .relayout(
            existingLayout: initial,
            nodes: {nodeA, nodeB},
            edges: {edge('a', 'b')},
            size: canvasSize,
          )
          .first;

      expect(shrunk.getPosition(nodeA), initial.getPosition(nodeA));
      expect(shrunk.getPosition(nodeB), initial.getPosition(nodeB));
    });

    test('relayout parks new children along the pinned branch direction', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a', ringGap: 170);
      final nodes = {nodeA, nodeB};
      // Place A→B going straight down so the fan must continue that heading.
      const parentPos = Offset(250, 100);
      const childPos = Offset(250, 200);
      final pinned = GraphLayoutBuilder(nodes: nodes)
        ..setNodePosition(nodeA, parentPos)
        ..setNodePosition(nodeB, childPos);
      final existing = pinned.build();

      final grown = await algorithm
          .relayout(
            existingLayout: existing,
            nodes: {nodeA, nodeB, nodeC},
            edges: {edge('a', 'b'), edge('b', 'c')},
            size: canvasSize,
          )
          .first;

      expect(grown.getPosition(nodeB), childPos);
      final c = grown.getPosition(nodeC);
      // Single child continues straight down by ringGap.
      expect(c.dx, closeTo(childPos.dx, 1));
      expect(c.dy, closeTo(childPos.dy + 170, 1));
    });

    test('relayout fans multiple siblings locally around the parent', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a', ringGap: 170);
      final nodes = {nodeA, nodeB};
      final pinned = GraphLayoutBuilder(nodes: nodes)
        ..setNodePosition(nodeA, const Offset(250, 100))
        ..setNodePosition(nodeB, const Offset(250, 200));
      final existing = pinned.build();

      final grown = await algorithm
          .relayout(
            existingLayout: existing,
            nodes: {nodeA, nodeB, nodeC, nodeD},
            edges: {
              edge('a', 'b'),
              edge('b', 'c'),
              edge('b', 'd'),
            },
            size: canvasSize,
          )
          .first;

      final b = grown.getPosition(nodeB);
      final c = grown.getPosition(nodeC);
      final d = grown.getPosition(nodeD);
      expect((c - b).distance, closeTo(170, 1));
      expect((d - b).distance, closeTo(170, 1));
      // Both stay below the parent (branch was downward).
      expect(c.dy, greaterThan(b.dy));
      expect(d.dy, greaterThan(b.dy));
      // And near each other — not opposite sides of the canvas.
      expect((c - d).distance, lessThan(200));
    });

    test('repeated expand re-fans all siblings without overlap', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a', ringGap: 170);
      final pinned = GraphLayoutBuilder(nodes: {nodeA, nodeB})
        ..setNodePosition(nodeA, const Offset(250, 100))
        ..setNodePosition(nodeB, const Offset(250, 200));
      final existing = pinned.build();

      final firstBatch = await algorithm
          .relayout(
            existingLayout: existing,
            nodes: {nodeA, nodeB, nodeC, nodeD},
            edges: {
              edge('a', 'b'),
              edge('b', 'c'),
              edge('b', 'd'),
            },
            size: canvasSize,
          )
          .first;

      final secondBatch = await algorithm
          .relayout(
            existingLayout: firstBatch,
            nodes: {nodeA, nodeB, nodeC, nodeD, nodeE, nodeF},
            edges: {
              edge('a', 'b'),
              edge('b', 'c'),
              edge('b', 'd'),
              edge('b', 'e'),
              edge('b', 'f'),
            },
            size: canvasSize,
          )
          .first;

      final b = secondBatch.getPosition(nodeB);
      final positions = [
        secondBatch.getPosition(nodeC),
        secondBatch.getPosition(nodeD),
        secondBatch.getPosition(nodeE),
        secondBatch.getPosition(nodeF),
      ];

      for (final pos in positions) {
        expect((pos - b).distance, closeTo(170, 1));
      }
      for (var i = 0; i < positions.length; i++) {
        for (var j = i + 1; j < positions.length; j++) {
          expect(
            (positions[i] - positions[j]).distance,
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
      final cold = await algorithm
          .layout(nodes: nodes, edges: edges, size: largeCanvas)
          .first;

      final pinned = GraphLayoutBuilder(nodes: {nodeA, nodeB})
        ..setNodePosition(nodeA, cold.getPosition(nodeA))
        ..setNodePosition(nodeB, cold.getPosition(nodeB));
      final existing = pinned.build();

      final grown = await algorithm
          .relayout(
            existingLayout: existing,
            nodes: nodes,
            edges: edges,
            size: largeCanvas,
          )
          .first;

      expect(grown.getPosition(nodeC), cold.getPosition(nodeC));
      expect(grown.getPosition(nodeD), cold.getPosition(nodeD));
      final centre = largeCanvas.center(Offset.zero);
      final c = grown.getPosition(nodeC);
      final d = grown.getPosition(nodeD);
      expect((c - centre).distance, closeTo(170, 1));
      expect((d - centre).distance, closeTo(170, 1));
      expect(c.dy == centre.dy || d.dy == centre.dy, isFalse);
    });

    test('every input node has a position', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a');
      final nodes = {nodeA, nodeB};
      final edges = {edge('a', 'b')};

      final layout = await layoutOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
      );

      for (final node in nodes) {
        expect(layout.hasPosition(node), isTrue);
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

      final initial = await layoutOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
      );
      final again = await algorithm.relayout(
        existingLayout: initial,
        nodes: nodes,
        edges: edges,
        size: canvasSize,
      ).first;

      for (final node in nodes) {
        expect(again.getPosition(node), initial.getPosition(node));
      }
    });

    test('every input node has a position', () async {
      const algorithm = LayeredDagLayoutAlgorithm(rootIds: {'a'});
      final nodes = {nodeA, nodeB};
      final edges = {edge('a', 'b')};

      final layout = await layoutOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
      );

      for (final node in nodes) {
        expect(layout.hasPosition(node), isTrue);
      }
    });
  });
}
