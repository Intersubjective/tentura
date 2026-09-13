import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:collection/collection.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import '../../domain/entity/node_details.dart';
import '../../domain/layout/layered_dag_positions.dart';
import '../../domain/layout/radial_hop_positions.dart';
import 'graph_scene_ids.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/constellation_path_resolution.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';

final class RadialHopLayoutAlgorithm implements SceneLayoutAlgorithm {
  const RadialHopLayoutAlgorithm({
    required this.rootId,
    this.ringGap = 170,
  });

  /// Layout domain id of the radial root (typically the viewer user id).
  final String rootId;
  final double ringGap;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield _frame(request, _computePositions(request));
  }

  Map<GraphNodeId, ScenePoint> _computePositions(GraphLayoutRequest request) {
    if (request.nodeIds.isEmpty) {
      return const {};
    }

    final graphIdByDomain = tenturaGraphIdsByDomainId(request.nodeIds);
    final domainNodeIds = graphIdByDomain.keys.toSet();
    final domainEdges = _domainEdges(request);
    final size = _canvasSize(request);

    final hop = computeRadialHopLayout(
      nodeIds: domainNodeIds,
      edges: domainEdges,
      rootId: rootId,
      canvasSize: size,
      ringGap: ringGap,
    );

    final previous = request.previous?.positions ?? const {};
    if (previous.isEmpty) {
      return _positionsFromDomainMap(
        graphIdByDomain: graphIdByDomain,
        domainPositions: hop.positions,
        canvasSize: size,
      );
    }

    return _relayoutPositions(
      request: request,
      graphIdByDomain: graphIdByDomain,
      hop: hop,
      canvasSize: size,
      previous: previous,
    );
  }

  Map<GraphNodeId, ScenePoint> _relayoutPositions({
    required GraphLayoutRequest request,
    required Map<String, GraphNodeId> graphIdByDomain,
    required RadialHopLayout hop,
    required Size canvasSize,
    required Map<GraphNodeId, ScenePoint> previous,
  }) {
    final placed = <String, ScenePoint>{};
    final fallback = _centerPoint(canvasSize);

    for (final entry in graphIdByDomain.entries) {
      final graphId = entry.value;
      final kept = previous[graphId];
      if (kept != null) {
        placed[entry.key] = kept;
      }
    }

    final newcomersByParent = <String, List<String>>{};
    final orphanIds = <String>[];
    for (final domainId in graphIdByDomain.keys) {
      if (placed.containsKey(domainId)) {
        continue;
      }
      final parentId = hop.parent[domainId];
      if (parentId == null) {
        orphanIds.add(domainId);
        continue;
      }
      newcomersByParent.putIfAbsent(parentId, () => []).add(domainId);
    }

    for (final id in orphanIds) {
      final offset = hop.positions[id];
      placed[id] = offset == null
          ? fallback
          : ScenePoint(x: offset.dx, y: offset.dy);
    }

    final parentIds = newcomersByParent.keys.toList()
      ..sort((a, b) {
        final da = hop.depth[a] ?? 0;
        final db = hop.depth[b] ?? 0;
        return da.compareTo(db);
      });

    final rootPos = placed[rootId] ??
        _sceneFromOffset(hop.positions[rootId]) ??
        fallback;

    for (final parentId in parentIds) {
      final childDomainIds = graphIdByDomain.keys
          .where((id) => hop.parent[id] == parentId)
          .toList()
        ..sort();

      if (parentId == rootId) {
        for (final childId in childDomainIds) {
          final offset = hop.positions[childId];
          placed[childId] = offset == null
              ? fallback
              : ScenePoint(x: offset.dx, y: offset.dy);
        }
        continue;
      }

      final parentPos = placed[parentId] ??
          _sceneFromOffset(hop.positions[parentId]) ??
          fallback;
      final grandparentId = hop.parent[parentId];
      final grandparentPos = grandparentId == null
          ? null
          : (placed[grandparentId] ??
              _sceneFromOffset(hop.positions[grandparentId]));
      final direction = branchUnitDirection(
        parentPos: Offset(parentPos.x, parentPos.y),
        grandparentPos: grandparentPos == null
            ? null
            : Offset(grandparentPos.x, grandparentPos.y),
        rootPos: Offset(rootPos.x, rootPos.y),
      );
      final maxChildSize = childDomainIds
          .map(
            (id) => request.nodesById[graphIdByDomain[id]!]!.size.height,
          )
          .fold(0.0, math.max);
      final minChord = math.max(
        amenityChordForRingGap(ringGap),
        maxChildSize + kFanSizePadding,
      );
      final fan = localFanPositions(
        parentPos: Offset(parentPos.x, parentPos.y),
        direction: direction,
        childIds: childDomainIds,
        canvasSize: canvasSize,
        ringGap: ringGap,
        minChord: minChord,
        rMax: ringGap * kFanRadiusMultiplier,
      );
      for (final entry in fan.entries) {
        placed[entry.key] = ScenePoint(x: entry.value.dx, y: entry.value.dy);
      }
    }

    final positions = <GraphNodeId, ScenePoint>{};
    for (final entry in graphIdByDomain.entries) {
      positions[entry.value] =
          placed[entry.key] ?? fallback;
    }
    return positions;
  }

  Set<(String, String)> _domainEdges(GraphLayoutRequest request) {
    final edges = <(String, String)>{};
    for (final edge in request.edgesById.values) {
      edges.add((
        tenturaLayoutDomainId(edge.sourceId),
        tenturaLayoutDomainId(edge.destinationId),
      ));
    }
    return edges;
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

final class LayeredDagLayoutAlgorithm implements SceneLayoutAlgorithm {
  const LayeredDagLayoutAlgorithm({
    required this.rootIds,
    this.layerGap = 150,
    this.columnGap = 130,
  });

  final Set<String> rootIds;
  final double layerGap;
  final double columnGap;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield _frame(request, _computePositions(request));
  }

  Map<GraphNodeId, ScenePoint> _computePositions(GraphLayoutRequest request) {
    if (request.nodeIds.isEmpty) {
      return const {};
    }

    final graphIdByDomain = tenturaGraphIdsByDomainId(request.nodeIds);
    final domainNodeIds = graphIdByDomain.keys.toSet();
    final domainEdges = <(String, String)>{
      for (final edge in request.edgesById.values)
        (
          tenturaLayoutDomainId(edge.sourceId),
          tenturaLayoutDomainId(edge.destinationId),
        ),
    };
    final size = _canvasSize(request);

    final positions = layeredDagPositions(
      nodeIds: domainNodeIds,
      edges: domainEdges,
      rootIds: rootIds,
      canvasSize: size,
      layerGap: layerGap,
      columnGap: columnGap,
    );

    return _positionsFromDomainMap(
      graphIdByDomain: graphIdByDomain,
      domainPositions: positions,
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

/// ID-keyed deterministic layout for the Constellation field map.
final class ConstellationSceneLayoutAlgorithm implements SceneLayoutAlgorithm {
  const ConstellationSceneLayoutAlgorithm({
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
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield _frame(request, _computePositions(request));
  }

  Map<GraphNodeId, ScenePoint> _computePositions(GraphLayoutRequest request) {
    if (request.nodeIds.isEmpty) {
      return const {};
    }

    final graphIdByDomain = tenturaGraphIdsByDomainId(request.nodeIds);
    final mergedHints = _mergePriorHints(request);
    final sizes = <String, ConstellationSize>{
      ...nodeSizes,
      for (final entry in graphIdByDomain.entries)
        entry.key: (
          width: request.nodesById[entry.value]!.size.width,
          height: request.nodesById[entry.value]!.size.height,
        ),
    };

    final domainPositions = _computeConstellationDomainPositions(
      priorHints: mergedHints,
      nodeSizes: sizes,
    );

    return _positionsFromDomainMap(
      graphIdByDomain: graphIdByDomain,
      domainPositions: domainPositions,
      canvasSize: _canvasSize(request),
    );
  }

  Map<String, Offset> _computeConstellationDomainPositions({
    ConstellationLayoutPriorHints? priorHints,
    required Map<String, ConstellationSize> nodeSizes,
  }) {
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
    return constellationLayoutPointsToOffsets(computed.positions);
  }

  ConstellationLayoutPriorHints? _mergePriorHints(GraphLayoutRequest request) {
    final previous = request.previous?.positions ?? const {};
    if (previous.isEmpty) {
      return priorHints;
    }

    final graphIdByDomain = tenturaGraphIdsByDomainId(request.nodeIds);
    final positions = <String, ConstellationPoint>{};
    final ring = <String, int>{...?priorHints?.ring};
    for (final entry in graphIdByDomain.entries) {
      final point = previous[entry.value];
      if (point == null) {
        continue;
      }
      positions[entry.key] = (x: point.x, y: point.y);
      if (priorHints?.ring.containsKey(entry.key) ?? false) {
        ring[entry.key] = priorHints!.ring[entry.key]!;
      }
    }
    if (positions.isEmpty) {
      return priorHints;
    }
    return (
      positions: positions,
      ring: ring,
      viewportClass: viewportClass,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationSceneLayoutAlgorithm &&
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

GraphLayoutFrame _frame(
  GraphLayoutRequest request,
  Map<GraphNodeId, ScenePoint> positions,
) =>
    GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: positions,
      isTerminal: true,
    );

Size _canvasSize(GraphLayoutRequest request) => Size(
  request.canvasSize.width,
  request.canvasSize.height,
);

ScenePoint _centerPoint(Size canvasSize) {
  final center = canvasSize.center(Offset.zero);
  return ScenePoint(x: center.dx, y: center.dy);
}

ScenePoint? _sceneFromOffset(Offset? offset) =>
    offset == null ? null : ScenePoint(x: offset.dx, y: offset.dy);

Map<GraphNodeId, ScenePoint> _positionsFromDomainMap({
  required Map<String, GraphNodeId> graphIdByDomain,
  required Map<String, Offset> domainPositions,
  required Size canvasSize,
}) {
  final fallback = _centerPoint(canvasSize);
  return {
    for (final entry in graphIdByDomain.entries)
      entry.value:
          _sceneFromOffset(domainPositions[entry.key]) ?? fallback,
  };
}

