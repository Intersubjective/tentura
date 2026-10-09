import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../../domain/constellation_anchor_composition.dart';
import '../../domain/constellation_consts.dart';
import '../../domain/constellation_layout.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';
import '../../domain/constellation_post_fade.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../../domain/entity/constellation_field.dart';
import '../../../graph/domain/entity/edge_details.dart';
import '../../../graph/domain/entity/node_details.dart';
import '../../../graph/ui/utils/graph_scene_ids.dart';
import '../../../graph/ui/utils/tentura_layout_algorithms.dart';
import '../utils/constellation_graph_scene.dart';
import '../util/constellation_perf.dart';
import 'constellation_interaction_controller.dart';

enum ConstellationEdgeKind {
  tier1Path,
  tier2Path,
  attachment,
  ringStub,
  webForwarded,
  webInside,
  draftRecipient,
}

const kConstellationLayoutMaxHops = 3;

void runAfterNextFrame(void Function() callback) {
  if (BindingBase.debugBindingType() != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
  } else {
    callback();
  }
}

/// Screen-owned scene: owns the [GraphController], the drawn edge/fade maps,
/// the layout inputs derived from the last build and the layout hand-off.
/// It holds no cubit state; the cubit passes everything it needs per call.
class ConstellationSceneController {
  late final GraphController<NodeDetails, EdgeDetails> graphController =
      GraphController(
        nodeIdOf: tenturaGraphNodeId,
        edgeIdOf: (edge) => constellationEdgeIdForEdge(edge, edgeKinds.keys),
        nodeSizeOf: (node) => node.size,
        nodeSimulationFixedOf: (node) => node.pinned,
        edgeSourceOf: (edge) => edge.source,
        edgeDestinationOf: (edge) => edge.destination,
      );

  final Map<GraphEdgeId, ConstellationEdgeKind> edgeKinds = {};

  /// O(1) kind lookup for edge painting keyed by [EdgeDetails.semanticId] (`src->dst#kind`).
  final Map<String, ConstellationEdgeKind> edgeKindByPair = {};

  /// Opacity per drawn Post id (1 until 48 h, 0.25 at 72 h).
  Map<String, double> postFadeById = const {};

  /// Opacity per Post web, keyed by [EdgeDetails.semanticId].
  final Map<String, double> edgeFadeBySemanticId = {};

  /// «+N» chip count per drawn Post: hidden reach plus capped members.
  Map<String, int> postOverflowCountByPostId = const {};

  String layoutEgoId = '';
  Map<String, List<String>> layoutVisibleRequestsByAuthor = const {};
  Set<String> layoutEgoOwnRequestIds = const {};
  Set<String> layoutPinnedPersonIds = const {};
  Set<String> layoutPinnedRequestIds = const {};
  Set<String> layoutSupportPersonIds = const {};
  Map<String, ConstellationAnchorPosition> layoutAnchorByNodeId = const {};
  Set<String> layoutKeptPeerIds = const {};
  ConstellationPathResolution? layoutPaths;
  Set<String> displayedRequestIds = const {};
  Map<String, int> overflowHiddenCountByAuthor = const {};
  Map<String, int> expandedExtraCountByAuthor = const {};
  Map<String, ConstellationFootprint> layoutFootprints = const {};

  Set<GraphNodeId> _placementHandoffGraphIds = {};

  bool awaitingLayoutOutcome = false;
  bool scheduleLayoutRecoveryAfterRebuild = false;
  int layoutHandoffGeneration = 0;

  SceneLayoutAlgorithm? testSceneLayoutAlgorithmOverride;

  /// One-shot algorithm for an owned layout request (tests); not used after recovery.
  SceneLayoutAlgorithm? ephemeralOwnedLayoutAlgorithm;

  int _constellationLayoutAlgorithmRevision = -1;
  ConstellationSceneLayoutAlgorithm? _constellationLayoutAlgorithm;

  late final ConstellationInteractionController interaction =
      ConstellationInteractionController(this);

  Set<GraphNodeId> get placementHandoffGraphIds => _placementHandoffGraphIds;

  void addPlacementHandoffGraphIds(Set<GraphNodeId> ids) {
    _placementHandoffGraphIds = {..._placementHandoffGraphIds, ...ids};
  }

  void clearPlacementHandoffGraphIds() {
    _placementHandoffGraphIds = {};
  }

  SceneLayoutAlgorithm layoutAlgorithm({
    required int graphRevision,
    required String viewerId,
    required ConstellationPathResolution? statePaths,
    required Set<String> stateKeptPeerIds,
    required Set<String> forgetPriorHintNodeIds,
  }) =>
      ephemeralOwnedLayoutAlgorithm ??
      testSceneLayoutAlgorithmOverride ??
      constellationAlgorithm(
        graphRevision: graphRevision,
        viewerId: viewerId,
        statePaths: statePaths,
        stateKeptPeerIds: stateKeptPeerIds,
        forgetPriorHintNodeIds: forgetPriorHintNodeIds,
      );

  ConstellationSceneLayoutAlgorithm constellationAlgorithm({
    required int graphRevision,
    required String viewerId,
    required ConstellationPathResolution? statePaths,
    required Set<String> stateKeptPeerIds,
    required Set<String> forgetPriorHintNodeIds,
  }) {
    final cached = _constellationLayoutAlgorithm;
    if (cached != null &&
        _constellationLayoutAlgorithmRevision == graphRevision) {
      return cached;
    }
    _constellationLayoutAlgorithmRevision = graphRevision;
    return _constellationLayoutAlgorithm = ConstellationSceneLayoutAlgorithm(
      egoId: layoutEgoId.isEmpty ? viewerId : layoutEgoId,
      paths:
          layoutPaths ??
          statePaths ??
          resolveConstellationPaths(
            egoId: viewerId,
            visiblePeerIds: const {},
            holderIds: {viewerId},
            edges: const [],
          ),
      keptPeerIds: layoutKeptPeerIds.isEmpty
          ? stateKeptPeerIds
          : layoutKeptPeerIds,
      maxHops: kConstellationLayoutMaxHops,
      visibleRequestsByAuthor: layoutVisibleRequestsByAuthor,
      egoOwnRequestIds: layoutEgoOwnRequestIds,
      pinnedPersonIds: layoutPinnedPersonIds,
      pinnedRequestIds: layoutPinnedRequestIds,
      supportPersonIds: layoutSupportPersonIds,
      anchorByNodeId: layoutAnchorByNodeId,
      forgetPriorHintNodeIds: forgetPriorHintNodeIds,
      footprints: layoutFootprints,
    );
  }

  Set<GraphPresentationToken> activePresentationReleaseTokens() {
    final releaseOnTerminal = <GraphPresentationToken>{};
    for (final id in graphController.renderSnapshot.topology.nodesById.keys) {
      final token = graphController.activePresentationTokenForNode(id);
      if (token != null) {
        releaseOnTerminal.add(token);
      }
    }
    return releaseOnTerminal;
  }

  void requestLayout({
    required Set<GraphPresentationToken> releaseOnTerminal,
    required SceneLayoutAlgorithm algorithm,
  }) {
    graphController.requestSceneLayout(
      releaseOnTerminal: releaseOnTerminal,
      algorithm: algorithm,
    );
  }

  void scheduleLayoutHandoff({
    required bool Function() isClosed,
    required SceneLayoutAlgorithm Function() algorithm,
    bool immediate = false,
  }) {
    final handoffGeneration = ++layoutHandoffGeneration;
    void handoff() {
      if (isClosed() || handoffGeneration != layoutHandoffGeneration) {
        return;
      }
      _requestLayoutHandoff(algorithm);
    }

    // A scene that is already laid out has nothing to wait a frame for.
    if (immediate && graphController.canLayout) {
      handoff();
    } else {
      runAfterNextFrame(handoff);
    }
  }

  void _requestLayoutHandoff(SceneLayoutAlgorithm Function() algorithm) {
    final handoffGraphIds = _placementHandoffGraphIds;
    _placementHandoffGraphIds = {};
    final recovery = scheduleLayoutRecoveryAfterRebuild;
    scheduleLayoutRecoveryAfterRebuild = false;
    final releaseOnTerminal = <GraphPresentationToken>{};
    if (recovery) {
      releaseOnTerminal.addAll(activePresentationReleaseTokens());
    } else if (handoffGraphIds.isNotEmpty) {
      for (final graphId in handoffGraphIds) {
        final token = graphController.activePresentationTokenForNode(graphId);
        if (token != null) {
          releaseOnTerminal.add(token);
        }
      }
      interaction.clearPlacementClusterState();
    }
    awaitingLayoutOutcome = true;
    requestLayout(
      releaseOnTerminal: releaseOnTerminal,
      algorithm: algorithm(),
    );
  }

  void clear() {
    graphController.clear();
    edgeKinds.clear();
    edgeKindByPair.clear();
    edgeFadeBySemanticId.clear();
    postFadeById = const {};
    postOverflowCountByPostId = const {};
    overflowHiddenCountByAuthor = const {};
    expandedExtraCountByAuthor = const {};
  }

  Map<String, ConstellationFootprint> layoutFootprintsForNodes({
    required ConstellationFootprintMetrics? metrics,
    required ConstellationLabelDisplayPlan plan,
    required Set<String> personIds,
    required Set<String> requestIds,
  }) {
    if (metrics == null) {
      return const {};
    }
    final footprints = <String, ConstellationFootprint>{};
    for (final id in personIds) {
      footprints[id] = constellationNodeFootprint(
        kind: ConstellationFootprintKind.person,
        bodySize: 40,
        hasAuthorChip:
            plan.overflowHiddenCountByAuthor.containsKey(id) ||
            plan.expandedExtraCountByAuthor.containsKey(id),
        metrics: metrics,
      );
    }
    for (final id in requestIds) {
      footprints[id] = constellationNodeFootprint(
        kind: ConstellationFootprintKind.request,
        bodySize: 36,
        hasAuthorChip: false,
        metrics: metrics,
      );
    }
    return footprints;
  }

  /// The peer an ego edge may lead to: the first hop on the path to
  /// [focusPersonId], or the person itself when it hangs on the ring.
  Set<String> _egoEdgeTargets({
    required String viewerId,
    required ConstellationPathResolution paths,
    required String? focusPersonId,
  }) {
    if (focusPersonId == null || focusPersonId == viewerId) {
      return const {};
    }
    var current = focusPersonId;
    final seen = <String>{};
    while (seen.add(current)) {
      final parentId = paths.parent[current];
      if (parentId == null || parentId == viewerId) {
        break;
      }
      current = parentId;
    }
    return {current};
  }

  void rebuild(void Function() build) {
    if (kReleaseMode) {
      build();
      return;
    }
    ConstellationPerf.timeSync('scene.build', build);
  }

  /// Reconciles the graph topology with [field]; returns the new node set and
  /// the node ids present before, so the caller can place composer nodes.
  ({Set<NodeDetails> nodes, Set<GraphNodeId> previousNodeIds}) buildGraphScene({
    required Profile viewer,
    required ConstellationField field,
    required ConstellationPathResolution paths,
    required ConstellationComposedPresentation? composition,
    required ConstellationLabelDisplayPlan plan,
    required Set<String> keptPeerIds,
    required String? selectedPersonId,
    required String? selectedRequestId,
    required DateTime? loadedAt,
    required bool isComposing,
    required Set<String> composingSelectedIds,
    required Map<String, List<ConstellationMemberWeb>> requestWebsById,
    required ConstellationFootprintMetrics? footprintMetrics,
    required Profile Function(ConstellationPerson peer) profileFromPeer,
  }) {
    final peersById = {
      for (final peer in field.peers) peer.id: peer,
    };
    final overlay = composition?.anchorOverlay;
    if (overlay != null) {
      for (final peer in overlay.pinnedPeers) {
        peersById.putIfAbsent(peer.id, () => peer);
      }
      for (final peer in overlay.supportPeers) {
        peersById.putIfAbsent(peer.id, () => peer);
      }
    }
    final drawnRequestIds = plan.drawnRequestIds;

    final requestsById = {
      for (final request in field.requests) request.id: request,
    };
    if (overlay != null) {
      for (final request in overlay.pinnedRequests) {
        requestsById.putIfAbsent(request.id, () => request);
      }
    }
    final drawnRequests = [
      for (final id in drawnRequestIds) ?requestsById[id],
    ]..sort((a, b) => a.id.compareTo(b.id));

    layoutEgoId = viewer.id;
    layoutPaths = paths;
    layoutKeptPeerIds = keptPeerIds;
    final anchors = overlay?.anchors ?? const <ConstellationAnchor>[];
    // Hard pins only: ids with an anchor coordinate. Peers listed as pinned
    // without a person anchor must not block automatic placement.
    layoutPinnedPersonIds = {
      for (final anchor in anchors)
        if (anchor.target.kind == ConstellationAnchorTargetKind.person)
          anchor.target.id,
    };
    layoutPinnedRequestIds = {
      for (final anchor in anchors)
        if (anchor.target.kind == ConstellationAnchorTargetKind.beacon)
          anchor.target.id,
    };
    layoutSupportPersonIds = {
      if (overlay != null)
        for (final peer in overlay.supportPeers) peer.id,
    };
    layoutAnchorByNodeId = {
      for (final entry in constellationAnchorsByNodeId(anchors).entries)
        entry.key: entry.value.position,
    };
    final drawnSatellites = constellationDrawnSatellites(
      plan,
      hardPinnedRequestIds: layoutPinnedRequestIds,
    );
    layoutVisibleRequestsByAuthor = drawnSatellites.byAuthor;
    layoutEgoOwnRequestIds = drawnSatellites.egoOwn;
    displayedRequestIds = plan.drawnRequestIds;
    overflowHiddenCountByAuthor = plan.overflowHiddenCountByAuthor;
    expandedExtraCountByAuthor = plan.expandedExtraCountByAuthor;

    final personIdsForFootprints = {
      viewer.id,
      ...layoutKeptPeerIds,
      ...layoutPinnedPersonIds,
      ...layoutSupportPersonIds,
    };
    final requestIdsForFootprints = {
      ...drawnSatellites.byAuthor.values.expand((ids) => ids),
      ...drawnSatellites.egoOwn,
      ...layoutPinnedRequestIds,
    };
    layoutFootprints = layoutFootprintsForNodes(
      metrics: footprintMetrics,
      plan: plan,
      personIds: personIdsForFootprints,
      requestIds: requestIdsForFootprints,
    );

    final nodes = <NodeDetails>{};
    final edges = <EdgeDetails>{};
    edgeKinds.clear();
    edgeKindByPair.clear();
    edgeFadeBySemanticId.clear();

    nodes.add(
      FieldPersonNode(
        person: viewer,
        ring: 0,
        isKept: true,
      ),
    );

    final keptSorted = keptPeerIds.toList()..sort();
    for (final peerId in keptSorted) {
      final peer = peersById[peerId];
      if (peer == null) {
        continue;
      }
      final ring = paths.ring.contains(peerId)
          ? kConstellationLayoutMaxHops + 1
          : paths.depth[peerId] ?? kConstellationLayoutMaxHops;
      nodes.add(
        FieldPersonNode(
          person: profileFromPeer(peer),
          ring: ring,
          isKept: paths.keep.contains(peerId),
        ),
      );
    }

    for (final request in drawnRequests) {
      nodes.add(FieldBeaconNode(request: request));
    }
    final drawnPosts = [
      for (final spec in composition?.beaconNodes ?? const <LayoutNodeSpec>[])
        if (spec.post != null && drawnRequestIds.contains(spec.id))
          FieldBeaconNode(post: spec.post, pinned: spec.pinned),
    ];
    nodes.addAll(drawnPosts);

    final composing = isComposing;
    if (composing) {
      nodes.add(const FieldDraftNode());
    }

    final nodeById = {for (final node in nodes) node.id: node};

    void addEdge({
      required String srcId,
      required String dstId,
      required ConstellationEdgeKind kind,
      double? fade,
    }) {
      final src = nodeById[srcId];
      final dst = nodeById[dstId];
      if (src == null || dst == null) {
        return;
      }
      final edge = EdgeDetails(
        source: src,
        destination: dst,
        color: Colors.transparent,
        strokeWidth: switch (kind) {
          ConstellationEdgeKind.tier1Path => 2,
          ConstellationEdgeKind.tier2Path => 2,
          ConstellationEdgeKind.attachment => 1.5,
          ConstellationEdgeKind.ringStub => 1.5,
          ConstellationEdgeKind.webForwarded ||
          ConstellationEdgeKind.webInside ||
          ConstellationEdgeKind.draftRecipient => 1.5,
        },
        semanticId:
            '${tenturaGraphNodeId(src)}->${tenturaGraphNodeId(dst)}#${kind.name}',
      );
      edges.add(edge);
      edgeKinds[constellationSceneEdgeId(
            kindName: kind.name,
            source: src,
            destination: dst,
          )] =
          kind;
      assert(!edgeKindByPair.containsKey(edge.semanticId));
      edgeKindByPair[edge.semanticId] = kind;
      if (fade != null) {
        edgeFadeBySemanticId[edge.semanticId] = fade;
      }
    }

    // Edges from ego fan out to every first-hop peer and crowd the field, so
    // only the one leading to the selected person (or the selected Beacon's
    // author) is drawn.
    final egoEdgeTargets = _egoEdgeTargets(
      viewerId: viewer.id,
      paths: paths,
      focusPersonId: selectedPersonId ?? nodeById[selectedRequestId]?.userId,
    );

    for (final child in paths.keep.intersection(keptPeerIds)) {
      final parentId = paths.parent[child];
      if (parentId == null ||
          (parentId == viewer.id && !egoEdgeTargets.contains(child))) {
        continue;
      }
      final tier = paths.parentTier[child] ?? 1;
      addEdge(
        srcId: parentId,
        dstId: child,
        kind: tier == 1
            ? ConstellationEdgeKind.tier1Path
            : ConstellationEdgeKind.tier2Path,
      );
    }

    for (final ringPeer in paths.ring.intersection(
      keptPeerIds.intersection(egoEdgeTargets),
    )) {
      addEdge(
        srcId: viewer.id,
        dstId: ringPeer,
        kind: ConstellationEdgeKind.ringStub,
      );
    }

    for (final request in drawnRequests) {
      addEdge(
        srcId: request.authorId,
        dstId: request.id,
        kind: ConstellationEdgeKind.attachment,
      );
    }

    final asOf = (loadedAt ?? field.loadedAt).toUtc();
    final postFade = <String, double>{};
    final postOverflow = <String, int>{};
    for (final node in drawnPosts) {
      final post = node.post!;
      final fade = constellationPostFade(
        lastActivityAt: post.lastActivityAt.toUtc(),
        asOfUtc: asOf,
      );
      postFade[post.id] = fade;
      addEdge(
        srcId: post.authorId,
        dstId: post.id,
        kind: ConstellationEdgeKind.attachment,
      );
      var visibleMembers = 0;
      var placedMembers = 0;
      final selected = selectedRequestId == post.id;
      for (final web in field.memberWebs) {
        if (web.beaconId != post.id) {
          continue;
        }
        if (web.personId != viewer.id && !peersById.containsKey(web.personId)) {
          continue;
        }
        visibleMembers++;
        if (!nodeById.containsKey(web.personId)) {
          continue;
        }
        placedMembers++;
        if (!selected) {
          continue;
        }
        addEdge(
          srcId: post.id,
          dstId: web.personId,
          kind: web.state == ConstellationMemberWebState.inside
              ? ConstellationEdgeKind.webInside
              : ConstellationEdgeKind.webForwarded,
          fade: fade,
        );
      }
      final count = constellationPostOverflowCount(
        hiddenReachCount: post.hiddenReachCount,
        visibleMemberCount: visibleMembers,
        placedMemberCount: placedMembers,
      );
      if (count > 0) {
        postOverflow[post.id] = count;
      }
    }
    if (selectedRequestId != null &&
        drawnRequestIds.contains(selectedRequestId)) {
      final webs =
          requestWebsById[selectedRequestId] ??
          const <ConstellationMemberWeb>[];
      for (final web in webs) {
        if (web.personId != viewer.id && !peersById.containsKey(web.personId)) {
          continue;
        }
        addEdge(
          srcId: selectedRequestId,
          dstId: web.personId,
          kind: web.state == ConstellationMemberWebState.inside
              ? ConstellationEdgeKind.webInside
              : ConstellationEdgeKind.webForwarded,
        );
      }
    }
    postFadeById = postFade;
    postOverflowCountByPostId = postOverflow;

    if (composing) {
      for (final personId in composingSelectedIds) {
        addEdge(
          srcId: FieldDraftNode.draftId,
          dstId: personId,
          kind: ConstellationEdgeKind.draftRecipient,
        );
      }
    }

    final previousNodeIds = graphController
        .renderSnapshot
        .topology
        .nodesById
        .keys
        .toSet();
    graphController.reconcileTopology(
      nodes,
      edges,
      requestLayout: false,
      layoutOnTopologyChange: false,
    );
    return (nodes: nodes, previousNodeIds: previousNodeIds);
  }

  // Camera.

  void fitWholeField(EdgeInsets insets) {
    if (!graphController.canLayout) {
      return;
    }
    final snapshot = graphController.renderSnapshot;
    Rect? bounds;
    for (final entry in snapshot.topology.nodesById.entries) {
      final graphId = entry.key;
      final point = snapshot.resolvePosition(graphId);
      if (point == null) {
        continue;
      }
      final centre = (x: point.x, y: point.y);
      final sceneNode = entry.value;
      final nodeBounds = constellationPlacedNodeBounds(
        centre: centre,
        footprint: layoutFootprints[graphId],
        size: (
          width: sceneNode.size.width,
          height: sceneNode.size.height,
        ),
      );
      final rect = Rect.fromLTRB(
        nodeBounds.left,
        nodeBounds.top,
        nodeBounds.right,
        nodeBounds.bottom,
      );
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    if (bounds == null) {
      return;
    }
    graphController.fitToRect(
      bounds,
      viewportInsets: insets,
      maxScale: 1,
    );
  }

  void centreOnBeacon(String beaconId, EdgeInsets insets) {
    if (!graphController.canLayout) {
      return;
    }
    for (final candidate
        in graphController.renderSnapshot.topology.nodesById.values) {
      final payload = candidate.payload;
      if (payload is! FieldBeaconNode ||
          (payload.request?.id ?? payload.post?.id) != beaconId) {
        continue;
      }
      final point = graphController.renderSnapshot.resolvePosition(
        tenturaGraphNodeId(payload),
      );
      if (point != null) {
        graphController.jumpToPosition(
          Offset(point.x, point.y),
          viewportInsets: insets,
        );
      }
      return;
    }
  }

  void centreOnEgo(String viewerId, EdgeInsets insets) {
    if (!graphController.canLayout) {
      return;
    }
    NodeDetails? egoNode;
    for (final candidate
        in graphController.renderSnapshot.topology.nodesById.values) {
      final payload = candidate.payload;
      if (payload is FieldPersonNode && payload.person.id == viewerId) {
        egoNode = payload;
        break;
      }
    }
    if (egoNode == null) {
      return;
    }
    final point = graphController.renderSnapshot.resolvePosition(
      tenturaGraphNodeId(egoNode),
    );
    if (point == null) {
      return;
    }
    graphController.jumpToPosition(
      Offset(point.x, point.y),
      resetScale: true,
      viewportInsets: insets,
    );
  }

  void updateSingleNodePresentation(GraphNodeId graphId, Offset sceneCentre) {
    if (graphController.nodePayloadForId(graphId) == null) {
      return;
    }
    final token = graphController.activePresentationTokenForNode(graphId);
    if (token != null) {
      graphController.updateNodePresentationDrag(token, sceneCentre);
    } else {
      graphController.beginNodePresentationDragForId(graphId, sceneCentre);
    }
  }

  /// Places the draft node, which is not in the anchor set, at a fixed centre.
  void placeDraftNode(Offset centre) {
    const draftGraphId = 'fd:${FieldDraftNode.draftId}';
    if (graphController.nodePayloadForId(draftGraphId) == null) {
      return;
    }
    final token = graphController.activePresentationTokenForNode(draftGraphId);
    if (token != null) {
      graphController.updateNodePresentationDrag(token, centre);
      return;
    }
    graphController.beginNodePresentationDragForId(draftGraphId, centre);
  }

  /// Gives composer-added people a ring slot around the ego and, unless a
  /// placement write is pending ([confirmedAnchors] is null), pins every
  /// person at its anchor or last known position; then places the draft.
  void placeComposerNodes({
    required Set<NodeDetails> nodes,
    required Set<GraphNodeId> previousNodeIds,
    required String viewerId,
    required Set<String> placedPersonIds,
    required Map<String, Offset> personPositions,
    required List<ConstellationAnchor>? confirmedAnchors,
    required Offset draftCentre,
  }) {
    final added =
        nodes
            .whereType<FieldPersonNode>()
            .map((node) => node.graphNodeId)
            .where((id) => !previousNodeIds.contains(id))
            .toList()
          ..sort();
    final egoPoint = graphController.renderSnapshot.resolvePosition(
      'fp:$viewerId',
    );
    final center = egoPoint == null
        ? const Offset(kConstellationCanvasCentre, kConstellationCanvasCentre)
        : Offset(egoPoint.x, egoPoint.y);
    final firstSlot = placedPersonIds.length;
    for (var i = 0; i < added.length; i++) {
      var slot = firstSlot + i;
      var ring = 1;
      while (slot >= 12 * ring) {
        slot -= 12 * ring;
        ring++;
      }
      final angle = 2 * math.pi * slot / (12 * ring);
      graphController.beginNodePresentationDragForId(
        added[i],
        center +
            Offset(
              math.cos(angle) * ring * kConstellationRingUnitPixels,
              math.sin(angle) * ring * kConstellationRingUnitPixels,
            ),
      );
      placedPersonIds.add(added[i]);
    }
    if (confirmedAnchors != null) {
      final anchors = constellationAnchorsByNodeId(confirmedAnchors);
      for (final node in nodes.whereType<FieldPersonNode>()) {
        final id = node.graphNodeId;
        final anchor = anchors[id];
        final point = anchor == null
            ? null
            : constellationV1AnchorToPoint(anchor.position);
        final current = graphController.renderSnapshot.resolvePosition(id);
        final position = point != null
            ? Offset(point.x, point.y)
            : personPositions[id] ??
                  (current == null ? null : Offset(current.x, current.y));
        if (position != null) {
          personPositions[id] = position;
          placedPersonIds.add(id);
          updateSingleNodePresentation(id, position);
        }
      }
    }
    placeDraftNode(draftCentre);
  }

  // Paint order.

  List<NodeDetails> orderedNodesForPaint({
    required List<ConstellationAnchor> anchors,
    required ConstellationAnchorTarget? activeTarget,
    required bool dragging,
  }) {
    final nodes = graphController.nodes.whereType<NodeDetails>().toList();
    if (nodes.isEmpty) {
      return nodes;
    }
    final anchorByNodeId = constellationAnchorsByNodeId(anchors);
    final anchored = <NodeDetails>[];
    final unanchored = <NodeDetails>[];
    for (final node in nodes) {
      if (anchorByNodeId.containsKey(node.id)) {
        anchored.add(node);
      } else {
        unanchored.add(node);
      }
    }
    anchored.sort((a, b) {
      final anchorA = anchorByNodeId[a.id]!;
      final anchorB = anchorByNodeId[b.id]!;
      return ConstellationAnchor.comparePaintOrder(anchorA, anchorB);
    });
    final ordered = [...unanchored, ...anchored];
    if (interaction.placementClusterGraphIds.isNotEmpty && dragging) {
      final parentGraphId = activeTarget == null
          ? null
          : constellationGraphNodeIdForTarget(activeTarget);
      final clusterNodes = <NodeDetails>[];
      for (final graphId in interaction.placementClusterGraphIds) {
        final domainId = tenturaLayoutDomainId(graphId);
        final node = ordered.where((n) => n.id == domainId).firstOrNull;
        if (node != null) {
          ordered.remove(node);
          clusterNodes.add(node);
        }
      }
      clusterNodes.sort((a, b) {
        if (parentGraphId == null) {
          return 0;
        }
        final aIsParent = tenturaGraphNodeId(a) == parentGraphId;
        final bIsParent = tenturaGraphNodeId(b) == parentGraphId;
        if (aIsParent == bIsParent) {
          return 0;
        }
        return aIsParent ? 1 : -1;
      });
      ordered.addAll(clusterNodes);
    }
    return ordered;
  }
}
