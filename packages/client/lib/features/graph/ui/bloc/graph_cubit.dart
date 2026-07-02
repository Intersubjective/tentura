// graphController should be here
// ignore_for_file: avoid_public_fields, prefer_void_public_cubit_methods

import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/message/common_messages.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/invite_genealogy/data/repository/invite_genealogy_repository.dart';
import 'package:tentura/features/invite_genealogy/domain/entity/invite_genealogy_graph.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../data/repository/forwards_graph_repository.dart';
import '../../data/repository/graph_repository.dart';
import '../../data/repository/graph_source_repository.dart';
import '../../domain/entity/edge_details.dart';
import '../../domain/entity/graph_edge_colors.dart';
import '../../domain/entity/edge_directed.dart';
import '../../domain/forward_graph_focus_rules.dart';
import '../../domain/prune_directed_paths.dart';
import '../../domain/entity/node_details.dart';
import 'graph_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export '../../domain/forward_graph_focus_rules.dart';
export 'graph_state.dart';

class GraphCubit extends Cubit<GraphState> {
  // TODO(contract): Phase-2 DTO migration — route multi-repo orchestration through a *Case.
  // ignore: tentura_lints/cubit_requires_use_case_for_multi_repos
  GraphCubit({
    required Profile me,
    required GraphEdgeColors edgeColors,
    String? focus,
    GraphSourceRepository? graphSourceRepository,

    /// When set, [GraphCubit] always loads forwards for this beacon id and
    /// does not refetch on node focus changes (forwards graph is static).
    this.forwardsGraphBeaconId,

    /// When set together with [forwardsGraphBeaconId], the cubit fetches the
    /// per-help-offerer forward path (V2 `beaconHelpOffererForwardPath`) instead
    /// of the broader `beaconForwardGraph`. Focus auto-rotates onto the
    /// help offerer (or the author when the viewer IS the help offerer — case 3).
    this.helpOffererFocusUserId,
    this.genealogyMode = false,
    this.genealogyTargetId,
    this.genealogyAnonymousNodeLabel,
    BeaconRepository? beaconRepository,
    ProfileRepositoryPort? profileRepository,
    UiEffectPort? effects,
  }) : assert(
         !genealogyMode || forwardsGraphBeaconId == null,
         'genealogyMode is mutually exclusive with forwardsGraphBeaconId',
       ),
       assert(
         !genealogyMode || helpOffererFocusUserId == null,
         'genealogyMode is mutually exclusive with helpOffererFocusUserId',
       ),
       _edgeColors = edgeColors,
       _egoNode = UserNode(
         user: me.copyWith(displayName: 'Me', score: 2),
         pinned: true,
         size: 80,
         positionHint: 0,
       ),
       _graphSource = graphSourceRepository ?? GetIt.I<GraphRepository>(),
       _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _profileRepository =
           profileRepository ?? GetIt.I<ProfileRepositoryPort>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(
         GraphState(
           focus: focus ?? '',
           me: me,
         ),
       ) {
    unawaited(_fetch());
  }

  final GraphSourceRepository _graphSource;

  final String? forwardsGraphBeaconId;

  final String? helpOffererFocusUserId;

  final bool genealogyMode;

  final String? genealogyTargetId;

  final String? genealogyAnonymousNodeLabel;

  final BeaconRepository _beaconRepository;

  final ProfileRepositoryPort _profileRepository;

  final UiEffectPort _effects;

  final GraphEdgeColors _edgeColors;

  /// Resolved viewer role for the help-offerer-path view; null when the cubit
  /// is operating in any other mode (regular forwards graph or MeritRank).
  /// Set during [_fetch] once `authorId`/`viewerId` are known.
  ForwardsGraphViewerRole? get helpOffererViewerRole =>
      state.helpOffererViewerRole;

  final graphController =
      GraphController<NodeDetails, EdgeDetails<NodeDetails>>();

  final UserNode _egoNode;

  final _fetchLimits = <String, int>{};

  final _genealogyChildrenCursors = <String, (DateTime, String)>{};

  final _totalNeighborCounts = <String, int>{};

  final _addedEdgeEndpoints = <(String, String)>{};

  /// Every edge ever fetched this session, keyed by `(src, dst)` — the
  /// source of truth for focus-path visibility. Unlike `graphController`
  /// (which only holds what is currently rendered), nothing is ever removed
  /// here except on full resets ([setContext] / [togglePositiveOnly]).
  final _allEdges = <(String, String), EdgeDirected>{};

  late final Map<String, NodeDetails> _nodes = genealogyMode
      ? <String, NodeDetails>{}
      : <String, NodeDetails>{_egoNode.id: _egoNode};

  /// Active help offerers for [forwardsGraphBeaconId] (forwards graph only).
  /// Highlighted via [UserNode.isHelpOfferer] in the renderer.
  Set<String> _helpOffererIds = const <String>{};

  /// Focus-path spotlight applies only to the default MeritRank connections
  /// graph; forwards and genealogy graphs keep their additive rendering.
  bool get _usesFocusPathVisibility =>
      forwardsGraphBeaconId == null && !genealogyMode;

  @override
  Future<void> close() {
    graphController.dispose();
    return super.close();
  }

  ///
  ///
  void jumpToEgo() {
    final node = genealogyMode ? _nodes[state.egoNodeId] : _egoNode;
    if (node == null) return;
    if (!graphController.canLayout ||
        !graphController.layout.hasPosition(node)) {
      return;
    }
    unawaited(Future.value(graphController.jumpToNode(node)));
  }

  ///
  ///
  void setFocus(NodeDetails node) {
    var alreadyFetched = false;
    if (state.focus != node.id) {
      final previousFocusId = state.focus;
      emit(state.copyWith(focus: node.id));
      graphController.setPinned(node, true);
      _unpinPreviousFocus(previousFocusId);
      if (_usesFocusPathVisibility) {
        _recomputeVisibility();
        // Backtracking onto a node whose neighbors are already loaded is a
        // pure visibility change — re-reveal instantly, no refetch. A repeat
        // tap on the *current* focus still falls through to _fetch to page
        // in more neighbors.
        alreadyFetched = _fetchLimits.containsKey(node.id);
      }
      if (graphController.canLayout &&
          graphController.layout.hasPosition(node)) {
        unawaited(Future.value(graphController.jumpToNode(node)));
      }
    }
    if (forwardsGraphBeaconId == null && !alreadyFetched) {
      unawaited(_fetch());
    }
  }

  /// Every focus change pins the new node ([setFocus]) — without a matching
  /// unpin, every node ever tapped stays frozen in the force layout forever.
  /// Converges to "ego + current focus pinned, everything else free".
  void _unpinPreviousFocus(String previousFocusId) {
    if (previousFocusId.isEmpty ||
        previousFocusId == _egoNode.id ||
        previousFocusId == state.egoNodeId ||
        previousFocusId == state.genealogyTargetNodeKey) {
      return;
    }
    // Look up the live controller instance by id: NodeBase equality ignores
    // `pinned`, and setPinned throws if the instance isn't in the controller.
    for (final n in graphController.nodes) {
      if (n.id == previousFocusId) {
        if (n.pinned) {
          graphController.setPinned(n, false);
        }
        break;
      }
    }
  }

  ///
  ///
  Future<void> setContext(String? context) {
    if (forwardsGraphBeaconId != null || genealogyMode) {
      return Future.value();
    }
    _totalNeighborCounts.clear();
    emit(
      state.copyWith(
        context: context ?? '',
        focus: '',
        hiddenNeighborCounts: const {},
      ),
    );
    graphController.clear();
    _fetchLimits.clear();
    _addedEdgeEndpoints.clear();
    _allEdges.clear();
    return _fetch();
  }

  ///
  ///
  void togglePositiveOnly() {
    if (forwardsGraphBeaconId != null || genealogyMode) {
      return;
    }
    _totalNeighborCounts.clear();
    emit(
      state.copyWith(
        positiveOnly: !state.positiveOnly,
        focus: '',
        hiddenNeighborCounts: const {},
      ),
    );
    graphController.clear();
    _fetchLimits.clear();
    _addedEdgeEndpoints.clear();
    _allEdges.clear();
    unawaited(_fetch());
  }

  ///
  ///
  Future<void> _fetch() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final fetchFocus = forwardsGraphBeaconId ?? state.focus;
      final limitKey = fetchFocus;

      Set<EdgeDirected> edges;
      final source = _graphSource;
      var showNoHelpOffererPathMessage = false;
      String? noPathHelpOffererId;
      var forwardsAuthorId = '';
      if (helpOffererFocusUserId != null &&
          forwardsGraphBeaconId != null &&
          source is ForwardsGraphRepository) {
        final payload = await source.fetchHelpOffererForwardsGraph(
          beaconId: forwardsGraphBeaconId!,
          helpOffererId: helpOffererFocusUserId!,
        );
        edges = payload.edges;
        _helpOffererIds = payload.helpOffererIds;
        forwardsAuthorId = payload.authorId;

        // Focus rule for the three viewer-role cases (see plan):
        //   case 1 (author):         focus = help offerer
        //   case 2 (involved-other): focus = help offerer
        //   case 3 (help-offerer-self): focus = author (chain reads "in reverse")
        // Ego node is always `me` (existing pattern); the role rotates onto
        // whichever principal happens to be the viewer.
        final viewerId = payload.viewerId ?? state.me.id;
        final authorId = payload.authorId;
        final helpOffererId = helpOffererFocusUserId!;
        final isSelf = viewerId == helpOffererId;
        final viewerRole = resolveHelpOffererViewerRole(
          viewerId: viewerId,
          authorId: authorId,
          helpOffererId: helpOffererId,
        );
        if (state.helpOffererViewerRole != viewerRole) {
          emit(state.copyWith(helpOffererViewerRole: viewerRole));
        }
        final hasHelpOffererEndpoint = edges.any(
          (e) => e.src == helpOffererId || e.dst == helpOffererId,
        );
        final derivedFocus = deriveHelpOffererGraphFocus(
          viewerIsHelpOfferer: isSelf,
          authorId: authorId,
          helpOffererId: helpOffererId,
        );
        if (state.focus != derivedFocus) {
          emit(state.copyWith(focus: derivedFocus));
        }
        // Help-offerer-card graph only: keep edges on some directed path from
        // ego (viewer) to focus (help offerer, or author when viewer = help offerer).
        edges = edgesOnSomeDirectedPath(
          edges: edges,
          root: state.me.id,
          focus: derivedFocus,
        );
        showNoHelpOffererPathMessage = !hasHelpOffererEndpoint;
        noPathHelpOffererId = !hasHelpOffererEndpoint ? helpOffererId : null;
      } else if (forwardsGraphBeaconId != null &&
          source is ForwardsGraphRepository) {
        final payload = await source.fetchForwardsGraph(
          beaconId: forwardsGraphBeaconId!,
        );
        edges = payload.edges;
        _helpOffererIds = payload.helpOffererIds;
        forwardsAuthorId = payload.authorId;
      } else if (genealogyMode && source is InviteGenealogyRepository) {
        List<EdgeDirected> rawEdges;
        if (fetchFocus.isEmpty) {
          final graph = await source.fetchGenealogyBootstrap(
            targetId: genealogyTargetId,
          );
          if (state.egoNodeId.isEmpty) {
            emit(
              state.copyWith(
                egoNodeId: graph.viewerNodeKey,
                genealogyTargetNodeKey: graph.targetNodeKey ?? '',
              ),
            );
          }
          _preloadGenealogyNodes(graph.nodes);
          await _fetchGenealogyChildCounts(
            source,
            graph.nodes.map((node) => node.nodeKey),
          );
          rawEdges = _genealogyEdgesFromGraph(graph);
        } else {
          final cursor = _genealogyChildrenCursors[fetchFocus];
          final page = await source.fetchChildren(
            nodeKey: fetchFocus,
            afterCreatedAt: cursor?.$1,
            afterNodeKey: cursor?.$2,
            limit: kFetchWindowSize,
          );
          if (page.edges.isNotEmpty) {
            final last = page.edges.last;
            _genealogyChildrenCursors[fetchFocus] = (
              last.descendantUserCreatedAt,
              last.descendantNodeKey,
            );
          }
          _preloadGenealogyNodes(page.nodes);
          await _fetchGenealogyChildCounts(
            source,
            {
              fetchFocus,
              for (final edge in page.edges) edge.descendantNodeKey,
            },
          );
          rawEdges = [
            for (final e in page.edges)
              (
                src: e.ancestorNodeKey,
                dst: e.descendantNodeKey,
                weight: 0.0,
                node: null,
                branch: null,
                srcTotalNeighborCount: null,
                dstTotalNeighborCount: null,
              ),
          ];
        }
        edges = rawEdges.toSet();
      } else if (genealogyMode) {
        throw StateError(
          'GraphCubit(genealogyMode: true) requires InviteGenealogyRepository',
        );
      } else {
        edges = await _graphSource.fetch(
          positiveOnly: state.positiveOnly,
          context: state.context,
          focus: fetchFocus.isEmpty ? null : fetchFocus,
          limit: _fetchLimits[limitKey] =
              (_fetchLimits[limitKey] ?? 0) + kFetchWindowSize,
          viewerUserId: state.me.id,
        );
      }

      for (final e in edges) {
        if (_nodes.containsKey(e.dst)) continue;
        final isFocus = state.focus.isNotEmpty && state.focus == e.dst;
        final node = e.node;
        if (node != null) {
          _nodes[e.dst] = node
              .copyWithPinned(isFocus)
              .copyWithPositionHint(_nodes.length);
        } else {
          final lazy = await _resolveNodeById(
            e.dst,
            pinned: isFocus,
          );
          if (lazy != null) {
            _nodes[e.dst] = lazy;
          }
        }
      }

      // Ensure every edge source exists as a node (forwards chains never carry
      // node payloads; MeritRank rows may still omit some `src`). Non-user /
      // non-beacon prefixes (C/O) are skipped — this UI only renders those.
      for (final e in edges) {
        if (_nodes.containsKey(e.src)) continue;
        final lazy = await _resolveNodeById(e.src);
        if (lazy != null) {
          _nodes[e.src] = lazy;
        }
      }

      // Add FocusNode in case there were no edges containing it
      if (state.focus.isNotEmpty && !_nodes.containsKey(state.focus)) {
        final lazy = await _resolveNodeById(state.focus, pinned: true);
        if (lazy != null) {
          // When the focused help offerer has no path edges, we still want to show
          // them as an isolated focus node. Give it a stable hint north of root.
          if (noPathHelpOffererId != null &&
              state.focus == noPathHelpOffererId) {
            _nodes[state.focus] = lazy.copyWithPositionHint(
              isolatedHelpOffererPositionHint(lazy.positionHint),
            );
          } else {
            _nodes[state.focus] = lazy;
          }
        }
      }

      if (forwardsGraphBeaconId != null &&
          forwardsAuthorId.isNotEmpty &&
          !_nodes.containsKey(forwardsAuthorId)) {
        final lazy = await _resolveNodeById(
          forwardsAuthorId,
          pinned: state.focus == forwardsAuthorId,
        );
        if (lazy != null) {
          _nodes[forwardsAuthorId] = lazy;
        }
      }

      _applyHelpOffererHighlights();

      emit(state.copyWith(status: StateStatus.isSuccess));

      _updateGraph(edges);

      if (showNoHelpOffererPathMessage) {
        _effects.emit(const ShowMessage(NoHelpOffererForwardPathMessage()));
      }

      // Recenter on the derived focus node in help-offerer-path mode so the
      // viewer immediately lands on the relevant principal (help offerer for
      // case 1/2, author for case 3) instead of the floating ego "Me".
      if (helpOffererFocusUserId != null && state.focus.isNotEmpty) {
        final focusNode = _nodes[state.focus];
        if (focusNode != null) {
          // `jumpToNode` expects the *same instance* that the graph controller
          // currently tracks positions for. When `NodeDetails` instances get
          // replaced in `_nodes` (pinned/help-offerer highlight), passing a stale
          // instance can crash the layout with a null position.
          NodeDetails? controllerNode;
          for (final n in graphController.nodes) {
            if (n.id == focusNode.id) {
              controllerNode = n;
              break;
            }
          }
          final nodeToJump = controllerNode ?? focusNode;
          final canLayout = graphController.canLayout;
          final hasPosition =
              canLayout && graphController.layout.hasPosition(nodeToJump);
          if (!hasPosition) {
            return;
          }
          await Future.value(graphController.jumpToNode(nodeToJump));
        }
      }
    } catch (e) {
      _effects.emit(ShowError(e));
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  Future<NodeDetails?> _resolveNodeById(
    String id, {
    bool pinned = false,
  }) async {
    if (id.startsWith('U')) {
      final profile = await _profileRepository.fetchById(id);
      return UserNode(
        user: profile,
        positionHint: _nodes.length,
        pinned: pinned,
        isHelpOfferer: _helpOffererIds.contains(id),
      );
    }
    if (id.startsWith('B')) {
      try {
        return BeaconNode(
          beacon: await _beaconRepository.fetchBeaconById(id),
          positionHint: _nodes.length,
          pinned: pinned,
        );
      } on BeaconFetchException {
        return null;
      }
    }
    return null;
  }

  void _preloadGenealogyNodes(List<InviteGenealogyNode> nodes) {
    for (final n in nodes) {
      _nodes.putIfAbsent(n.nodeKey, () {
        final isEndpoint =
            n.nodeKey == state.egoNodeId ||
            n.nodeKey == state.genealogyTargetNodeKey;
        if (n.profile != null && n.deletedAt == null) {
          return GenealogyUserNode(
            nodeKey: n.nodeKey,
            user: n.profile!,
            pinned: isEndpoint,
            size: isEndpoint ? 72 : 48,
            positionHint: _nodes.length,
          );
        }
        return GenealogyDeletedNode(
          nodeKey: n.nodeKey,
          label: genealogyAnonymousNodeLabel ?? '',
          pinned: isEndpoint,
          size: isEndpoint ? 72 : 48,
          positionHint: _nodes.length,
        );
      });
    }
  }

  List<EdgeDirected> _genealogyEdgesFromGraph(InviteGenealogyGraph graph) {
    final isBetween = graph.targetNodeKey != null;
    final viewerBranch = isBetween
        ? _genealogyBranchBelowLca(graph, graph.viewerNodeKey)
        : const <String>{};
    final targetBranch = isBetween
        ? _genealogyBranchBelowLca(graph, graph.targetNodeKey!)
        : const <String>{};
    return [
      for (final e in graph.edges)
        (
          src: e.ancestorNodeKey,
          dst: e.descendantNodeKey,
          weight: 0.0,
          node: null,
          branch: isBetween
              ? viewerBranch.contains(e.descendantNodeKey)
                    ? GenealogyEdgeBranch.ego
                    : targetBranch.contains(e.descendantNodeKey)
                    ? GenealogyEdgeBranch.target
                    : GenealogyEdgeBranch.neutral
              : null,
          srcTotalNeighborCount: null,
          dstTotalNeighborCount: null,
        ),
    ];
  }

  Set<String> _genealogyBranchBelowLca(
    InviteGenealogyGraph graph,
    String start,
  ) {
    final parentOf = <String, String>{
      for (final edge in graph.edges)
        edge.descendantNodeKey: edge.ancestorNodeKey,
    };
    final lca = graph.commonAncestorNodeKey;
    final branch = <String>{};
    String? current = start;
    while (current != null && current != lca && branch.add(current)) {
      current = parentOf[current];
    }
    return branch;
  }

  /// Stamps `isHelpOfferer` on every help offerer's [UserNode] currently in
  /// [_nodes]. Called after each fetch so late-arriving nodes pick up the flag.
  void _applyHelpOffererHighlights() {
    if (_helpOffererIds.isEmpty) return;
    for (final id in _helpOffererIds) {
      final node = _nodes[id];
      if (node is UserNode && !node.isHelpOfferer) {
        _nodes[id] = node.copyWithIsHelpOfferer(true);
      }
    }
  }

  Future<void> _fetchGenealogyChildCounts(
    InviteGenealogyRepository source,
    Iterable<String> nodeKeys,
  ) async {
    final keys = nodeKeys.where((key) => key.isNotEmpty).toSet();
    if (keys.isEmpty) {
      return;
    }
    final counts = await source.fetchChildCounts(nodeKeys: keys.toList());
    _totalNeighborCounts.addAll(counts);
  }

  void _captureEndpointTotals(Set<EdgeDirected> edges) {
    if (genealogyMode) {
      return;
    }
    for (final edge in edges) {
      final srcTotal = edge.srcTotalNeighborCount;
      if (srcTotal != null) {
        _totalNeighborCounts[edge.src] = srcTotal;
      }
      final dstTotal = edge.dstTotalNeighborCount;
      if (dstTotal != null) {
        _totalNeighborCounts[edge.dst] = dstTotal;
      }
    }
  }

  void _emitHiddenNeighborCounts() {
    final hidden = _deriveHiddenNeighborCounts();
    if (!_sameHiddenCounts(state.hiddenNeighborCounts, hidden)) {
      emit(state.copyWith(hiddenNeighborCounts: hidden));
    }
  }

  Map<String, int> _deriveHiddenNeighborCounts() {
    if (_totalNeighborCounts.isEmpty) {
      return const {};
    }
    // Count distinct neighbor ids, not edges: a mutual relationship is
    // reported by MeritRank as two directed rows (one per direction), which
    // would otherwise double-count a single neighbor — and since either
    // direction can arrive from a *different* focus query, that miscount
    // could shift a node's badge as a side effect of tapping an unrelated
    // node, once the other direction of an already-known neighbor loads.
    final visibleNeighborIds = <String, Set<String>>{};
    for (final edge in graphController.edges) {
      if (genealogyMode) {
        visibleNeighborIds
            .putIfAbsent(edge.source.id, () => <String>{})
            .add(edge.destination.id);
      } else {
        visibleNeighborIds
            .putIfAbsent(edge.source.id, () => <String>{})
            .add(edge.destination.id);
        visibleNeighborIds
            .putIfAbsent(edge.destination.id, () => <String>{})
            .add(edge.source.id);
      }
    }

    final hidden = <String, int>{};
    for (final entry in _totalNeighborCounts.entries) {
      final visibleCount = visibleNeighborIds[entry.key]?.length ?? 0;
      final hiddenCount = entry.value - visibleCount;
      if (hiddenCount > 0) {
        hidden[entry.key] = hiddenCount;
      }
    }
    return hidden;
  }

  static bool _sameHiddenCounts(Map<String, int> a, Map<String, int> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  void _updateGraph(Set<EdgeDirected> edges) {
    _captureEndpointTotals(edges);
    if (_usesFocusPathVisibility) {
      for (final e in edges) {
        if (state.positiveOnly && e.weight < 0) {
          continue;
        }
        if (e.src == e.dst ||
            !_nodes.containsKey(e.src) ||
            !_nodes.containsKey(e.dst)) {
          continue;
        }
        _allEdges[(e.src, e.dst)] = e;
      }
      _recomputeVisibility();
      return;
    }
    graphController.mutate((mutator) {
      for (final e in edges) {
        if (state.positiveOnly && e.weight < 0) {
          continue;
        }
        final src = _nodes[e.src];
        if (src == null) {
          continue;
        }
        final dst = _nodes[e.dst];
        if (dst == null) {
          continue;
        }
        if (!mutator.controller.nodes.contains(src)) {
          mutator.addNode(src);
        }
        if (!mutator.controller.nodes.contains(dst)) {
          mutator.addNode(dst);
        }
        final endpointKey = (src.id, dst.id);
        if (src.id != dst.id && _addedEdgeEndpoints.add(endpointKey)) {
          mutator.addEdge(_buildEdgeDetails(e, src, dst));
        }
      }

      if (genealogyMode) {
        for (final node in _nodes.values) {
          if (!mutator.controller.nodes.contains(node)) {
            mutator.addNode(node);
          }
        }
      } else if (!mutator.controller.nodes.contains(_egoNode)) {
        mutator.addNode(_egoNode);
      }
      final focusNode = _nodes[state.focus];
      if (focusNode != null && !mutator.controller.nodes.contains(focusNode)) {
        mutator.addNode(focusNode);
      }
    });
    _emitHiddenNeighborCounts();
  }

  EdgeDetails<NodeDetails> _buildEdgeDetails(
    EdgeDirected e,
    NodeDetails src,
    NodeDetails dst,
  ) {
    final egoId = genealogyMode ? state.egoNodeId : _egoNode.id;
    final branchHighlighted =
        e.branch == GenealogyEdgeBranch.ego ||
        e.branch == GenealogyEdgeBranch.target;
    final touchesEgo = egoId.isNotEmpty && (src.id == egoId || dst.id == egoId);
    return EdgeDetails<NodeDetails>(
      source: src,
      destination: dst,
      strokeWidth: branchHighlighted || touchesEgo ? 3 : 2,
      color: switch (e.branch) {
        GenealogyEdgeBranch.ego => _edgeColors.ego,
        GenealogyEdgeBranch.target => _edgeColors.target,
        GenealogyEdgeBranch.neutral => _edgeColors.neutral,
        null =>
          e.weight < 0
              ? _edgeColors.negative
              : touchesEgo
              ? _edgeColors.ego
              : _edgeColors.neutral,
      },
    );
  }

  /// Focus-path spotlight (MeritRank connections graph only): reconciles
  /// [graphController] against the union of edges lying on some directed
  /// ego→focus path plus all edges incident to the current focus (the
  /// fresh neighbors a tap just revealed). Pure filter over [_allEdges] —
  /// hidden data stays cached, so backtracking re-reveals without a refetch.
  void _recomputeVisibility() {
    final focusId = state.focus;
    final visibleEdges = <(String, String), EdgeDirected>{};
    if (focusId.isEmpty) {
      visibleEdges.addAll(_allEdges);
    } else {
      final onPath = edgePairsOnSomeDirectedPath(
        pairs: _allEdges.keys.toSet(),
        root: _egoNode.id,
        focus: focusId,
      );
      for (final entry in _allEdges.entries) {
        if (onPath.contains(entry.key) ||
            entry.key.$1 == focusId ||
            entry.key.$2 == focusId) {
          visibleEdges[entry.key] = entry.value;
        }
      }
    }
    final visibleNodeIds = <String>{
      _egoNode.id,
      if (focusId.isNotEmpty) focusId,
      for (final key in visibleEdges.keys) ...[key.$1, key.$2],
    };

    graphController.mutate((mutator) {
      for (final node in List.of(graphController.nodes)) {
        if (node.id != _egoNode.id && !visibleNodeIds.contains(node.id)) {
          mutator.removeNode(node); // cascades to remove touching edges
        }
      }
      // A surviving edge can still be invisible even with both endpoints
      // visible (e.g. two of ego's siblings linked to each other, neither
      // on-path nor focus-incident).
      for (final edge in List.of(graphController.edges)) {
        if (!visibleEdges.containsKey((edge.source.id, edge.destination.id))) {
          mutator.removeEdge(edge);
        }
      }
      final liveNodes = <String, NodeDetails>{
        for (final n in graphController.nodes) n.id: n,
      };
      for (final id in visibleNodeIds) {
        if (liveNodes.containsKey(id)) {
          continue;
        }
        final node = _nodes[id];
        if (node != null) {
          mutator.addNode(node);
          liveNodes[id] = node;
        }
      }
      final liveEdgeKeys = <(String, String)>{
        for (final e in graphController.edges) (e.source.id, e.destination.id),
      };
      for (final entry in visibleEdges.entries) {
        if (liveEdgeKeys.contains(entry.key)) {
          continue;
        }
        final src = liveNodes[entry.key.$1];
        final dst = liveNodes[entry.key.$2];
        if (src == null || dst == null) {
          continue;
        }
        mutator.addEdge(_buildEdgeDetails(entry.value, src, dst));
      }
    });
    _emitHiddenNeighborCounts();
  }
}
