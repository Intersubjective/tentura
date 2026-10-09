// reconcileTopology matches existing members to targets by stable id. The
// work it does must grow linearly with the topology size: every id resolver
// is a callback into app code, so a quadratic scan multiplies that cost at
// large node counts.

import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/int_graph_controller.dart';

const _count = 600;

/// Generous per-member allowance for the resolver calls one reconcile pass may
/// make (matching, committing the topology to the scene, size resolution).
/// A linear implementation stays far below it; a pairwise scan over
/// [_count] members exceeds it by two orders of magnitude.
const _callsPerMemberBudget = 12;

/// Real time one id-resolver call costs in the timing test, standing in for
/// the work app code does inside a resolver.
const _resolverCost = Duration(microseconds: 2);

/// Wall-clock allowance for one reconcile at [_count] members when every id
/// resolver call costs [_resolverCost]. A linear pass needs roughly
/// 10-20 ms; a pairwise scan needs several hundred.
const _reconcileTimeBudget = Duration(milliseconds: 120);

typedef _Counted = ({
  GraphController<Node<int>, Edge<Node<int>, int>> controller,
  int Function() nodeIdCalls,
  int Function() edgeIdCalls,
});

_Counted _countingController() {
  var nodeIdCalls = 0;
  var edgeIdCalls = 0;
  final controller = GraphController<Node<int>, Edge<Node<int>, int>>(
    nodeIdOf: (node) {
      nodeIdCalls++;
      return testIntNodeId(node);
    },
    edgeIdOf: (edge) {
      edgeIdCalls++;
      return edge.data.toString();
    },
    nodeSizeOf: (node) => node.size,
    nodeSimulationFixedOf: (node) => node.pinned,
    edgeSourceOf: (edge) => edge.source,
    edgeDestinationOf: (edge) => edge.destination,
  );
  return (
    controller: controller,
    nodeIdCalls: () => nodeIdCalls,
    edgeIdCalls: () => edgeIdCalls,
  );
}

Set<Node<int>> _nodes({double size = 50, bool reversed = false}) {
  final ids = [for (var i = 0; i < _count; i++) i];
  return {
    for (final i in reversed ? ids.reversed : ids)
      Node<int>(data: i, size: size),
  };
}

Set<Edge<Node<int>, int>> _edges(
  Set<Node<int>> nodes, {
  bool reversed = false,
}) {
  final list = nodes.toList()..sort((a, b) => a.data.compareTo(b.data));
  final ids = [for (var i = 0; i < list.length - 1; i++) i];
  return {
    for (final i in reversed ? ids.reversed : ids)
      Edge(source: list[i], destination: list[i + 1], data: i),
  };
}

void main() {
  test('reconcile of an unchanged topology makes linearly many id lookups', () {
    final counted = _countingController();
    final nodes = _nodes();
    final edges = _edges(nodes);
    counted.controller.reconcileTopology(nodes, edges);

    final nodeBefore = counted.nodeIdCalls();
    final edgeBefore = counted.edgeIdCalls();
    counted.controller.reconcileTopology(
      {..._nodes()},
      {..._edges(_nodes())},
    );

    expect(
      counted.nodeIdCalls() - nodeBefore,
      lessThanOrEqualTo(_count * _callsPerMemberBudget),
      reason: 'node id resolver calls during one reconcile',
    );
    expect(
      counted.edgeIdCalls() - edgeBefore,
      lessThanOrEqualTo(_count * _callsPerMemberBudget),
      reason: 'edge id resolver calls during one reconcile',
    );
  });

  test(
      'reconcile that replaces every payload in reverse order makes linearly '
      'many id lookups', () {
    final counted = _countingController();
    final nodes = _nodes();
    counted.controller.reconcileTopology(nodes, _edges(nodes));

    final nodeBefore = counted.nodeIdCalls();
    final edgeBefore = counted.edgeIdCalls();
    final resized = _nodes(size: 80, reversed: true);
    counted.controller.reconcileTopology(
      resized,
      _edges(resized, reversed: true),
    );

    expect(
      counted.nodeIdCalls() - nodeBefore,
      lessThanOrEqualTo(_count * _callsPerMemberBudget),
      reason: 'node id resolver calls during one reconcile',
    );
    expect(
      counted.edgeIdCalls() - edgeBefore,
      lessThanOrEqualTo(_count * _callsPerMemberBudget),
      reason: 'edge id resolver calls during one reconcile',
    );
  });

  test('reconcile keeps payload replacement, additions and removals by id', () {
    final counted = _countingController();
    final nodes = _nodes();
    counted.controller.reconcileTopology(nodes, _edges(nodes));

    final next = {
      const Node<int>(data: 0, size: 99),
      for (var i = 10; i < _count; i++) Node<int>(data: i, size: 50),
      const Node<int>(data: 1000, size: 50),
    };
    counted.controller.reconcileTopology(next, const {});

    final byId = {
      for (final node in counted.controller.nodes) node.data: node,
    };
    expect(byId.length, next.length);
    expect(byId[0]!.size, 99);
    expect(byId.containsKey(5), isFalse);
    expect(byId.containsKey(1000), isTrue);
    expect(counted.controller.edges, isEmpty);
  });

  test(
    'reconcile keeps surviving edges and applies edge additions, removals and '
    'rewiring by id',
    () {
      final counted = _countingController();
      final nodes = _nodes();
      counted.controller.reconcileTopology(nodes, _edges(nodes));

      // Same node ids, but every node payload is replaced.
      final resized = _nodes(size: 80, reversed: true);
      final byData = {for (final node in resized) node.data: node};
      Edge<Node<int>, int> edge(int id, int from, int to) =>
          Edge(source: byData[from]!, destination: byData[to]!, data: id);
      final next = {
        // 0..299 survive with the same endpoints.
        for (var i = 0; i < 300; i++) edge(i, i, i + 1),
        // 300..399 keep their id but are rewired to skip a node.
        for (var i = 300; i < 400; i++) edge(i, i, i + 2),
        // 400..598 are removed; 1000..1009 are new.
        for (var i = 0; i < 10; i++) edge(1000 + i, i, _count - 1 - i),
      };
      counted.controller.reconcileTopology(resized, next);

      final edgesById = {
        for (final e in counted.controller.edges) e.data: e,
      };
      expect(edgesById.length, next.length);
      for (var i = 0; i < 300; i++) {
        expect(edgesById[i]!.source.data, i, reason: 'source of edge $i');
        expect(edgesById[i]!.destination.data, i + 1, reason: 'dest of $i');
      }
      for (var i = 300; i < 400; i++) {
        expect(edgesById[i]!.source.data, i, reason: 'source of edge $i');
        expect(edgesById[i]!.destination.data, i + 2, reason: 'dest of $i');
      }
      for (var i = 400; i < _count - 1; i++) {
        expect(edgesById.containsKey(i), isFalse, reason: 'edge $i removed');
      }
      for (var i = 0; i < 10; i++) {
        expect(edgesById[1000 + i]!.source.data, i);
        expect(edgesById[1000 + i]!.destination.data, _count - 1 - i);
      }
      // Surviving edges point at the current node payloads.
      expect(edgesById[0]!.source.size, 80);
      expect(counted.controller.nodes.length, _count);
    },
  );

  test(
    'reconcile at 600 members stays within the wall-clock budget when each '
    'id lookup costs real time',
    () {
      final spin = Stopwatch()..start();
      void pay() {
        final start = spin.elapsedMicroseconds;
        while (spin.elapsedMicroseconds - start <
            _resolverCost.inMicroseconds) {}
      }

      final controller = GraphController<Node<int>, Edge<Node<int>, int>>(
        nodeIdOf: (node) {
          pay();
          return testIntNodeId(node);
        },
        edgeIdOf: (edge) {
          pay();
          return edge.data.toString();
        },
        nodeSizeOf: (node) => node.size,
        nodeSimulationFixedOf: (node) => node.pinned,
        edgeSourceOf: (edge) => edge.source,
        edgeDestinationOf: (edge) => edge.destination,
      );
      final nodes = _nodes();
      controller.reconcileTopology(nodes, _edges(nodes));

      var best = const Duration(days: 1);
      for (var run = 0; run < 3; run++) {
        final next = _nodes(size: run.isEven ? 80 : 50, reversed: run.isEven);
        final nextEdges = _edges(next, reversed: run.isEven);
        final watch = Stopwatch()..start();
        controller.reconcileTopology(next, nextEdges);
        watch.stop();
        if (watch.elapsed < best) best = watch.elapsed;
      }

      expect(
        best,
        lessThan(_reconcileTimeBudget),
        reason: 'fastest of three reconciles at $_count members',
      );
    },
  );
}
