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
import '../../domain/constellation_trust_chain.dart';
import '../../domain/constellation_visibility.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../../domain/constellation_forward_tree_overlay.dart';
import '../../domain/constellation_forward_tree_marker.dart';
import '../../domain/entity/constellation_field.dart';
import 'package:tentura/features/forward/domain/entity/forward_graph.dart';
import 'package:tentura/features/forward/domain/entity/forward_recipient_offer_status.dart';
import '../../../graph/domain/entity/edge_details.dart';
import '../../../graph/domain/entity/node_details.dart';
import '../../../graph/ui/utils/graph_scene_ids.dart';
import '../../../graph/ui/utils/tentura_layout_algorithms.dart';
import 'package:tentura/ui/utils/frame_slice_scheduler.dart';
import 'package:tentura/ui/utils/rearrange_preview_scheduler.dart';

import '../utils/constellation_graph_scene.dart';
import '../utils/constellation_presentation_frame.dart';
import '../util/constellation_perf.dart';
import 'constellation_interaction_controller.dart';
import 'scene_update_gate.dart';

enum ConstellationEdgeKind {
  tier1Path,
  tier2Path,
  attachment,
  ringStub,
  webForwarded,
  webInside,
  draftRecipient,

  /// A Request budded from a Post: Post → child (post→Request budding D5).
  grewFrom,

  /// While a person is selected: them → each person on the field they trust
  /// both ways (explicit trust marks only). Drawn over the scene, never laid
  /// out.
  mutualTrust,

  /// Forward-tree overlay: edge on a path to an accepted helper (#774 31ve.6).
  helpBranch,

  /// Forward-tree overlay: other forward edges in the tree (dimmed).
  forwardBranch,

  /// A temporary person → the Request that made them visible (field
  /// membership v2).
  temporaryPresence,
}

const kConstellationLayoutMaxHops = 3;

typedef _LayoutRequest = ({
  Set<GraphPresentationToken> releaseOnTerminal,
  SceneLayoutAlgorithm algorithm,
});

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
  ConstellationSceneController({
    FrameSliceScheduler? slicer,
    this.rearrangePreviewScheduler,
  }) : _slicer = slicer;

  final FrameSliceScheduler? _slicer;

  /// Synchronous slicing for field layout only (pointer pause + starvation).
  FrameSliceScheduler? get layoutSliceScheduler => _slicer;

  /// Bounded stepping for «Rearrange everyone» preview.
  final RearrangePreviewScheduler? rearrangePreviewScheduler;

  /// Cancels the layout job in flight and releases the scheduler.
  void dispose() {
    _slicer?.dispose();
    rearrangePreviewScheduler?.dispose();
  }

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

  /// Opacity per Post web, keyed by [EdgeDetails.semanticId]. A new map per
  /// build, so a painter holding the previous one sees the change.
  Map<String, double> edgeFadeBySemanticId = {};

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

  /// The tag view's layout while one is open; takes over from the Field's.
  SceneLayoutAlgorithm? tagViewAlgorithm;

  /// Forward-tree «Arrange as tree» session layout (#774 31ve.6).
  SceneLayoutAlgorithm? forwardTreeAlgorithm;

  /// Restores saved Field positions after leaving forward-tree radial layout.
  SceneLayoutAlgorithm? forwardTreeLayoutRestore;

  /// One-shot algorithm for an owned layout request (tests); not used after recovery.
  SceneLayoutAlgorithm? ephemeralOwnedLayoutAlgorithm;

  /// 0–1 pulse along an edge while forward-tree replay reveals it (#774).
  final Map<String, double> forwardTreeEdgePulseBySemanticId = {};

  /// Semantic ids of forward-tree edges currently drawn (replay slice order).
  List<String> forwardTreeVisibleSemanticIds = const [];

  /// Overlay-only person decoration: not part of [FieldPersonNode] equality, so
  /// graph topology stays stable when the overlay toggles or rebuilds (#774,
  /// placement_phase_node_rebuild_test).
  Map<String, ConstellationForwardTreeRecipientMarker>
  forwardTreeRecipientMarkerByPersonId = const {};

  Set<String> forwardTreeTemporaryOutlinePersonIds = const {};

  Map<String, int> forwardTreeAnonymousCountByPersonId = const {};

  int _constellationLayoutAlgorithmRevision = -1;
  ConstellationSceneLayoutAlgorithm? _constellationLayoutAlgorithm;

  late final ConstellationInteractionController interaction =
      ConstellationInteractionController(this);

  late final SceneUpdateGate _updateGate = SceneUpdateGate(
    onApply: _applyGatedInput,
  );

  /// The committed scene is frozen (a node is being dragged); layout requests
  /// are held until [releaseFreeze].
  bool get isFrozen => _updateGate.isFrozen;

  /// Freezes the committed scene: displayed geometry stops where it is, the
  /// layout job in flight is invalidated and later requests are held.
  void freeze() {
    if (_updateGate.isFrozen) {
      return;
    }
    _updateGate.freeze();
    graphController
      ..pauseTransitions()
      ..cancelSceneLayout();
  }

  void releaseFreeze() {
    if (!_updateGate.isFrozen) {
      return;
    }
    graphController.resumeTransitions();
    _updateGate.release();
  }

  void _applyGatedInput(SceneInputSource source, Object input) {
    if (source != SceneInputSource.transition) {
      return;
    }
    final request = input as _LayoutRequest;
    graphController.requestSceneLayout(
      releaseOnTerminal: request.releaseOnTerminal,
      algorithm: request.algorithm,
    );
  }

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
      forwardTreeAlgorithm ??
      forwardTreeLayoutRestore ??
      tagViewAlgorithm ??
      ephemeralOwnedLayoutAlgorithm ??
      testSceneLayoutAlgorithmOverride ??
      constellationAlgorithm(
        graphRevision: graphRevision,
        viewerId: viewerId,
        statePaths: statePaths,
        stateKeptPeerIds: stateKeptPeerIds,
        forgetPriorHintNodeIds: forgetPriorHintNodeIds,
      );

  /// Selection redraws advance the graph revision without changing layout.
  void retainLayoutAlgorithmForNextRevision(int graphRevision) {
    if (_constellationLayoutAlgorithmRevision == graphRevision) {
      _constellationLayoutAlgorithmRevision = graphRevision + 1;
    }
  }

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
    ConstellationSceneLayoutAlgorithm build(Set<String> forgetPriorHints) =>
        ConstellationSceneLayoutAlgorithm(
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
          forgetPriorHintNodeIds: forgetPriorHints,
          footprints: layoutFootprints,
          slicer: layoutSliceScheduler,
        );
    // The forgotten prior hints only matter to the layout that consumed them.
    // Once they are cleared, an otherwise identical algorithm is the one the
    // view already runs; a different instance would make it lay out again.
    final consumedHints = cached?.forgetPriorHintNodeIds ?? const <String>{};
    if (cached != null &&
        forgetPriorHintNodeIds.isEmpty &&
        consumedHints.isNotEmpty &&
        build(consumedHints) == cached) {
      return cached;
    }
    return _constellationLayoutAlgorithm = build(forgetPriorHintNodeIds);
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
    _updateGate.submit(SceneInputSource.transition, (
      releaseOnTerminal: releaseOnTerminal,
      algorithm: algorithm,
    ));
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
    // A layout that supersedes a drop's handoff before its terminal frame
    // takes over that drop's holds, or they would never be released.
    final releaseOnTerminal = <GraphPresentationToken>{
      for (final hold
          in graphController.renderSnapshot.presentation.holds.values)
        hold.token,
    };
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
    edgeFadeBySemanticId = {};
    forwardTreeEdgePulseBySemanticId.clear();
    forwardTreeRecipientMarkerByPersonId = const {};
    forwardTreeTemporaryOutlinePersonIds = const {};
    forwardTreeAnonymousCountByPersonId = const {};
    forwardTreeVisibleSemanticIds = const [];
    forwardTreeAlgorithm = null;
    forwardTreeLayoutRestore = null;
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

  /// Every visible trust edge on the field that touches [focusPersonId]
  /// (both directions), between placed people only (#964).
  void _drawFocusPersonTrustEdges({
    required String focusPersonId,
    required Iterable<ConstellationEdgeRef> trustEdges,
    required Map<String, NodeDetails> nodeById,
    required void Function({
      required String srcId,
      required String dstId,
      required ConstellationEdgeKind kind,
      double? fade,
    })
    addEdge,
  }) {
    for (final edge in trustEdges) {
      if (edge.src != focusPersonId && edge.dst != focusPersonId) {
        continue;
      }
      if (!nodeById.containsKey(edge.src) || !nodeById.containsKey(edge.dst)) {
        continue;
      }
      addEdge(
        srcId: edge.src,
        dstId: edge.dst,
        kind: edge.tier == 1
            ? ConstellationEdgeKind.tier1Path
            : ConstellationEdgeKind.tier2Path,
      );
    }
  }

  /// Draws the selected focus person's trust-chain hops and fades every other
  /// edge (#641, #964). Chain hops use tier path kinds; the focus person's
  /// own trust edges are drawn separately.
  void _highlightTrustChain({
    required ConstellationTrustChainFound chain,
    required Set<EdgeDetails> edges,
    required Map<String, NodeDetails> nodeById,
    required void Function({
      required String srcId,
      required String dstId,
      required ConstellationEdgeKind kind,
      double? fade,
    })
    addEdge,
  }) {
    final hopKeys = <String>{};
    for (final (src, dst) in chain.hops) {
      hopKeys.add('$src->$dst');
      if (nodeById.containsKey(src) && nodeById.containsKey(dst)) {
        addEdge(
          srcId: src,
          dstId: dst,
          kind: chain.derivedHops.contains((src, dst))
              ? ConstellationEdgeKind.tier2Path
              : ConstellationEdgeKind.tier1Path,
        );
      }
    }
    final personId = chain.path.last;
    for (final edge in edges) {
      final kind = edgeKindByPair[edge.semanticId];
      final onChain =
          (kind == ConstellationEdgeKind.tier1Path ||
              kind == ConstellationEdgeKind.tier2Path) &&
          hopKeys.contains('${edge.source.id}->${edge.destination.id}');
      final touchesFocus =
          (kind == ConstellationEdgeKind.tier1Path ||
              kind == ConstellationEdgeKind.tier2Path) &&
          (edge.source.id == personId || edge.destination.id == personId);
      final ownItem =
          kind == ConstellationEdgeKind.attachment &&
          edge.source.id == personId;
      if (!onChain && !touchesFocus && !ownItem) {
        edgeFadeBySemanticId[edge.semanticId] =
            (edgeFadeBySemanticId[edge.semanticId] ?? 1) *
            kConstellationTrustChainEdgeFade;
      }
    }
  }

  void _applyForwardTreeOverlay({
    required ConstellationForwardTreeOverlay? forwardTree,
    required Profile viewer,
    required ConstellationPathResolution paths,
    required Set<String> keptPeerIds,
    required Set<NodeDetails> nodes,
    required Map<String, NodeDetails> nodeById,
    required Set<EdgeDetails> edges,
  }) {
    forwardTreeRecipientMarkerByPersonId = const {};
    forwardTreeTemporaryOutlinePersonIds = const {};
    forwardTreeAnonymousCountByPersonId = const {};

    final tree = forwardTree;
    final graph = tree?.graph;
    if (tree == null || graph == null || graph.edges.isEmpty) {
      forwardTreeVisibleSemanticIds = const [];
      forwardTreeEdgePulseBySemanticId.clear();
      return;
    }

    final markers = <String, ConstellationForwardTreeRecipientMarker>{};
    final tempOutlineIds = <String>{};
    final anonByPerson = <String, int>{};

    forwardTreeVisibleSemanticIds = const [];
    if (!tree.replaying) {
      forwardTreeEdgePulseBySemanticId.clear();
    }

    String endpointId(ForwardGraphEdge e, {required bool sender}) {
      final anon = sender ? e.senderAnonymousCount : e.recipientAnonymousCount;
      if (anon > 0) {
        return sender ? 'ftghost:${e.id}:s' : 'ftghost:${e.id}:r';
      }
      return sender ? e.senderId : e.recipientId;
    }

    Profile profileForPerson(
      String personId,
      ForwardGraphEdge e, {
      required bool sender,
    }) {
      final existing = nodeById[personId];
      if (existing is FieldPersonNode) {
        return existing.person;
      }
      final raw = sender ? e.senderDisplayName : e.recipientDisplayName;
      final display = raw?.trim() ?? '';
      return Profile(id: personId, displayName: display);
    }

    ConstellationForwardTreeRecipientMarker? markerFor(ForwardGraphEdge e) {
      if (e.offerStatus == ForwardRecipientOfferStatus.accepted) {
        return ConstellationForwardTreeRecipientMarker.helped;
      }
      if (e.offerStatus == ForwardRecipientOfferStatus.offered) {
        return ConstellationForwardTreeRecipientMarker.offered;
      }
      if (e.declinedInvite == true) {
        return ConstellationForwardTreeRecipientMarker.cantHelp;
      }
      if (e.readAt != null) {
        return ConstellationForwardTreeRecipientMarker.opened;
      }
      if (e.forwardedOn == false) {
        return ConstellationForwardTreeRecipientMarker.notOpened;
      }
      return null;
    }

    ConstellationForwardTreeRecipientMarker? mergeMarker(
      ConstellationForwardTreeRecipientMarker? a,
      ConstellationForwardTreeRecipientMarker? b,
    ) {
      if (a == null) return b;
      if (b == null) return a;
      int rank(ConstellationForwardTreeRecipientMarker m) => switch (m) {
        ConstellationForwardTreeRecipientMarker.helped => 0,
        ConstellationForwardTreeRecipientMarker.offered => 1,
        ConstellationForwardTreeRecipientMarker.cantHelp => 2,
        ConstellationForwardTreeRecipientMarker.opened => 3,
        ConstellationForwardTreeRecipientMarker.notOpened => 4,
      };
      return rank(a) <= rank(b) ? a : b;
    }

    void ensurePersonNode(
      String personId,
      ForwardGraphEdge e, {
      required bool sender,
    }) {
      final anon = sender ? e.senderAnonymousCount : e.recipientAnonymousCount;
      final marker = sender ? null : markerFor(e);
      final isGhost = personId.startsWith('ftghost:');
      final onVisibleField =
          !isGhost && (personId == viewer.id || keptPeerIds.contains(personId));
      final tempOutline = !isGhost && !onVisibleField && anon == 0;
      if (marker != null) {
        final merged = mergeMarker(markers[personId], marker);
        if (merged != null) {
          markers[personId] = merged;
        }
      }
      if (tempOutline) {
        tempOutlineIds.add(personId);
      }
      if (anon > 0) {
        final prev = anonByPerson[personId];
        anonByPerson[personId] = prev == null ? anon : math.max(prev, anon);
      }
      final existing = nodeById[personId];
      if (existing is FieldPersonNode) {
        return;
      }
      final profile = profileForPerson(personId, e, sender: sender);
      final ring = paths.depth[personId] ?? kConstellationLayoutMaxHops;
      nodes.add(
        nodeById[personId] = FieldPersonNode(
          person: profile,
          ring: ring,
          isKept: false,
        ),
      );
    }

    // Edge ids on paths to active help offerers (ancestor walk).
    final byId = {for (final edge in graph.edges) edge.id: edge};
    final helpBranchIds = <String>{};
    final focusOfferer = tree.helpOffererFocusId;
    final offererIds = (focusOfferer != null && focusOfferer.isNotEmpty)
        ? {focusOfferer}
        : graph.helpOffererIds;
    for (final hoId in offererIds) {
      final intoHo =
          [
            for (final edge in graph.edges)
              if (edge.recipientId == hoId) edge,
          ]..sort(
            (a, b) {
              final at = a.createdAt;
              final bt = b.createdAt;
              if (at != null && bt != null && at != bt) {
                return at.compareTo(bt);
              }
              return a.id.compareTo(b.id);
            },
          );
      var current = intoHo.isEmpty ? null : intoHo.last;
      final seen = <String>{};
      while (current != null && seen.add(current.id)) {
        helpBranchIds.add(current.id);
        final parent = current.parentEdgeId;
        current = parent == null ? null : byId[parent];
      }
    }

    var ordered = List<ForwardGraphEdge>.from(graph.edges)
      ..sort(
        (a, b) {
          final at = a.createdAt;
          final bt = b.createdAt;
          if (at != null && bt != null && at != bt) {
            return at.compareTo(bt);
          }
          return a.id.compareTo(b.id);
        },
      );
    final maxVisible = tree.replayVisibleCount;
    if (maxVisible != null) {
      if (maxVisible <= 0) {
        ordered = const [];
      } else if (maxVisible < ordered.length) {
        ordered = ordered.sublist(0, maxVisible);
      }
    }

    final visibleSemanticIds = <String>[];
    for (final e in ordered) {
      final srcId = endpointId(e, sender: true);
      final dstId = endpointId(e, sender: false);
      ensurePersonNode(srcId, e, sender: true);
      ensurePersonNode(dstId, e, sender: false);
      final kind = helpBranchIds.contains(e.id)
          ? ConstellationEdgeKind.helpBranch
          : ConstellationEdgeKind.forwardBranch;
      final srcNode = nodeById[srcId]!;
      final dstNode = nodeById[dstId]!;
      final uniqueKind = 'ft_${e.id}';
      final semanticId =
          '${tenturaGraphNodeId(srcNode)}->${tenturaGraphNodeId(dstNode)}#$uniqueKind';
      if (edgeKindByPair.containsKey(semanticId)) {
        continue;
      }
      final edge = EdgeDetails(
        source: srcNode,
        destination: dstNode,
        color: Colors.transparent,
        strokeWidth: kind == ConstellationEdgeKind.helpBranch ? 3 : 1.5,
        arrowAtDestination: kind == ConstellationEdgeKind.helpBranch,
        semanticId: semanticId,
      );
      edges.add(edge);
      final sceneEdgeId = constellationSceneEdgeId(
        kindName: uniqueKind,
        source: srcNode,
        destination: dstNode,
      );
      edgeKinds[sceneEdgeId] = kind;
      edgeKindByPair[semanticId] = kind;
      visibleSemanticIds.add(semanticId);
    }
    forwardTreeVisibleSemanticIds = visibleSemanticIds;

    final activePersonIds = <String>{};
    for (final e in graph.edges) {
      activePersonIds
        ..add(endpointId(e, sender: true))
        ..add(endpointId(e, sender: false));
    }

    for (final edge in edges) {
      final kind = edgeKindByPair[edge.semanticId];
      if (kind == ConstellationEdgeKind.helpBranch ||
          kind == ConstellationEdgeKind.forwardBranch) {
        continue;
      }
      final srcId = edge.source.id;
      final dstId = edge.destination.id;
      final touches =
          activePersonIds.contains(srcId) || activePersonIds.contains(dstId);
      if (touches) {
        continue;
      }
      edgeFadeBySemanticId[edge.semanticId] =
          (edgeFadeBySemanticId[edge.semanticId] ?? 1) *
          kConstellationTrustChainEdgeFade;
    }

    forwardTreeRecipientMarkerByPersonId = markers;
    forwardTreeTemporaryOutlinePersonIds = tempOutlineIds;
    forwardTreeAnonymousCountByPersonId = anonByPerson;
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

  /// Updates overflow / text-view display metadata when composition changes
  /// without relayout (same anchor projection and peer set).
  void syncLabelDisplayPlan(ConstellationLabelDisplayPlan plan) {
    final drawnSatellites = constellationDrawnSatellites(
      plan,
      hardPinnedRequestIds: layoutPinnedRequestIds,
    );
    layoutVisibleRequestsByAuthor = drawnSatellites.byAuthor;
    layoutEgoOwnRequestIds = drawnSatellites.egoOwn;
    displayedRequestIds = plan.drawnRequestIds;
    overflowHiddenCountByAuthor = plan.overflowHiddenCountByAuthor;
    expandedExtraCountByAuthor = plan.expandedExtraCountByAuthor;
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
    required DateTime asOfUtc,
    required bool isComposing,
    required Set<String> composingSelectedIds,
    required Map<String, List<ConstellationMemberWeb>> requestWebsById,
    required ConstellationFootprintMetrics? footprintMetrics,
    required Profile Function(ConstellationPerson peer) profileFromPeer,
    ConstellationForwardTreeOverlay? forwardTree,
    ConstellationTrustChain? trustChain,
    Set<String> mutualTrustIds = const {},
    Set<String> hiddenPersonIds = const {},
    bool fieldMembershipV2Enabled = false,
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
        requestsById[request.id] = request;
      }
    }
    final drawnRequests = [
      for (final id in drawnRequestIds)
        if (requestsById[id] case final request?
            when !hiddenPersonIds.contains(request.authorId))
          request,
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
    edgeFadeBySemanticId = {};

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
      if (peer == null || hiddenPersonIds.contains(peerId)) {
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
        if (spec.post != null &&
            drawnRequestIds.contains(spec.id) &&
            !hiddenPersonIds.contains(spec.post!.authorId))
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
          ConstellationEdgeKind.helpBranch => 3,
          ConstellationEdgeKind.attachment => 1.5,
          ConstellationEdgeKind.ringStub => 1.5,
          ConstellationEdgeKind.webForwarded ||
          ConstellationEdgeKind.webInside ||
          ConstellationEdgeKind.draftRecipient ||
          ConstellationEdgeKind.grewFrom ||
          ConstellationEdgeKind.mutualTrust => 1.5,
          ConstellationEdgeKind.forwardBranch => 1.5,
          ConstellationEdgeKind.temporaryPresence => 1,
        },
        arrowAtDestination: kind == ConstellationEdgeKind.helpBranch,
        semanticId:
            '${tenturaGraphNodeId(src)}->${tenturaGraphNodeId(dst)}#${kind.name}',
      );
      if (edgeKindByPair.containsKey(edge.semanticId)) {
        return;
      }
      edges.add(edge);
      edgeKinds[constellationSceneEdgeId(
            kindName: kind.name,
            source: src,
            destination: dst,
          )] =
          kind;
      assert(
        !edgeKindByPair.containsKey(edge.semanticId),
        'duplicate edge semantic id ${edge.semanticId}',
      );
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

    final postFade = <String, double>{};
    final postOverflow = <String, int>{};
    for (final node in drawnPosts) {
      final post = node.post!;
      final fade = constellationPostFade(
        expiresAt: post.expiresAt,
        asOfUtc: asOfUtc,
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

    // A budded Request hangs off the Post it grew from; addEdge drops it
    // unless both nodes are on the field.
    for (final request in drawnRequests) {
      final parentId = request.parentBeaconId;
      if (parentId == null || parentId.isEmpty) {
        continue;
      }
      addEdge(
        srcId: parentId,
        dstId: request.id,
        kind: ConstellationEdgeKind.grewFrom,
        fade: postFade[parentId],
      );
    }

    // addEdge drops the link unless both the person and the Request are on
    // the field.
    if (fieldMembershipV2Enabled) {
      for (final peerId in keptSorted) {
        final peer = peersById[peerId];
        final requestId = peer?.temporaryBeaconId;
        if (peer?.fieldMembership != ConstellationFieldMembership.temporary ||
            requestId == null ||
            requestId.isEmpty) {
          continue;
        }
        addEdge(
          srcId: peerId,
          dstId: requestId,
          kind: ConstellationEdgeKind.temporaryPresence,
        );
      }
    }

    if (composing) {
      for (final personId in composingSelectedIds) {
        addEdge(
          srcId: FieldDraftNode.draftId,
          dstId: personId,
          kind: ConstellationEdgeKind.draftRecipient,
        );
      }
    }

    final focusPersonId =
        selectedPersonId ?? nodeById[selectedRequestId]?.userId;
    final visibleTrustEdges = [
      ...constellationVisibleTrustEdges(field),
      if (overlay != null)
        for (final edge in overlay.supportEdges)
          (src: edge.src, dst: edge.dst, tier: edge.tier),
    ];

    if (focusPersonId != null && nodeById.containsKey(focusPersonId)) {
      _drawFocusPersonTrustEdges(
        focusPersonId: focusPersonId,
        trustEdges: visibleTrustEdges,
        nodeById: nodeById,
        addEdge: addEdge,
      );
    }

    if (trustChain is ConstellationTrustChainFound) {
      _highlightTrustChain(
        chain: trustChain,
        edges: edges,
        nodeById: nodeById,
        addEdge: addEdge,
      );
    }

    // After the chain highlight, so the chain's fade never reaches them.
    // Only between people on the field: addEdge drops the rest.
    if (selectedPersonId != null &&
        nodeById[selectedPersonId] is FieldPersonNode) {
      for (final personId in mutualTrustIds.toList()..sort()) {
        if (personId != selectedPersonId &&
            nodeById[personId] is FieldPersonNode) {
          addEdge(
            srcId: selectedPersonId,
            dstId: personId,
            kind: ConstellationEdgeKind.mutualTrust,
          );
        }
      }
    }

    _applyForwardTreeOverlay(
      forwardTree: forwardTree,
      viewer: viewer,
      paths: paths,
      keptPeerIds: keptPeerIds,
      nodes: nodes,
      nodeById: nodeById,
      edges: edges,
    );

    final previous = graphController.renderSnapshot;
    final previousNodeIds = previous.topology.nodesById.keys.toSet();
    graphController.reconcileTopology(
      nodes,
      edges,
      requestLayout: false,
      layoutOnTopologyChange: false,
      // The graph view paints them beneath every other node until they
      // reach their place, so they spring out from under the author.
      initialPositions: beaconSpawnPositions(
        nodes: nodes,
        previous: previous,
        // Before the first layout the view may not know its canvas yet;
        // nothing is seeded then, and the first load lands as before.
        canvasCentre: graphController.canLayout
            ? graphController.canvasSize.center(Offset.zero)
            : null,
      ),
    );
    return (nodes: nodes, previousNodeIds: previousNodeIds);
  }

  /// Where each Request or Post new to the field starts: on its author's
  /// displayed position, so the layout transition carries it out from under
  /// the author. A beacon whose author is not on the field yet (arriving in
  /// the same build) starts at [canvasCentre], where that new author starts
  /// too; with no [canvasCentre] it gets no entry.
  static Map<GraphNodeId, Offset> beaconSpawnPositions({
    required Set<NodeDetails> nodes,
    required GraphSceneSnapshot<NodeDetails, EdgeDetails> previous,
    Offset? canvasCentre,
  }) {
    final present = previous.topology.nodesById;
    final positions = <GraphNodeId, Offset>{};
    for (final node in nodes) {
      if (node is! FieldBeaconNode) {
        continue;
      }
      final graphId = node.graphNodeId;
      if (present.containsKey(graphId)) {
        continue;
      }
      final author = previous.resolvePosition('fp:${node.userId}');
      final start = author == null ? canvasCentre : Offset(author.x, author.y);
      if (start != null) {
        positions[graphId] = start;
      }
    }
    return positions;
  }

  // Camera.

  void fitWholeField(EdgeInsets insets, {GraphNodeId? focus}) => fitNodes(
    insets,
    minScale: kConstellationDistrictDetailScale,
    focus: focus,
  );

  /// Scene pixels [GraphController.fitToRect] reserves around a fitted rect
  /// by default.
  static const _fitPadding = 48.0;

  /// Fits the camera (never zooming past 1) to the placed footprints of the
  /// nodes [include] accepts, or of every node when [include] is null.
  ///
  /// [minScale] keeps the fit from landing below it (the content may then
  /// overflow the viewport). Content that overflows is then framed as close
  /// to [focus] as it allows, when given.
  void fitNodes(
    EdgeInsets insets, {
    bool Function(GraphNodeId)? include,
    double? minScale,
    GraphNodeId? focus,
  }) {
    if (!graphController.canLayout) {
      return;
    }
    var bounds = _placedBounds(include);
    if (bounds == null) {
      return;
    }
    final focusPoint = focus == null
        ? null
        : graphController.renderSnapshot.resolveTargetPosition(focus);
    final viewport = graphController.viewportSize;
    if (minScale != null &&
        focusPoint != null &&
        viewport != null &&
        _fitScale(bounds, insets, viewport) < minScale) {
      // The scene window [minScale] shows, moved toward [focus] only as far
      // as it keeps every footprint in view (or, when they cannot all fit,
      // stays within their span).
      final window = insets.deflateSize(viewport) / minScale;
      double towardFocus(double focus, double low, double high, double size) {
        final a = high - size / 2;
        final b = low + size / 2;
        return focus.clamp(math.min(a, b), math.max(a, b));
      }

      bounds = Rect.fromCenter(
        center: Offset(
          towardFocus(focusPoint.x, bounds.left, bounds.right, window.width),
          towardFocus(focusPoint.y, bounds.top, bounds.bottom, window.height),
        ),
        width: window.width - 2 * _fitPadding,
        height: window.height - 2 * _fitPadding,
      );
    }
    graphController.fitToRect(
      bounds,
      viewportInsets: insets,
      maxScale: 1,
      minScale: minScale,
    );
  }

  static double _fitScale(Rect bounds, EdgeInsets insets, Size viewport) {
    final padded = bounds.inflate(_fitPadding);
    final usable = insets.deflateSize(viewport);
    return math.min(
      usable.width / padded.width,
      usable.height / padded.height,
    );
  }

  /// The placed footprints of the nodes [include] accepts (every node when
  /// null), or null when none is placed.
  Rect? _placedBounds(bool Function(GraphNodeId)? include) {
    final snapshot = graphController.renderSnapshot;
    Rect? bounds;
    for (final entry in snapshot.topology.nodesById.entries) {
      final graphId = entry.key;
      if (include != null && !include(graphId)) {
        continue;
      }
      final point = snapshot.resolveTargetPosition(graphId);
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
    return bounds;
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

  /// The pan (never a zoom) that brings [graphId]'s node inside the viewport
  /// minus [insets] by the least distance, as the camera's scene centre now
  /// (`from`) and after the pan (`to`); null when the node is already inside
  /// or cannot be measured.
  ({Offset from, Offset to})? revealPan(
    GraphNodeId graphId,
    EdgeInsets insets, {
    bool centreVertically = false,
  }) {
    final pixel = graphController.viewportSize;
    if (!graphController.canLayout || pixel == null) {
      return null;
    }
    final snapshot = graphController.renderSnapshot;
    final sceneNode = snapshot.topology.nodesById[graphId];
    final point = snapshot.resolvePosition(graphId);
    if (sceneNode == null || point == null) {
      return null;
    }
    final bounds = constellationPlacedNodeBounds(
      centre: (x: point.x, y: point.y),
      footprint: layoutFootprints[graphId],
      size: (width: sceneNode.size.width, height: sceneNode.size.height),
    );
    final topLeft = graphController.sceneToViewportLocal(
      Offset(bounds.left, bounds.top),
    );
    final bottomRight = graphController.sceneToViewportLocal(
      Offset(bounds.right, bounds.bottom),
    );
    final usable = Rect.fromLTRB(
      insets.left,
      insets.top,
      pixel.width - insets.right,
      pixel.height - insets.bottom,
    );
    if (usable.width <= 0 || usable.height <= 0) {
      return null;
    }
    double shift(double lo, double hi, double min, double max) {
      if (hi - lo > max - min) {
        return (min + max) / 2 - (lo + hi) / 2;
      }
      if (lo < min) return min - lo;
      if (hi > max) return max - hi;
      return 0;
    }

    double shiftY(double lo, double hi, double min, double max) {
      if (centreVertically || hi - lo > max - min) {
        return (min + max) / 2 - (lo + hi) / 2;
      }
      if (lo < min) return min - lo;
      if (hi > max) return max - hi;
      return 0;
    }

    final delta = Offset(
      shift(topLeft.dx, bottomRight.dx, usable.left, usable.right),
      shiftY(topLeft.dy, bottomRight.dy, usable.top, usable.bottom),
    );
    if (delta == Offset.zero) {
      return null;
    }
    // Re-centring the full viewport on the scene point that sits at
    // (centre - delta) now is a pure translation by [delta] at this scale.
    final viewportCentre = pixel.center(Offset.zero);
    return (
      from: graphController.viewportLocalToScene(viewportCentre),
      to: graphController.viewportLocalToScene(viewportCentre - delta),
    );
  }

  Rect _fieldCameraSafeRect(EdgeInsets insets) {
    final pixel = graphController.viewportSize;
    if (pixel == null) {
      return Rect.zero;
    }
    return Rect.fromLTRB(
      insets.left,
      insets.top,
      pixel.width - insets.right,
      pixel.height - insets.bottom,
    );
  }

  Rect? _fieldNodeBodyViewportRect(GraphNodeId graphId) {
    final pixel = graphController.viewportSize;
    if (!graphController.canLayout || pixel == null) {
      return null;
    }
    final snapshot = graphController.renderSnapshot;
    final sceneNode = snapshot.topology.nodesById[graphId];
    final point = snapshot.resolvePosition(graphId);
    if (sceneNode == null || point == null) {
      return null;
    }
    final payload = sceneNode.payload;
    if (payload is! FieldPersonNode && payload is! FieldBeaconNode) {
      return null;
    }
    final bounds = constellationPlacedNodeBounds(
      centre: (x: point.x, y: point.y),
      footprint: layoutFootprints[graphId],
      size: (width: sceneNode.size.width, height: sceneNode.size.height),
    );
    final topLeft = graphController.sceneToViewportLocal(
      Offset(bounds.left, bounds.top),
    );
    final bottomRight = graphController.sceneToViewportLocal(
      Offset(bounds.right, bounds.bottom),
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  /// Whether any Field map body (person, Request, or Post) overlaps the safe
  /// viewport inside [insets].
  bool anyFieldNodeBodyIntersectsSafeRect(EdgeInsets insets) {
    final safe = _fieldCameraSafeRect(insets);
    if (safe.width <= 0 || safe.height <= 0) {
      return true;
    }
    for (final graphId
        in graphController.renderSnapshot.topology.nodesById.keys) {
      final viewportRect = _fieldNodeBodyViewportRect(graphId);
      if (viewportRect != null && safe.overlaps(viewportRect)) {
        return true;
      }
    }
    return false;
  }

  /// The Field node whose body centre is nearest the safe-rect centre.
  GraphNodeId? nearestFieldNodeGraphIdToSafeRectCenter(EdgeInsets insets) {
    final safe = _fieldCameraSafeRect(insets);
    if (safe.width <= 0 || safe.height <= 0) {
      return null;
    }
    final target = safe.center;
    GraphNodeId? nearestId;
    var nearestDistSq = double.infinity;
    for (final graphId
        in graphController.renderSnapshot.topology.nodesById.keys) {
      final viewportRect = _fieldNodeBodyViewportRect(graphId);
      if (viewportRect == null) {
        continue;
      }
      final distSq = (viewportRect.center - target).distanceSquared;
      if (distSq < nearestDistSq) {
        nearestDistSq = distSq;
        nearestId = graphId;
      }
    }
    return nearestId;
  }

  /// Centres the full viewport on [sceneCentre] at the current scale.
  void panCameraTo(Offset sceneCentre) {
    graphController.jumpToPosition(sceneCentre);
  }

  /// Keeps scene nodes visually stable when the map viewport height changes
  /// (Field top chrome hidden for the context sheet).
  void compensateViewportHeightDelta(double viewportDeltaY) {
    final pixel = graphController.viewportSize;
    if (pixel == null || !graphController.canLayout || viewportDeltaY == 0) {
      return;
    }
    final scale = graphController.cameraScale;
    final viewportCentre = pixel.center(Offset.zero);
    final sceneCentre = graphController.viewportLocalToScene(viewportCentre);
    graphController.jumpToPosition(
      sceneCentre - Offset(0, viewportDeltaY / scale),
    );
  }

  void centreOnEgo(String viewerId, EdgeInsets insets) =>
      _centreOnPersonNode(viewerId, insets, resetScale: true);

  /// Centres the camera on [personId]'s node at the current zoom, or at
  /// full scale with [resetScale].
  void centreOnPerson(
    String personId,
    EdgeInsets insets, {
    bool resetScale = false,
  }) => _centreOnPersonNode(personId, insets, resetScale: resetScale);

  void _centreOnPersonNode(
    String personId,
    EdgeInsets insets, {
    required bool resetScale,
  }) {
    if (!graphController.canLayout) {
      return;
    }
    NodeDetails? personNode;
    for (final candidate
        in graphController.renderSnapshot.topology.nodesById.values) {
      final payload = candidate.payload;
      if (payload is FieldPersonNode && payload.person.id == personId) {
        personNode = payload;
        break;
      }
    }
    if (personNode == null) {
      return;
    }
    final point = graphController.renderSnapshot.resolvePosition(
      tenturaGraphNodeId(personNode),
    );
    if (point == null) {
      return;
    }
    graphController.jumpToPosition(
      Offset(point.x, point.y),
      resetScale: resetScale,
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
  /// People in [movedPersonIds] were moved by hand and stay where dropped;
  /// [heldPersonId], under the pointer right now, is left to the drag.
  void placeComposerNodes({
    required Set<NodeDetails> nodes,
    required Set<GraphNodeId> previousNodeIds,
    required String viewerId,
    required Set<String> placedPersonIds,
    required Map<String, Offset> personPositions,
    required Set<GraphNodeId> movedPersonIds,
    required GraphNodeId? heldPersonId,
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
    // A pinned person re-joining the scene (the first composing pass, before
    // the composer's people load, has none) goes back to its pin, not a slot.
    final pins = <GraphNodeId, ConstellationPoint>{
      for (final anchor in confirmedAnchors ?? const <ConstellationAnchor>[])
        if (anchor.target.kind == ConstellationAnchorTargetKind.person)
          constellationGraphNodeIdForTarget(anchor.target):
              constellationV1AnchorToPoint(anchor.position),
    };
    for (final id in added.where(pins.containsKey)) {
      final pin = pins[id]!;
      graphController.beginNodePresentationDragForId(id, Offset(pin.x, pin.y));
      placedPersonIds.add(id);
    }
    added.removeWhere(pins.containsKey);
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
      for (final node in nodes.whereType<FieldPersonNode>()) {
        final id = node.graphNodeId;
        if (id == heldPersonId) continue;
        final point = pins[id];
        final current = graphController.renderSnapshot.resolvePosition(id);
        final moved = movedPersonIds.contains(id) ? personPositions[id] : null;
        final position =
            moved ??
            (point != null
                ? Offset(point.x, point.y)
                : personPositions[id] ??
                      (current == null ? null : Offset(current.x, current.y)));
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
