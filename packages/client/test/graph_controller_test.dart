import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/domain/entity/profile.dart';

import 'package:tentura/features/graph/domain/entity/node_details.dart';

GraphNodeId _testNodeId(NodeBase node) => 'n:${identityHashCode(node)}';

GraphEdgeId _testEdgeId(EdgeBase edge) =>
    'e:${identityHashCode(edge.source)}->${identityHashCode(edge.destination)}';

void main() {
  late GraphController<Node<UserNode>, Edge<Node<UserNode>, Object?>> controller;

  setUp(() {
    controller = GraphController(
      nodeIdOf: _testNodeId,
      edgeIdOf: _testEdgeId,
    );
  });

  test('GraphController is empty by default', () {
    expect(controller.nodes, isEmpty);
    expect(controller.edges, isEmpty);
  });

  const node1 = Node(
    data: UserNode(
      user: Profile(id: 'U1'),
    ),
    size: 100,
  );
  const node2 = Node(
    data: UserNode(
      user: Profile(id: 'U2'),
    ),
    size: 100,
  );
  const edge12 = Edge(
    source: node1,
    destination: node2,
    data: null,
  );

  test('Add and remove node', () {
    controller.mutate((mutator) => mutator.addNode(node1));
    expect(controller.nodes.contains(node1), true);

    controller.mutate((mutator) => mutator.removeNode(node1));
    expect(controller.nodes.contains(node1), false);
  });

  test('Add and remove edge', () {
    controller.mutate((mutator) {
      mutator
        ..addNode(node1)
        ..addNode(node2)
        ..addEdge(edge12);
    });

    expect(controller.edges.contains(edge12), true);

    controller.mutate((mutator) => mutator.removeEdge(edge12));
    expect(controller.edges.contains(edge12), false);
  });

  test('Throws when adding existing node', () {
    controller.mutate((mutator) => mutator.addNode(node1));

    expect(
      () => controller.mutate((mutator) => mutator.addNode(node1)),
      throwsA(isInstanceOf<StateError>()),
    );
  });

  test('Throws when removing non-existing node', () {
    expect(
      () => controller.mutate((mutator) => mutator.removeNode(node1)),
      throwsA(isInstanceOf<StateError>()),
    );
  });

  test('Throws when adding edge with non-existing node', () {
    controller.mutate((mutator) => mutator.addNode(node1));

    expect(
      () => controller.mutate((mutator) => mutator.addEdge(edge12)),
      throwsA(isInstanceOf<StateError>()),
    );
  });

  test('Throws when removing non-existing edge', () {
    expect(
      () => controller.mutate((mutator) => mutator.removeEdge(edge12)),
      throwsA(isInstanceOf<StateError>()),
    );
  });
}
