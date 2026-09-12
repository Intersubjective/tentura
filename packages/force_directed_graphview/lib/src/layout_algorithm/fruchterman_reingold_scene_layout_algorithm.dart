import 'dart:async';
import 'dart:math';

import 'package:force_directed_graphview/src/layout_algorithm/graph_layout_request.dart';
import 'package:force_directed_graphview/src/layout_algorithm/layout_id_seed.dart';
import 'package:force_directed_graphview/src/layout_algorithm/scene_layout_algorithm.dart';
import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/scene_geometry.dart';

/// Scene-port Fruchterman–Reingold layout (pure Dart; ID-keyed request only).
class FruchtermanReingoldSceneLayoutAlgorithm implements SceneLayoutAlgorithm {
  const FruchtermanReingoldSceneLayoutAlgorithm({
    this.iterations = 100,
    this.relayoutIterationsMultiplier = 0.1,
    this.showIterations = false,
    this.temperature,
    this.optimalDistance,
  });

  final int iterations;
  final double relayoutIterationsMultiplier;
  final bool showIterations;
  final double? temperature;
  final double? optimalDistance;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    final nodes = request.nodesById;
    final edges = request.edgesById.values;
    final size = request.canvasSize;

    if (nodes.isEmpty) {
      yield GraphLayoutFrame(
        ticket: request.ticket,
        sequence: 0,
        positions: const {},
        isTerminal: true,
      );
      return;
    }

    var temp = temperature ??
        sqrt(size.width / 2 * size.height / 2) / 30;
    final k = optimalDistance ??
        sqrt(size.width * size.height / nodes.length);

    final positions = <GraphNodeId, ScenePoint>{};
    for (final node in nodes.values) {
      final prior = request.previous?.positions[node.id];
      positions[node.id] = prior ??
          _defaultInitialPosition(node.id, size);
    }

    final iterationCount = request.previous == null
        ? iterations
        : (iterations * relayoutIterationsMultiplier).toInt();

    var sequence = 0;

    for (var step = 0; step < iterationCount; step++) {
      if (temp < 1) {
        break;
      }

      _runIteration(
        positions: positions,
        nodes: nodes,
        edges: edges,
        size: size,
        temp: temp,
        k: k,
      );

      final vc = nodes.length * 2;
      temp *= 1 / (1 + 1 / (sqrt(step * (vc + 1) + vc)));

      if (showIterations) {
        yield GraphLayoutFrame(
          ticket: request.ticket,
          sequence: sequence++,
          positions: Map<GraphNodeId, ScenePoint>.from(positions),
          isTerminal: false,
        );
      }

      await Future<void>.delayed(Duration.zero);
    }

    if (!showIterations) {
      yield GraphLayoutFrame(
        ticket: request.ticket,
        sequence: sequence++,
        positions: Map<GraphNodeId, ScenePoint>.from(positions),
        isTerminal: false,
      );
    }

    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: sequence,
      positions: Map<GraphNodeId, ScenePoint>.from(positions),
      isTerminal: true,
    );
  }

  static ScenePoint _defaultInitialPosition(GraphNodeId id, SceneSize canvasSize) {
    final random = Random(graphNodeIdLayoutSeed(id));
    return ScenePoint(
      x: random.nextDouble() + canvasSize.width / 2,
      y: random.nextDouble() + canvasSize.height / 2,
    );
  }

  static void _runIteration({
    required Map<GraphNodeId, ScenePoint> positions,
    required Map<GraphNodeId, GraphLayoutNode> nodes,
    required Iterable<GraphLayoutEdge> edges,
    required SceneSize size,
    required double temp,
    required double k,
  }) {
    final width = size.width;
    final height = size.height;
    final repulsionDistanceCutoff = k * 3;
    final kSquared = k * k;

    double attraction(double x) => x * x / k;
    double clampDistance(double x) => (x < 0.01 ? 0.01 : x);

    final displacements = <GraphNodeId, ({double dx, double dy})>{
      for (final id in nodes.keys) id: (dx: 0, dy: 0),
    };

    final ids = nodes.keys.toList();
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final u = ids[i];
        final v = ids[j];
        final posU = positions[u]!;
        final posV = positions[v]!;
        final deltaX = posV.x - posU.x;
        final deltaY = posV.y - posU.y;
        final distance = clampDistance(sqrt(deltaX * deltaX + deltaY * deltaY));
        if (distance > repulsionDistanceCutoff) continue;

        final disp = kSquared / (distance * distance);
        final scaleX = deltaX / distance * disp;
        final scaleY = deltaY / distance * disp;
        final du = displacements[u]!;
        final dv = displacements[v]!;
        displacements[v] = (dx: dv.dx + scaleX, dy: dv.dy + scaleY);
        displacements[u] = (dx: du.dx - scaleX, dy: du.dy - scaleY);
      }
    }

    for (final edge in edges) {
      if (!nodes.containsKey(edge.sourceId) ||
          !nodes.containsKey(edge.destinationId)) {
        continue;
      }
      final sourcePos = positions[edge.sourceId]!;
      final destPos = positions[edge.destinationId]!;
      final deltaX = sourcePos.x - destPos.x;
      final deltaY = sourcePos.y - destPos.y;
      final distance = clampDistance(sqrt(deltaX * deltaX + deltaY * deltaY));
      final force = attraction(distance);
      final scaleX = deltaX / distance * force;
      final scaleY = deltaY / distance * force;
      final ds = displacements[edge.sourceId]!;
      final dd = displacements[edge.destinationId]!;
      displacements[edge.sourceId] = (dx: ds.dx - scaleX, dy: ds.dy - scaleY);
      displacements[edge.destinationId] =
          (dx: dd.dx + scaleX, dy: dd.dy + scaleY);
    }

    for (final entry in nodes.entries) {
      final id = entry.key;
      final node = entry.value;
      if (node.simulationFixed) continue;

      final displacement = displacements[id]!;
      final dist = sqrt(
        displacement.dx * displacement.dx + displacement.dy * displacement.dy,
      );
      if (dist < repulsionDistanceCutoff / 30) continue;

      final move = min(dist, temp);
      final scale = move / dist;
      final pos = positions[id]!;
      positions[id] = ScenePoint(
        x: pos.x + displacement.dx * scale,
        y: pos.y + displacement.dy * scale,
      );
    }

    for (final entry in nodes.entries) {
      final id = entry.key;
      final node = entry.value;
      final halfW = node.size.width / 2;
      final halfH = node.size.height / 2;
      final pos = positions[id]!;
      positions[id] = ScenePoint(
        x: pos.x.clamp(halfW, width - halfW),
        y: pos.y.clamp(halfH, height - halfH),
      );
    }
  }
}
