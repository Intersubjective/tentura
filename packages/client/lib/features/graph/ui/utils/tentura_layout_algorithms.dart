import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:collection/collection.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import '../../domain/entity/node_details.dart';
import '../../domain/layout/layered_dag_positions.dart';
import '../../domain/layout/radial_hop_positions.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/constellation_path_resolution.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';

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
      final childIds = byId.keys
          .where((id) => hop.parent[id] == parentId)
          .toList()
        ..sort();

      if (parentId == rootId) {
        for (final childId in childIds) {
          placed[childId] = hop.positions[childId] ?? fallback;
        }
        continue;
      }

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
      final maxChildSize = childIds
          .map((id) => (byId[id]! as NodeDetails).size)
          .fold(0.0, math.max);
      final minChord = math.max(
        amenityChordForRingGap(ringGap),
        maxChildSize + kFanSizePadding,
      );
      final fan = localFanPositions(
        parentPos: parentPos,
        direction: direction,
        childIds: childIds,
        canvasSize: size,
        ringGap: ringGap,
        minChord: minChord,
        rMax: ringGap * kFanRadiusMultiplier,
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

/// Deterministic three-pass layout for the Constellation field map.
final class ConstellationLayoutAlgorithm implements GraphLayoutAlgorithm {
  const ConstellationLayoutAlgorithm({
    required this.egoId,
    required this.paths,
    required this.keptPeerIds,
    required this.maxHops,
    required this.visibleRequestsByAuthor,
    required this.egoOwnRequestIds,
    this.pinnedPersonIds = const {},
    this.pinnedRequestIds = const {},
    this.supportPersonIds = const {},
    this.anchorByNodeId = const {},
    this.priorHints,
    this.nodeSizes = const {},
    this.spacing = 16,
    this.viewportClass = ConstellationViewportClass.expanded,
  });

  final String egoId;
  final ConstellationPathResolution paths;
  final Set<String> keptPeerIds;
  final int maxHops;
  final Map<String, List<String>> visibleRequestsByAuthor;
  final Set<String> egoOwnRequestIds;
  final Set<String> pinnedPersonIds;
  final Set<String> pinnedRequestIds;
  final Set<String> supportPersonIds;
  final Map<String, ConstellationAnchorPosition> anchorByNodeId;
  final ConstellationLayoutPriorHints? priorHints;
  final Map<String, ConstellationSize> nodeSizes;
  final double spacing;
  final ConstellationViewportClass viewportClass;

  @override
  Stream<GraphLayout> relayout({
    required GraphLayout existingLayout,
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    final mergedHints = _mergePriorHints(existingLayout, nodes);
    return _layoutStream(
      nodes: nodes,
      size: size,
      priorHints: mergedHints,
    );
  }

  @override
  Stream<GraphLayout> layout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    return _layoutStream(nodes: nodes, size: size, priorHints: priorHints);
  }

  Stream<GraphLayout> _layoutStream({
    required Set<NodeBase> nodes,
    required Size size,
    ConstellationLayoutPriorHints? priorHints,
  }) {
    return Stream.value(
      _buildLayout(
        nodes: nodes,
        size: size,
        priorHints: priorHints,
      ),
    );
  }

  ConstellationLayoutPriorHints? _mergePriorHints(
    GraphLayout existingLayout,
    Set<NodeBase> nodes,
  ) {
    final positions = <String, ConstellationPoint>{};
    final ring = <String, int>{};
    for (final node in nodes) {
      final id = (node as NodeDetails).id;
      final offset = existingLayout.getPositionOrNull(node);
      if (offset == null) {
        continue;
      }
      positions[id] = (x: offset.dx, y: offset.dy);
      if (priorHints?.ring.containsKey(id) ?? false) {
        ring[id] = priorHints!.ring[id]!;
      }
    }
    if (positions.isEmpty) {
      return priorHints;
    }
    return (
      positions: positions,
      ring: {...?priorHints?.ring, ...ring},
      viewportClass: viewportClass,
    );
  }

  GraphLayout _buildLayout({
    required Set<NodeBase> nodes,
    required Size size,
    ConstellationLayoutPriorHints? priorHints,
  }) {
    if (nodes.isEmpty) {
      return const GraphLayout.empty();
    }

    final computed = computeConstellationPlacedLayout(
      input: (
        egoId: egoId,
        paths: paths,
        automaticKeptPeerIds: keptPeerIds,
        pinnedPersonIds: pinnedPersonIds,
        pinnedRequestIds: pinnedRequestIds,
        supportPersonIds: supportPersonIds,
        anchorByNodeId: anchorByNodeId,
        priorHints: priorHints,
        nodeSizes: nodeSizes,
        satelliteRequestIdsByAuthor: visibleRequestsByAuthor,
        requestAuthorById: const {},
        egoOwnRequestIds: egoOwnRequestIds,
        spacing: spacing,
        maxHops: maxHops,
        viewportClass: viewportClass,
      ),
    );

    return _layoutFromPositions(
      nodes: nodes,
      positions: constellationLayoutPointsToOffsets(computed.positions),
      canvasSize: size,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationLayoutAlgorithm &&
          runtimeType == other.runtimeType &&
          egoId == other.egoId &&
          maxHops == other.maxHops &&
          spacing == other.spacing &&
          viewportClass == other.viewportClass &&
          paths == other.paths &&
          const SetEquality<String>().equals(keptPeerIds, other.keptPeerIds) &&
          const SetEquality<String>().equals(
            egoOwnRequestIds,
            other.egoOwnRequestIds,
          ) &&
          const SetEquality<String>().equals(
            pinnedPersonIds,
            other.pinnedPersonIds,
          ) &&
          const SetEquality<String>().equals(
            pinnedRequestIds,
            other.pinnedRequestIds,
          ) &&
          const SetEquality<String>().equals(
            supportPersonIds,
            other.supportPersonIds,
          ) &&
          const MapEquality<String, ConstellationAnchorPosition>().equals(
            anchorByNodeId,
            other.anchorByNodeId,
          ) &&
          priorHints == other.priorHints &&
          const MapEquality<String, ConstellationSize>().equals(
            nodeSizes,
            other.nodeSizes,
          ) &&
          const DeepCollectionEquality().equals(
            visibleRequestsByAuthor,
            other.visibleRequestsByAuthor,
          );

  @override
  int get hashCode => Object.hash(
    runtimeType,
    egoId,
    maxHops,
    spacing,
    viewportClass,
    paths,
    const SetEquality<String>().hash(keptPeerIds),
    const SetEquality<String>().hash(egoOwnRequestIds),
    const SetEquality<String>().hash(pinnedPersonIds),
    const SetEquality<String>().hash(pinnedRequestIds),
    const SetEquality<String>().hash(supportPersonIds),
    const MapEquality<String, ConstellationAnchorPosition>().hash(
      anchorByNodeId,
    ),
    priorHints,
    const MapEquality<String, ConstellationSize>().hash(nodeSizes),
    const DeepCollectionEquality().hash(visibleRequestsByAuthor),
  );
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
