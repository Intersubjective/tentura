import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/domain/entity/profile.dart';

import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';

void main() {
  late GraphController<NodeDetails, EdgeDetails> controller;

  setUp(() {
    controller = createTenturaGraphController();
  });

  test('GraphController is empty by default', () {
    expect(controller.nodes, isEmpty);
    expect(controller.edges, isEmpty);
  });

  final node1 = UserNode(user: Profile(id: 'U1'));
  final node2 = UserNode(user: Profile(id: 'U2'));
  final edge12 = EdgeDetails(
    source: node1,
    destination: node2,
    color: const Color(0xFF000000),
  );

  test('reconcileTopology adds and removes nodes', () {
    controller.reconcileTopology({node1}, const {});
    expect(controller.nodes.contains(node1), true);

    controller.reconcileTopology(const {}, const {});
    expect(controller.nodes, isEmpty);
  });

  test('reconcileTopology adds and removes edges', () {
    controller.reconcileTopology({node1, node2}, {edge12});
    expect(controller.edges.contains(edge12), true);

    controller.reconcileTopology({node1, node2}, const {});
    expect(controller.edges, isEmpty);
  });
}
