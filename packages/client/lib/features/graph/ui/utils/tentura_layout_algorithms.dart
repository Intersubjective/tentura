import 'dart:ui' show Offset, Size;

import 'package:collection/collection.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import '../../domain/entity/node_details.dart';
import '../../domain/layout/layered_dag_positions.dart';
import '../../domain/layout/radial_hop_positions.dart';

final class RadialHopLayoutAlgorithm implements GraphLayoutAlgorithm {
  const RadialHopLayoutAlgorithm({
    required this.rootId,
    this.ringGap = 170,
  });

  final String rootId;
  final double ringGap;

  @override
  Stream<GraphLayout> layout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    return Stream.value(_buildLayout(nodes: nodes, edges: edges, size: size));
  }

  @override
  Stream<GraphLayout> relayout({
    required GraphLayout existingLayout,
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    // Keep already-placed nodes where they are. Park brand-new nodes next to
    // their (possibly pinned) BFS parent using the fresh layout's parent→child
    // offset, so expand does not fling children across the canvas.
    final hop = _computeHop(nodes: nodes, edges: edges, size: size);
    final placed = <String, Offset>{};
    final byId = <String, NodeBase>{
      for (final node in nodes) (node as NodeDetails).id: node,
    };

    for (final node in nodes) {
      final kept = existingLayout.getPositionOrNull(node);
      if (kept != null) {
        placed[(node as NodeDetails).id] = kept;
      }
    }

    final newcomers = nodes
        .where((node) => !placed.containsKey((node as NodeDetails).id))
        .toList()
      ..sort((a, b) {
        final da = hop.depth[(a as NodeDetails).id] ?? 0;
        final db = hop.depth[(b as NodeDetails).id] ?? 0;
        return da.compareTo(db);
      });

    final fallback = size.center(Offset.zero);
    for (final node in newcomers) {
      final id = (node as NodeDetails).id;
      final freshPos = hop.positions[id] ?? fallback;
      final parentId = hop.parent[id];
      if (parentId != null) {
        final parentPos = placed[parentId] ?? hop.positions[parentId];
        final freshParent = hop.positions[parentId];
        if (parentPos != null && freshParent != null) {
          placed[id] = clampLayoutPosition(
            parentPos + (freshPos - freshParent),
            size,
          );
          continue;
        }
      }
      placed[id] = freshPos;
    }

    final builder = GraphLayoutBuilder(nodes: nodes);
    for (final entry in byId.entries) {
      builder.setNodePosition(
        entry.value,
        placed[entry.key] ?? fallback,
      );
    }
    return Stream.value(builder.build());
  }

  GraphLayout _buildLayout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    if (nodes.isEmpty) {
      return const GraphLayout.empty();
    }

    final hop = _computeHop(nodes: nodes, edges: edges, size: size);
    return _layoutFromPositions(
      nodes: nodes,
      positions: hop.positions,
      canvasSize: size,
    );
  }

  RadialHopLayout _computeHop({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    final nodeIds = nodes.map((node) => (node as NodeDetails).id).toSet();
    final edgeIds = edges
        .map(
          (edge) => (
            (edge.source as NodeDetails).id,
            (edge.destination as NodeDetails).id,
          ),
        )
        .toSet();

    return computeRadialHopLayout(
      nodeIds: nodeIds,
      edges: edgeIds,
      rootId: rootId,
      canvasSize: size,
      ringGap: ringGap,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RadialHopLayoutAlgorithm &&
          runtimeType == other.runtimeType &&
          rootId == other.rootId &&
          ringGap == other.ringGap;

  @override
  int get hashCode => Object.hash(runtimeType, rootId, ringGap);
}

final class LayeredDagLayoutAlgorithm implements GraphLayoutAlgorithm {
  const LayeredDagLayoutAlgorithm({
    required this.rootIds,
    this.layerGap = 150,
    this.columnGap = 130,
  });

  final Set<String> rootIds;
  final double layerGap;
  final double columnGap;

  @override
  Stream<GraphLayout> layout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    return Stream.value(_buildLayout(nodes: nodes, edges: edges, size: size));
  }

  @override
  Stream<GraphLayout> relayout({
    required GraphLayout existingLayout,
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    return layout(nodes: nodes, edges: edges, size: size);
  }

  GraphLayout _buildLayout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    if (nodes.isEmpty) {
      return const GraphLayout.empty();
    }

    final nodeIds = nodes.map((node) => (node as NodeDetails).id).toSet();
    final edgeIds = edges
        .map(
          (edge) => (
            (edge.source as NodeDetails).id,
            (edge.destination as NodeDetails).id,
          ),
        )
        .toSet();

    final positions = layeredDagPositions(
      nodeIds: nodeIds,
      edges: edgeIds,
      rootIds: rootIds,
      canvasSize: size,
      layerGap: layerGap,
      columnGap: columnGap,
    );

    return _layoutFromPositions(
      nodes: nodes,
      positions: positions,
      canvasSize: size,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayeredDagLayoutAlgorithm &&
          runtimeType == other.runtimeType &&
          layerGap == other.layerGap &&
          columnGap == other.columnGap &&
          const SetEquality<String>().equals(rootIds, other.rootIds);

  @override
  int get hashCode => Object.hash(
    runtimeType,
    layerGap,
    columnGap,
    const SetEquality<String>().hash(rootIds),
  );
}

GraphLayout _layoutFromPositions({
  required Set<NodeBase> nodes,
  required Map<String, Offset> positions,
  required Size canvasSize,
}) {
  final builder = GraphLayoutBuilder(nodes: nodes);
  final fallback = canvasSize.center(Offset.zero);
  for (final node in nodes) {
    final id = (node as NodeDetails).id;
    builder.setNodePosition(node, positions[id] ?? fallback);
  }
  return builder.build();
}
