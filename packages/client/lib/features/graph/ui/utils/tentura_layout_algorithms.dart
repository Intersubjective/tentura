import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/constellation/ui/util/constellation_perf.dart';

import '../../domain/entity/node_details.dart';
import '../../domain/layout/layered_dag_positions.dart';
import '../../domain/layout/radial_hop_positions.dart';
import 'graph_scene_ids.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/layout/constellation_layout_engine.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/layout/spatial_index.dart';
import 'package:tentura/ui/utils/frame_slice_scheduler.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

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
    required LSize canvasSize,
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
          : ScenePoint(x: offset.x, y: offset.y);
    }

    final parentIds = newcomersByParent.keys.toList()
      ..sort((a, b) {
        final da = hop.depth[a] ?? 0;
        final db = hop.depth[b] ?? 0;
        return da.compareTo(db);
      });

    final rootPos = placed[rootId] ??
        _sceneFromPoint(hop.positions[rootId]) ??
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
              : ScenePoint(x: offset.x, y: offset.y);
        }
        continue;
      }

      final parentPos = placed[parentId] ??
          _sceneFromPoint(hop.positions[parentId]) ??
          fallback;
      final grandparentId = hop.parent[parentId];
      final grandparentPos = grandparentId == null
          ? null
          : (placed[grandparentId] ??
              _sceneFromPoint(hop.positions[grandparentId]));
      final direction = branchUnitDirection(
        parentPos: (x: parentPos.x, y: parentPos.y),
        grandparentPos: grandparentPos == null
            ? null
            : (x: grandparentPos.x, y: grandparentPos.y),
        rootPos: (x: rootPos.x, y: rootPos.y),
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
        parentPos: (x: parentPos.x, y: parentPos.y),
        direction: direction,
        childIds: childDomainIds,
        canvasSize: canvasSize,
        ringGap: ringGap,
        minChord: minChord,
        rMax: ringGap * kFanRadiusMultiplier,
      );
      for (final entry in fan.entries) {
        placed[entry.key] = ScenePoint(x: entry.value.x, y: entry.value.y);
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
    this.forgetPriorHintNodeIds = const {},
    this.priorHints,
    this.nodeSizes = const {},
    this.footprints = const {},
    this.spacing = 16,
    this.viewportClass = ConstellationViewportClass.expanded,
    this.slicer,
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
  /// Domain ids that must not reuse session inertia from a former pin.
  final Set<String> forgetPriorHintNodeIds;
  final ConstellationLayoutPriorHints? priorHints;
  final Map<String, ConstellationSize> nodeSizes;
  final Map<String, ConstellationFootprint> footprints;
  final double spacing;
  final ConstellationViewportClass viewportClass;

  /// When set, the layout runs as a resumable job in frame slices instead of
  /// one synchronous pass. Not part of the algorithm's identity.
  final FrameSliceScheduler? slicer;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) {
    final slicer = this.slicer;
    if (slicer == null || request.nodeIds.isEmpty) {
      return _layoutSync(request);
    }
    final ({
      Map<String, GraphNodeId> graphIdByDomain,
      ConstellationPlacedLayoutInput input,
    })
    prepared;
    final LayoutJob job;
    try {
      prepared = _prepare(request);
      job = ConstellationLayoutEngine(
        newIndex: BruteForceIndex.new,
      ).start(null, prepared.input);
    } catch (error, stackTrace) {
      return Stream.error(error, stackTrace);
    }
    final controller = StreamController<GraphLayoutFrame>();
    // Like the sync path, a throw while laying out ends the stream with an
    // error (a failed layout outcome); it must never escape into the
    // scheduler task and leave the stream open forever.
    void fail(Object error, StackTrace stackTrace) {
      if (controller.isClosed) return;
      controller.addError(error, stackTrace);
      unawaited(controller.close());
    }

    bool step(int units) {
      if (controller.isClosed) return true;
      try {
        return job.step(units);
      } catch (error, stackTrace) {
        fail(error, stackTrace);
        return true;
      }
    }

    void onComplete() {
      if (controller.isClosed) return;
      final GraphLayoutFrame frame;
      try {
        frame = _frame(
          request,
          _constellationPositionsFromDomainMap(
            graphIdByDomain: prepared.graphIdByDomain,
            domainPositions: job.result.positions,
            request: request,
          ),
        );
      } catch (error, stackTrace) {
        fail(error, stackTrace);
        return;
      }
      controller.add(frame);
      unawaited(controller.close());
    }

    controller
      ..onListen = () {
        slicer.start(step: step, onComplete: onComplete);
      }
      ..onCancel = () {
        slicer.cancelJob(onComplete);
      };
    return controller.stream;
  }

  Stream<GraphLayoutFrame> _layoutSync(GraphLayoutRequest request) async* {
    final positions = kReleaseMode
        ? _computePositions(request)
        : ConstellationPerf.timeSync(
            'layout.job',
            () => _computePositions(request),
          );
    yield _frame(request, positions);
  }

  Map<GraphNodeId, ScenePoint> _computePositions(GraphLayoutRequest request) {
    if (request.nodeIds.isEmpty) {
      return const {};
    }
    final prepared = _prepare(request);
    return _constellationPositionsFromDomainMap(
      graphIdByDomain: prepared.graphIdByDomain,
      domainPositions: computeConstellationPlacedLayout(
        input: prepared.input,
      ).positions,
      request: request,
    );
  }

  ({
    Map<String, GraphNodeId> graphIdByDomain,
    ConstellationPlacedLayoutInput input,
  })
  _prepare(GraphLayoutRequest request) {
    final graphIdByDomain = tenturaGraphIdsByDomainId(request.nodeIds);
    final sizes = <String, ConstellationSize>{
      ...nodeSizes,
      for (final entry in graphIdByDomain.entries)
        entry.key: (
          width: request.nodesById[entry.value]!.size.width,
          height: request.nodesById[entry.value]!.size.height,
        ),
    };
    return (
      graphIdByDomain: graphIdByDomain,
      input: (
        egoId: egoId,
        paths: _pathsSeatingOffPathPeers(graphIdByDomain.keys.toSet()),
        automaticKeptPeerIds: keptPeerIds,
        pinnedPersonIds: pinnedPersonIds,
        pinnedRequestIds: pinnedRequestIds,
        supportPersonIds: supportPersonIds,
        anchorByNodeId: anchorByNodeId,
        priorHints: _mergePriorHints(request),
        nodeSizes: sizes,
        satelliteRequestIdsByAuthor: visibleRequestsByAuthor,
        requestAuthorById: const {},
        egoOwnRequestIds: egoOwnRequestIds,
        spacing: spacing,
        maxHops: maxHops,
        viewportClass: viewportClass,
        footprints: footprints,
      ),
    );
  }

  /// The domain layout seats a kept person only on the trust tree
  /// (`paths.keep`) or the residual ring. A drawn kept
  /// person that is neither a path holder nor a holder's ancestor — a
  /// composer candidate, or a Request member kept after its Request was
  /// deselected — would get no seat at all, so it joins the residual ring.
  /// Hard-pinned people are seated by their anchor and are left out.
  ConstellationPathResolution _pathsSeatingOffPathPeers(Set<String> drawnIds) {
    final offPath = <String>{
      for (final id in keptPeerIds)
        if (id != egoId &&
            drawnIds.contains(id) &&
            !paths.keep.contains(id) &&
            !paths.ring.contains(id) &&
            !(pinnedPersonIds.contains(id) && anchorByNodeId.containsKey(id)))
          id,
    };
    if (offPath.isEmpty) {
      return paths;
    }
    return (
      depth: paths.depth,
      derived: paths.derived,
      parent: paths.parent,
      parentTier: paths.parentTier,
      attributed: paths.attributed,
      keep: paths.keep,
      ring: {...paths.ring, ...offPath},
    );
  }

  /// Prefer domain layout, then author seat, then prior layout — never canvas
  /// centre (that coincides with ego and is the unpin failure mode).
  Map<GraphNodeId, ScenePoint> _constellationPositionsFromDomainMap({
    required Map<String, GraphNodeId> graphIdByDomain,
    required Map<String, LPoint> domainPositions,
    required GraphLayoutRequest request,
  }) {
    final previous = request.previous?.positions ?? const {};
    final authorByRequestId = <String, String>{
      for (final requestId in egoOwnRequestIds) requestId: egoId,
      for (final entry in visibleRequestsByAuthor.entries)
        for (final requestId in entry.value) requestId: entry.key,
    };
    final result = <GraphNodeId, ScenePoint>{};
    for (final entry in graphIdByDomain.entries) {
      final domainId = entry.key;
      final graphId = entry.value;
      final fromDomain = _sceneFromPoint(domainPositions[domainId]);
      if (fromDomain != null) {
        result[graphId] = fromDomain;
        continue;
      }
      if (domainId == egoId) {
        result[graphId] = _centerPoint(_canvasSize(request));
        continue;
      }
      final authorId = authorByRequestId[domainId];
      final authorOffset =
          authorId == null ? null : domainPositions[authorId];
      if (authorOffset != null) {
        result[graphId] = ScenePoint(x: authorOffset.x, y: authorOffset.y);
        continue;
      }
      if (!forgetPriorHintNodeIds.contains(domainId)) {
        final prior = previous[graphId];
        if (prior != null) {
          result[graphId] = prior;
          continue;
        }
      }
      final authorPrior = authorId == null
          ? null
          : previous[graphIdByDomain[authorId]];
      if (authorPrior != null) {
        result[graphId] = authorPrior;
        continue;
      }
      // Last resort for release: keep prior pin rather than ego centre when
      // forget set already cleared; otherwise omit (node may briefly vanish).
      final prior = previous[graphId];
      if (prior != null) {
        result[graphId] = prior;
        continue;
      }
      // The composer's draft is placed by its presentation, never by layout,
      // but a frame must still position every requested node (the frame
      // protocol rejects a partial one), so it gets a placeholder.
      if (domainId == FieldDraftNode.draftId &&
          graphId == const FieldDraftNode().graphNodeId) {
        result[graphId] = _centerPoint(_canvasSize(request));
        continue;
      }
      assert(
        false,
        'Constellation layout missing position for $domainId '
        '(graph $graphId); refusing canvas-centre fallback',
      );
    }
    return result;
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
      if (forgetPriorHintNodeIds.contains(entry.key)) {
        continue;
      }
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
          const SetEquality<String>().equals(
            forgetPriorHintNodeIds,
            other.forgetPriorHintNodeIds,
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
          const MapEquality<String, ConstellationFootprint>().equals(
            footprints,
            other.footprints,
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
    const SetEquality<String>().hash(forgetPriorHintNodeIds),
    const MapEquality<String, ConstellationAnchorPosition>().hash(
      anchorByNodeId,
    ),
    priorHints,
    const MapEquality<String, ConstellationSize>().hash(nodeSizes),
    const MapEquality<String, ConstellationFootprint>().hash(footprints),
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

LSize _canvasSize(GraphLayoutRequest request) => (
  w: request.canvasSize.width,
  h: request.canvasSize.height,
);

ScenePoint _centerPoint(LSize canvasSize) {
  final center = lSizeCenter(canvasSize);
  return ScenePoint(x: center.x, y: center.y);
}

ScenePoint? _sceneFromPoint(LPoint? point) =>
    point == null ? null : ScenePoint(x: point.x, y: point.y);

Map<GraphNodeId, ScenePoint> _positionsFromDomainMap({
  required Map<String, GraphNodeId> graphIdByDomain,
  required Map<String, LPoint> domainPositions,
  required LSize canvasSize,
}) {
  final fallback = _centerPoint(canvasSize);
  return {
    for (final entry in graphIdByDomain.entries)
      entry.value:
          _sceneFromPoint(domainPositions[entry.key]) ?? fallback,
  };
}
