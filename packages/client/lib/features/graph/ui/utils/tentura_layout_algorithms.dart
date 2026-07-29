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
    // Keep already-placed nodes. Park newcomers in a local fan around their
    // real parent, continuing parent−grandparent so expand does not reuse
    // global radial sectors (which fling siblings across the canvas).
    final hop = _computeHop(nodes: nodes, edges: edges, size: size);
    final placed = <String, Offset>{};
    final byId = <String, NodeBase>{
      for (final node in nodes) (node as NodeDetails).id: node,
    };
    final fallback = size.center(Offset.zero);

    for (final node in nodes) {
      final kept = existingLayout.getPositionOrNull(node);
      if (kept != null) {
        placed[(node as NodeDetails).id] = kept;
      }
    }

    final newcomersByParent = <String, List<String>>{};
    final orphanIds = <String>[];
    for (final node in nodes) {
      final id = (node as NodeDetails).id;
      if (placed.containsKey(id)) {
        continue;
      }
      final parentId = hop.parent[id];
      if (parentId == null) {
        orphanIds.add(id);
        continue;
      }
      newcomersByParent.putIfAbsent(parentId, () => []).add(id);
    }

    for (final id in orphanIds) {
      placed[id] = hop.positions[id] ?? fallback;
    }

    final parentIds = newcomersByParent.keys.toList()
      ..sort((a, b) {
        final da = hop.depth[a] ?? 0;
        final db = hop.depth[b] ?? 0;
        return da.compareTo(db);
      });

    final rootPos = placed[rootId] ?? hop.positions[rootId] ?? fallback;

    for (final parentId in parentIds) {
      final childIds = List<String>.from(newcomersByParent[parentId]!)..sort();
      final parentPos =
          placed[parentId] ?? hop.positions[parentId] ?? fallback;
      final grandparentId = hop.parent[parentId];
      final grandparentPos = grandparentId == null
          ? null
          : (placed[grandparentId] ?? hop.positions[grandparentId]);
      final direction = branchUnitDirection(
        parentPos: parentPos,
        grandparentPos: grandparentPos,
        rootPos: rootPos,
      );
      final fan = localFanPositions(
        parentPos: parentPos,
        direction: direction,
        childIds: childIds,
        canvasSize: size,
        ringGap: ringGap,
      );
      placed.addAll(fan);
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
