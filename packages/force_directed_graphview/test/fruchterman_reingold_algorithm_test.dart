import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

void main() {
  const node1 = Node(data: 1, size: 100);
  const node2 = Node(data: 2, size: 100);
  const edge12 = Edge(source: node1, destination: node2, data: null);

  test('layout completes when input node set is mutated mid-run', () async {
    final mutableNodes = <NodeBase>{node1};
    const algorithm = FruchtermanReingoldAlgorithm(
      iterations: 20,
      showIterations: true,
    );

    var yieldedLayouts = 0;
    await for (final _ in algorithm.layout(
      nodes: mutableNodes,
      edges: const {},
      size: const Size(500, 500),
    )) {
      yieldedLayouts++;
      if (yieldedLayouts == 1) {
        mutableNodes.add(node2);
      }
    }

    expect(yieldedLayouts, greaterThan(0));
  });

  test('layout ignores edges whose endpoints are outside the snapshot', () async {
    const algorithm = FruchtermanReingoldAlgorithm(iterations: 5);

    final layouts = await algorithm
        .layout(
          nodes: {node1},
          edges: {edge12},
          size: const Size(500, 500),
        )
        .toList();

    expect(layouts, isNotEmpty);
    expect(layouts.last.hasPosition(node1), isTrue);
  });
}
