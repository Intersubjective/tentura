import 'dart:ui' show Offset, Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/domain/layout/radial_hop_positions.dart';
import 'package:tentura/features/graph/ui/utils/tentura_layout_algorithms.dart';

void main() {
  const canvasSize = Size(500, 500);

  final nodeA = UserNode(user: Profile(id: 'a'));
  final nodeB = UserNode(user: Profile(id: 'b'));
  final nodeC = UserNode(user: Profile(id: 'c'));

  EdgeDetails<NodeDetails> edge(String srcId, String dstId) {
    final src = srcId == 'a'
        ? nodeA
        : srcId == 'b'
        ? nodeB
        : nodeC;
    final dst = dstId == 'a'
        ? nodeA
        : dstId == 'b'
        ? nodeB
        : nodeC;
    return EdgeDetails(
      source: src,
      destination: dst,
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

    test('relayout parks new children next to a pinned parent', () async {
      const algorithm = RadialHopLayoutAlgorithm(rootId: 'a');
      final nodes = {nodeA, nodeB};
      final edges = {edge('a', 'b')};

      final initial = await layoutOnce(
        algorithm,
        nodes: nodes,
        edges: edges,
      );

      // Nudge B away from its fresh seat so absolute placement would diverge.
      final shiftedB = initial.getPosition(nodeB) + const Offset(120, 80);
      final pinned = GraphLayoutBuilder(nodes: nodes)
        ..setNodePosition(nodeA, initial.getPosition(nodeA))
        ..setNodePosition(nodeB, shiftedB);
      final existing = pinned.build();

      final grown = await algorithm
          .relayout(
            existingLayout: existing,
            nodes: {nodeA, nodeB, nodeC},
            edges: {edge('a', 'b'), edge('b', 'c')},
            size: canvasSize,
          )
          .first;

      expect(grown.getPosition(nodeB), shiftedB);
      final fresh = await layoutOnce(
        algorithm,
        nodes: {nodeA, nodeB, nodeC},
        edges: {edge('a', 'b'), edge('b', 'c')},
      );
      final expectedDelta =
          fresh.getPosition(nodeC) - fresh.getPosition(nodeB);
      expect(
        grown.getPosition(nodeC),
        clampLayoutPosition(shiftedB + expectedDelta, canvasSize),
      );
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
