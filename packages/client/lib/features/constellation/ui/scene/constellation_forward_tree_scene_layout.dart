import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/features/forward/domain/entity/forward_graph.dart';

/// One-shot radial tree layout for forward-tree «Arrange as tree» (#774 31ve.6).
///
/// Positions every person node around the author by BFS depth along
/// [ForwardGraphEdge] endpoints. Session-local — paired with a fixed-layout
/// restore when leaving «Arrange as tree».
class ConstellationForwardTreeRadialLayout implements SceneLayoutAlgorithm {
  ConstellationForwardTreeRadialLayout({
    required this.authorPersonId,
    required this.edges,
    required this.personGraphIds,
  });

  final String authorPersonId;
  final List<ForwardGraphEdge> edges;
  final Set<GraphNodeId> personGraphIds;

  static const _layerRadius = 120.0;

  String _endpointDomain(ForwardGraphEdge e, {required bool sender}) {
    final anon = sender ? e.senderAnonymousCount : e.recipientAnonymousCount;
    if (anon > 0) {
      return sender ? 'ftghost:${e.id}:s' : 'ftghost:${e.id}:r';
    }
    return sender ? e.senderId : e.recipientId;
  }

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    final centre = Offset(
      request.canvasSize.width / 2,
      request.canvasSize.height / 2,
    );
    final authorGid = 'fp:$authorPersonId';

    final adj = <String, Set<String>>{};
    for (final e in edges) {
      final a = _endpointDomain(e, sender: true);
      final b = _endpointDomain(e, sender: false);
      adj.putIfAbsent(a, () => {}).add(b);
      adj.putIfAbsent(b, () => {}).add(a);
    }

    final depth = <String, int>{authorPersonId: 0};
    final queue = <String>[authorPersonId];
    while (queue.isNotEmpty) {
      final u = queue.removeAt(0);
      for (final v in adj[u] ?? const <String>{}) {
        if (depth.containsKey(v)) continue;
        depth[v] = depth[u]! + 1;
        queue.add(v);
      }
    }

    final byLayer = <int, List<String>>{};
    for (final gid in personGraphIds) {
      if (!gid.startsWith('fp:')) continue;
      final pid = gid.substring(3);
      final d = depth[pid];
      if (d == null) continue;
      byLayer.putIfAbsent(d, () => []).add(pid);
    }

    final positions = <GraphNodeId, ScenePoint>{};
    positions[authorGid] = ScenePoint(x: centre.dx, y: centre.dy);

    for (final MapEntry(:key, :value) in byLayer.entries) {
      final layer = key;
      if (layer == 0) continue;
      final ids = [...value]..sort();
      final n = ids.length;
      final radius = layer * _layerRadius;
      for (var i = 0; i < n; i++) {
        final angle = -math.pi / 2 + (i * 2 * math.pi / n);
        final pid = ids[i];
        positions['fp:$pid'] = ScenePoint(
          x: centre.dx + radius * math.cos(angle),
          y: centre.dy + radius * math.sin(angle),
        );
      }
    }

    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: positions,
      isTerminal: true,
    );
  }
}
