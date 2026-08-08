// graphController should be here
// ignore_for_file: avoid_public_fields, prefer_void_public_cubit_methods

import 'dart:async';
import 'dart:developer' as developer;
import 'package:get_it/get_it.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/message/common_messages.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/features/invite_genealogy/data/repository/invite_genealogy_repository.dart';
import 'package:tentura/features/invite_genealogy/domain/entity/invite_genealogy_graph.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../data/repository/forwards_graph_repository.dart';
import '../../data/repository/graph_repository.dart';
import '../../data/repository/graph_source_repository.dart';
import '../../domain/entity/edge_details.dart';
import '../../domain/entity/graph_edge_colors.dart';
import '../../domain/entity/graph_mode.dart';
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
    BlockCase? blockCase,
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
       ),
       _graphSource = graphSourceRepository ?? GetIt.I<GraphRepository>(),
       _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _profileRepository =
           profileRepository ?? GetIt.I<ProfileRepositoryPort>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       mode = forwardsGraphBeaconId != null
           ? GraphMode.forwards
           : genealogyMode
           ? GraphMode.genealogy
           : GraphMode.trust,
       super(
         GraphState(
           focus: focus ?? '',
           me: me,
         ),
       ) {
    _pinnedNodeIds.add(_egoNode.id);
    _focusPathIds.add(_egoNode.id);
    if (!genealogyMode) {
      _everFocusedIds.add(_egoNode.id);
    }
    final block =
        blockCase ??
        (GetIt.I.isRegistered<BlockCase>() ? GetIt.I<BlockCase>() : null);
    if (block != null) {
      _blockChanges = block.changes.listen(
        _onBlockVisibilityChanged,
        cancelOnError: false,
      );
    }
    unawaited(_fetch());
  }

  final GraphMode mode;

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

  StreamSubscription<RepositoryEvent<BlockIntent>>? _blockChanges;

  /// Resolved viewer role for the help-offerer-path view; null when the cubit
  /// is operating in any other mode (regular forwards graph or MeritRank).
  /// Set during [_fetch] once `authorId`/`viewerId` are known.
  ForwardsGraphViewerRole? get helpOffererViewerRole =>
      state.helpOffererViewerRole;

  final graphController =
      GraphController<NodeDetails, EdgeDetails<NodeDetails>>();

  final UserNode _egoNode;

  final _fetchLimits = <String, int>{};

  /// Neighbor ids already present in [_allEdges] for [focus] (or ego when empty).
  Set<String> _knownNeighborIdsForFocus(String focus) {
    final anchor = focus.isEmpty ? _egoNode.id : focus;
    return {
      for (final entry in _allEdges.entries)
        if (entry.key.$1 == anchor)
          entry.key.$2
        else if (entry.key.$2 == anchor)
          entry.key.$1,
    };
  }

  final _genealogyChildrenCursors = <String, (DateTime, String)>{};

  final _genealogyParentChainNodeIds = <String>{};

  final _totalNeighborCounts = <String, int>{};

  final _addedEdgeEndpoints = <(String, String)>{};

  final _pinnedNodeIds = <String>{};

  final _focusPathIds = <String>[];

  /// Nodes that have been focus at least once this session (plus seeded
  /// genealogy parent-chain). Used to distinguish explore vs rollback taps.
  final _everFocusedIds = <String>{};

  String _forwardsAuthorId = '';

  /// Every edge ever fetched this session, keyed by `(src, dst)` — the
  /// source of truth for focus-path visibility. Unlike `graphController`
  /// (which only holds what is currently rendered), nothing is ever removed
  /// here except on full resets ([setContext]).
  final _allEdges = <(String, String), EdgeDirected>{};

  /// Bumped when [_allEdges] is discarded ([setContext]). Stale async merges
  /// must not write into a newer cache generation.
  int _cacheEpoch = 0;

  /// Bumped at each [_fetch] start so overlapping fetches supersede older ones.
  int _fetchEpoch = 0;

  late final Map<String, NodeDetails> _nodes = genealogyMode
      ? <String, NodeDetails>{}
      : <String, NodeDetails>{_egoNode.id: _egoNode};

  bool get _isTrustGraph => mode == GraphMode.trust;

  /// Active help offerers for [forwardsGraphBeaconId] (forwards graph only).
  /// Highlighted via [UserNode.isHelpOfferer] in the renderer.
  Set<String> _helpOffererIds = const <String>{};

  /// Focus-path spotlight is shared by the MeritRank connections graph and
  /// invite genealogy. Forwards graph remains additive/static.
  bool get _usesFocusPathVisibility => mode != GraphMode.forwards;

  String get _focusRootId => genealogyMode ? state.egoNodeId : _egoNode.id;

  Set<String> get _alwaysVisibleNodeIds =>
      genealogyMode ? _genealogyParentChainNodeIds : const <String>{};

  @override
  Future<void> close() async {
    await _blockChanges?.cancel();
    graphController.dispose();
    return super.close();
  }

  void _onBlockVisibilityChanged(RepositoryEvent<BlockIntent> event) {
    if (mode == GraphMode.forwards) {
      return;
    }
    // A block/unblock event for a user that isn't part of anything currently
    // loaded has nothing to invalidate here — wiping the whole cache in that
    // case is exactly the "unrelated friends disappear" defect (issue #111).
    if (!_nodes.containsKey(event.id) && event.id != _egoNode.id) {
      return;
    }
    _cacheEpoch++;
    _fetchEpoch++;
    graphController.clear();
    _fetchLimits.clear();
    _addedEdgeEndpoints.clear();
    _allEdges.clear();
    if (mode == GraphMode.genealogy) {
      _genealogyChildrenCursors.clear();
      _genealogyParentChainNodeIds.clear();
      _nodes.clear();
      _everFocusedIds.clear();
      _focusPathIds.clear();
      emit(
        state.copyWith(
          focus: '',
          focusPathDepth: 0,
          hiddenNeighborCounts: const {},
          egoNodeId: '',
          genealogyTargetNodeKey: '',
        ),
      );
    } else {
      _nodes
        ..clear()
        ..[_egoNode.id] = _egoNode;
      _everFocusedIds
        ..clear()
        ..add(_egoNode.id);
      _focusPathIds
        ..clear()
        ..add(_egoNode.id);
      emit(
        state.copyWith(
          focus: '',
          focusPathDepth: _focusPathIds.length,
          hiddenNeighborCounts: const {},
        ),
      );
    }
    unawaited(_fetch());
  }

  /// True when there is somewhere to go back to.
  bool get canPopFocus => state.focusPathDepth > 1;

  /// Exploration trail from origin to the current focus (inclusive).
  List<String> get focusPath => List.unmodifiable(_focusPathIds);

  /// Layout root for forwards graphs; empty in other modes.
  Set<String> get forwardsRootIds =>
      _forwardsAuthorId.isEmpty ? const {} : {_forwardsAuthorId};

  /// Origin node for focus-path visibility (ego in trust, viewer in genealogy).
  String get originNodeId => _focusRootId;

  void jumpToEgo({bool resetScale = false}) {
    final node = genealogyMode ? _nodes[state.egoNodeId] : _egoNode;
    if (node == null) return;
    if (!graphController.canLayout ||
        !graphController.layout.hasPosition(node)) {
      return;
    }
    unawaited(
      Future.value(graphController.jumpToNode(node, resetScale: resetScale)),
    );
  }

  /// True when [id] owns the active spotlight (including trust overview).
  bool isCurrentFocus(String id) {
    if (state.focus == id) {
      return true;
    }
    return _isTrustGraph && state.focus.isEmpty && id == _focusRootId;
  }

  /// True when the current focus can page in another neighbourhood window.
  /// Only meaningful for [isCurrentFocus] nodes and the Expand control.
  bool canPageMore(String id) {
    if (mode == GraphMode.forwards) {
      return false;
    }
    return (state.hiddenNeighborCounts[id] ?? 0) > 0;
  }

  /// Whether [id] has been focused before (rollback taps select only).
  @visibleForTesting
  bool hasEverFocused(String id) => _everFocusedIds.contains(id);

  /// @deprecated Use [isCurrentFocus], [canPageMore], and [handleNodeTap].
  @Deprecated('Use isCurrentFocus, canPageMore, and handleNodeTap')
  bool canExpandNode(String id) => canPageMore(id);

  /// Highlights [node] on the graph and updates the exploration trail.
  /// Never pages neighbourhood — use [expandNode]. May request structural
  /// closure among the resulting visible set (trust graph only).
  void selectNode(NodeDetails node, {bool ensureStructuralEdges = true}) {
    if (mode == GraphMode.genealogy) {
      _pinGenealogyParentChainNodes();
    }
    if (state.focus == node.id) {
      return;
    }
    _everFocusedIds.add(node.id);
    _updateFocusPath(node.id);
    _emitFocusAndDepth(focus: node.id);
    if (_usesFocusPathVisibility) {
      _syncFocusPathPins();
      _recomputeVisibility();
      if (ensureStructuralEdges) {
        unawaited(_ensureVisibleStructuralEdges());
      }
    }
  }

  /// Selects [node] when needed, then pages in the next neighbourhood window.
  Future<void> expandNode(NodeDetails node) async {
    final trustOverviewPaging =
        _isTrustGraph && state.focus.isEmpty && node.id == _focusRootId;
    if (mode != GraphMode.forwards) {
      emit(state.copyWith(status: StateStatus.isLoading));
    }
    if (!trustOverviewPaging && state.focus != node.id) {
      // Skip select-time ensure: [_fetch] closes over the staged neighbourhood
      // before the first paint of new nodes.
      selectNode(node, ensureStructuralEdges: false);
    } else {
      _everFocusedIds.add(node.id);
    }
    if (mode != GraphMode.forwards) {
      await _fetch();
    }
  }

  /// Routes a node tap by explore / rollback intent (trust + genealogy).
  void handleNodeTap(NodeDetails node) {
    if (mode == GraphMode.forwards) {
      selectNode(node);
      return;
    }
    if (isCurrentFocus(node.id)) {
      if (canPageMore(node.id)) {
        unawaited(expandNode(node));
      }
      return;
    }
    if (_everFocusedIds.contains(node.id)) {
      selectNode(node);
      return;
    }
    unawaited(expandNode(node));
  }

  /// Steps one hop back along the exploration trail. Does not page
  /// neighbourhood (cached trail data); may request structural closure among
  /// the restored visible set on the trust graph.
  void popFocus() {
    if (!canPopFocus) return;
    _focusPathIds.removeLast();
    final previous = _focusPathIds.last;
    _emitFocusAndDepth(
      focus: previous == _focusRootId ? '' : previous,
    );
    _syncFocusPathPins();
    _recomputeVisibility();
    unawaited(_ensureVisibleStructuralEdges());
    final node = _nodes[previous];
    if (node != null &&
        graphController.canLayout &&
        graphController.layout.hasPosition(node)) {
      unawaited(Future.value(graphController.jumpToNode(node)));
    }
  }

  /// Returns to the origin without dropping the cache: clears the trail, unpins
  /// every node except the root, recomputes visibility and re-centres.
  void resetToEgo() {
    _resetFocusPathRoot(_focusRootId);
    _pinnedNodeIds
      ..clear()
      ..add(_focusRootId);
    for (final entry in _nodes.entries) {
      if (entry.value.pinned && entry.key != _focusRootId) {
        _nodes[entry.key] = entry.value.copyWithPinned(false);
      }
    }
    _emitFocusAndDepth(focus: '');
    _syncFocusPathPins();
    _recomputeVisibility();
    unawaited(_ensureVisibleStructuralEdges());
    jumpToEgo(resetScale: true);
  }

  void _emitFocusAndDepth({required String focus}) {
    emit(
      state.copyWith(
        focus: focus,
        focusPathDepth: _focusPathIds.length,
      ),
    );
  }

  /// Fits the active path into the viewport. With a trail of one (only the
  /// origin) it fits the origin together with all of its visible neighbours.
  /// Patches every loaded live-user node for [updated.id] without refetching or
  /// relayout. Self updates are ignored — ego projection is owned by
  /// [ProfileCubit].
  void patchLoadedProfile(Profile updated) {
    if (updated.id == state.me.id) {
      assert(
        false,
        'Self profile updates belong to ProfileCubit; never patch ego Me projection.',
      );
      return;
    }
    for (final entry in _nodes.entries) {
      final node = entry.value;
      final NodeDetails? replacement = switch (node) {
        UserNode userNode when userNode.user.id == updated.id => UserNode(
          user: updated,
          size: userNode.size,
          pinned: userNode.pinned,
          isHelpOfferer: userNode.isHelpOfferer,
        ),
        GenealogyUserNode genealogyNode
            when genealogyNode.user.id == updated.id =>
          GenealogyUserNode(
            nodeKey: genealogyNode.nodeKey,
            user: updated,
            size: genealogyNode.size,
            pinned: genealogyNode.pinned,
          ),
        _ => null,
      };
      if (replacement == null) {
        continue;
      }
      _nodes[entry.key] = replacement;
      final controllerNode = _controllerNodeById(entry.key);
      if (controllerNode != null &&
          graphController.nodes.contains(controllerNode)) {
        graphController.replaceNode(controllerNode, replacement);
      }
    }
  }

  void fitCurrentPath() {
    if (!graphController.canLayout) return;
    var ids = _focusPathIds.toSet();
    if (ids.length <= 1) {
      for (final edge in graphController.edges) {
        if (edge.source.id == _focusRootId) ids.add(edge.destination.id);
        if (edge.destination.id == _focusRootId) ids.add(edge.source.id);
      }
    }
    graphController.fitToNodes(
      graphController.nodes.where((n) => ids.contains(n.id)),
    );
  }

  @Deprecated('Use selectNode or expandNode')
  void setFocus(NodeDetails node) => selectNode(node);

  void _syncFocusPathPins() {
    final pinIds = <String>{
      _focusRootId,
      ..._focusPathIds,
      if (genealogyMode) ..._genealogyParentChainNodeIds,
    };
    _pinnedNodeIds
      ..clear()
      ..addAll(pinIds);
    for (final entry in _nodes.entries) {
      final shouldPin = pinIds.contains(entry.key);
      if (entry.value.pinned == shouldPin) {
        continue;
      }
      final updated = entry.value.copyWithPinned(shouldPin);
      _nodes[entry.key] = updated;
      final controllerNode = _controllerNodeById(entry.key);
      if (controllerNode != null &&
          graphController.nodes.contains(controllerNode)) {
        graphController.replaceNode(controllerNode, updated);
      }
    }
  }

  NodeDetails _pinNode(NodeDetails node) {
    final controllerNode = _controllerNodeById(node.id) ?? node;
    _pinnedNodeIds.add(controllerNode.id);
    final pinnedNode = _pinnedCopyIfNeeded(controllerNode);
    if (!controllerNode.pinned &&
        graphController.nodes.contains(controllerNode)) {
      graphController.replaceNode(controllerNode, pinnedNode);
    }
    _nodes[controllerNode.id] = pinnedNode;
    return pinnedNode;
  }

  NodeDetails? _controllerNodeById(String id) {
    for (final node in graphController.nodes) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }

  NodeDetails _pinnedCopyIfNeeded(NodeDetails node) {
    if (!_pinnedNodeIds.contains(node.id) || node.pinned) {
      return node;
    }
    return node.copyWithPinned(true);
  }

  NodeDetails? _nodeForGraph(String id) {
    final node = _nodes[id];
    if (node == null) {
      return null;
    }
    final graphNode = _pinnedCopyIfNeeded(node);
    if (!node.pinned && graphNode.pinned) {
      _nodes[id] = graphNode;
    }
    return graphNode;
  }

  void _updateFocusPath(String focusId) {
    if (!_usesFocusPathVisibility) {
      return;
    }
    final egoId = _focusRootId;
    if (egoId.isEmpty) {
      return;
    }
    if (_focusPathIds.isEmpty) {
      _focusPathIds.add(egoId);
    }
    if (focusId.isEmpty || focusId == egoId) {
      _focusPathIds
        ..clear()
        ..add(egoId);
      return;
    }
    final existingIndex = _focusPathIds.indexOf(focusId);
    if (existingIndex >= 0) {
      _focusPathIds.removeRange(existingIndex + 1, _focusPathIds.length);
      return;
    }
    final tip = _focusPathIds.last;
    if (_areAdjacentInAllEdges(tip, focusId)) {
      _focusPathIds.add(focusId);
      return;
    }
    final rebuilt = _shortestPathInAllEdges(egoId, focusId);
    if (rebuilt != null) {
      _focusPathIds
        ..clear()
        ..addAll(rebuilt);
      return;
    }
    _focusPathIds.add(focusId);
  }

  bool _areAdjacentInAllEdges(String a, String b) {
    if (a == b) {
      return true;
    }
    return _allEdges.containsKey((a, b)) || _allEdges.containsKey((b, a));
  }

  /// Shortest undirected path between [from] and [to] over [_allEdges], or null.
  List<String>? _shortestPathInAllEdges(String from, String to) {
    if (from == to) {
      return [from];
    }
    final adjacency = <String, Set<String>>{};
    for (final key in _allEdges.keys) {
      adjacency.putIfAbsent(key.$1, () => {}).add(key.$2);
      adjacency.putIfAbsent(key.$2, () => {}).add(key.$1);
    }
    if (!adjacency.containsKey(from) || !adjacency.containsKey(to)) {
      return null;
    }
    final queue = <String>[from];
    final previous = <String, String?>{from: null};
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (current == to) {
        break;
      }
      for (final neighbor in adjacency[current] ?? const <String>{}) {
        if (previous.containsKey(neighbor)) {
          continue;
        }
        previous[neighbor] = current;
        queue.add(neighbor);
      }
    }
    if (!previous.containsKey(to)) {
      return null;
    }
    final path = <String>[];
    var walk = to;
    while (true) {
      path.add(walk);
      final parent = previous[walk];
      if (parent == null) {
        break;
      }
      walk = parent;
    }
    return path.reversed.toList();
  }

  void _resetFocusPathRoot(String rootId) {
    if (rootId.isEmpty) {
      return;
    }
    _focusPathIds
      ..clear()
      ..add(rootId);
  }

  void _seedGenealogyEverFocused() {
    _everFocusedIds
      ..addAll(_genealogyParentChainNodeIds)
      ..add(_focusRootId);
  }

  ///
  ///
  Future<void> setContext(String? context) {
    if (mode != GraphMode.trust) {
      return Future.value();
    }
    _cacheEpoch++;
    _fetchEpoch++;
    _totalNeighborCounts.clear();
    _focusPathIds
      ..clear()
      ..add(_egoNode.id);
    emit(
      state.copyWith(
        context: context ?? '',
        focus: '',
        focusPathDepth: _focusPathIds.length,
        hiddenNeighborCounts: const {},
      ),
    );
    graphController.clear();
    _fetchLimits.clear();
    _addedEdgeEndpoints.clear();
    _allEdges.clear();
    _everFocusedIds
      ..clear()
      ..add(_egoNode.id);
    return _fetch();
  }

  ///
  ///
  void togglePositiveOnly() {
    if (mode != GraphMode.trust) {
      return;
    }
    emit(state.copyWith(positiveOnly: !state.positiveOnly));
    _recomputeVisibility();
  }

  ///
  ///
  Future<void> _fetch() async {
    final cacheEpoch = _cacheEpoch;
    final fetchEpoch = ++_fetchEpoch;
    var loadingOwned = false;
    try {
      emit(state.copyWith(status: StateStatus.isLoading));
      loadingOwned = true;

      final fetchFocus = forwardsGraphBeaconId ?? state.focus;
      final limitKey = fetchFocus;

      Set<EdgeDirected> edges;
      final source = _graphSource;
      var showNoHelpOffererPathMessage = false;
      var forwardsAuthorId = '';
      if (helpOffererFocusUserId != null &&
          forwardsGraphBeaconId != null &&
          source is ForwardsGraphRepository) {
        final payload = await source.fetchHelpOffererForwardsGraph(
          beaconId: forwardsGraphBeaconId!,
          helpOffererId: helpOffererFocusUserId!,
        );
        if (!_fetchStillValid(cacheEpoch, fetchEpoch)) return;
        edges = payload.edges;
        _helpOffererIds = payload.helpOffererIds;
        _forwardsAuthorId = payload.authorId;
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
      } else if (forwardsGraphBeaconId != null &&
          source is ForwardsGraphRepository) {
        final payload = await source.fetchForwardsGraph(
          beaconId: forwardsGraphBeaconId!,
        );
        if (!_fetchStillValid(cacheEpoch, fetchEpoch)) return;
        edges = payload.edges;
        _helpOffererIds = payload.helpOffererIds;
        _forwardsAuthorId = payload.authorId;
        forwardsAuthorId = payload.authorId;
      } else if (genealogyMode && source is InviteGenealogyRepository) {
        List<EdgeDirected> rawEdges;
        if (fetchFocus.isEmpty) {
          final graph = await source.fetchGenealogyBootstrap(
            targetId: genealogyTargetId,
          );
          if (!_fetchStillValid(cacheEpoch, fetchEpoch)) return;
          if (state.egoNodeId.isEmpty) {
            _resetFocusPathRoot(graph.viewerNodeKey);
            emit(
              state.copyWith(
                egoNodeId: graph.viewerNodeKey,
                genealogyTargetNodeKey: graph.targetNodeKey ?? '',
                focusPathDepth: _focusPathIds.length,
              ),
            );
          }
          _genealogyParentChainNodeIds.addAll(
            graph.nodes.map((node) => node.nodeKey),
          );
          _seedGenealogyEverFocused();
          _preloadGenealogyNodes(graph.nodes);
          await _fetchGenealogyChildCounts(
            source,
            graph.nodes.map((node) => node.nodeKey),
          );
          if (!_fetchStillValid(cacheEpoch, fetchEpoch)) return;
          rawEdges = _genealogyEdgesFromGraph(graph);
        } else {
          final cursor = _genealogyChildrenCursors[fetchFocus];
          final page = await source.fetchChildren(
            nodeKey: fetchFocus,
            afterCreatedAt: cursor?.$1,
            afterNodeKey: cursor?.$2,
            limit: kFetchWindowSize,
          );
          if (!_fetchStillValid(cacheEpoch, fetchEpoch)) return;
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
          if (!_fetchStillValid(cacheEpoch, fetchEpoch)) return;
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
        // Trust graph: stage neighbourhood outside [_allEdges] until visible-set
        // closure returns so sync recomputes cannot paint unclosed new nodes.
        final excludeNeighborIds = _knownNeighborIdsForFocus(fetchFocus);
        final star = await _graphSource.fetch(
          positiveOnly: state.positiveOnly,
          context: state.context,
          focus: fetchFocus.isEmpty ? null : fetchFocus,
          limit: kFetchWindowSize,
          viewerUserId: state.me.id,
          excludeNeighborIds: excludeNeighborIds,
        );
        if (!_fetchStillValid(cacheEpoch, fetchEpoch)) return;

        await _resolveEdgeEndpoints(star);
        if (!_fetchStillValid(cacheEpoch, fetchEpoch)) return;

        final visibleIds = _computeVisibleNodeIds(
          extraIds: {
            for (final e in star) ...[e.src, e.dst],
          },
        );
        var closure = const <EdgeDirected>{};
        try {
          if (visibleIds.length >= 2) {
            closure = await _graphSource.fetchEdgesBetween(
              nodeIds: visibleIds,
              positiveOnly: state.positiveOnly,
            );
          }
        } catch (e, st) {
          developer.log(
            'graph_edges_between failed; painting neighbourhood only',
            name: 'GraphCubit',
            error: e,
            stackTrace: st,
          );
        }
        if (!_fetchStillValid(cacheEpoch, fetchEpoch)) return;

        await _resolveEdgeEndpoints(closure);
        if (!_fetchStillValid(cacheEpoch, fetchEpoch)) return;

        _mergeEdgesIntoCache(star);
        _mergeEdgesIntoCache(closure);
        if (limitKey.isNotEmpty) {
          _fetchLimits[limitKey] = 1;
        }
        emit(state.copyWith(status: StateStatus.isSuccess));
        loadingOwned = false;
        _recomputeVisibility();
        // Second pass over the actual on-screen set repairs a failed/empty
        // first closure and matches the product invariant literally.
        unawaited(_ensureVisibleStructuralEdges());
        return;
      }

      await _resolveEdgeEndpoints(edges);
      if (!_fetchStillValid(cacheEpoch, fetchEpoch)) return;

      if (forwardsGraphBeaconId != null &&
          forwardsAuthorId.isNotEmpty &&
          !_nodes.containsKey(forwardsAuthorId)) {
        final lazy = await _resolveNodeById(
          forwardsAuthorId,
          pinned: state.focus == forwardsAuthorId,
        );
        if (!_fetchStillValid(cacheEpoch, fetchEpoch)) return;
        if (lazy != null) {
          _nodes[forwardsAuthorId] = lazy;
        }
      }

      _applyHelpOffererHighlights();

      emit(state.copyWith(status: StateStatus.isSuccess));
      loadingOwned = false;

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
      if (!isClosed) {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
      loadingOwned = false;
    } finally {
      if (loadingOwned && !isClosed) {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    }
  }

  bool _fetchStillValid(int cacheEpoch, int fetchEpoch) =>
      !isClosed && cacheEpoch == _cacheEpoch && fetchEpoch == _fetchEpoch;

  Future<void> _resolveEdgeEndpoints(Set<EdgeDirected> edges) async {
    for (final e in edges) {
      if (_nodes.containsKey(e.dst)) continue;
      final isFocus = state.focus.isNotEmpty && state.focus == e.dst;
      final node = e.node;
      if (node != null) {
        _nodes[e.dst] = node.copyWithPinned(isFocus);
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
  }

  Future<NodeDetails?> _resolveNodeById(
    String id, {
    bool pinned = false,
  }) async {
    if (id.startsWith('U')) {
      final profile = await _profileRepository.fetchById(id);
      return UserNode(
        user: profile,
        pinned: pinned,
        isHelpOfferer: _helpOffererIds.contains(id),
      );
    }
    if (id.startsWith('B')) {
      try {
        return BeaconNode(
          beacon: await _beaconRepository.fetchBeaconById(id),
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
          );
        }
        return GenealogyDeletedNode(
          nodeKey: n.nodeKey,
          label: genealogyAnonymousNodeLabel ?? '',
          pinned: isEndpoint,
          size: isEndpoint ? 72 : 48,
        );
      });
    }
  }

  void _pinGenealogyParentChainNodes() {
    for (final id in _genealogyParentChainNodeIds) {
      final node = _controllerNodeById(id) ?? _nodes[id];
      if (node != null) {
        _pinNode(node);
      }
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
    final renderedNodeIds = graphController.nodes
        .map((node) => node.id)
        .toSet();
    for (final entry in _totalNeighborCounts.entries) {
      if (!renderedNodeIds.contains(entry.key)) {
        continue;
      }
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
    if (_usesFocusPathVisibility) {
      _mergeEdgesIntoCache(edges);
      _recomputeVisibility();
      return;
    }
    _captureEndpointTotals(edges);
    graphController.mutate((mutator) {
      for (final e in edges) {
        if (state.positiveOnly && e.weight < 0) {
          continue;
        }
        final src = _nodeForGraph(e.src);
        if (src == null) {
          continue;
        }
        final dst = _nodeForGraph(e.dst);
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

      if (!mutator.controller.nodes.contains(_egoNode)) {
        mutator.addNode(_egoNode);
      }
      final focusNode = _nodeForGraph(state.focus);
      if (focusNode != null && !mutator.controller.nodes.contains(focusNode)) {
        mutator.addNode(focusNode);
      }
    });
    _emitHiddenNeighborCounts();
  }

  /// Merges [edges] into [_allEdges]. Returns true if any new endpoint pair
  /// was inserted (overwrites of existing keys do not count).
  bool _mergeEdgesIntoCache(Set<EdgeDirected> edges) {
    _captureEndpointTotals(edges);
    var added = false;
    for (final e in edges) {
      if (e.src == e.dst ||
          !_nodes.containsKey(e.src) ||
          !_nodes.containsKey(e.dst)) {
        continue;
      }
      final key = (e.src, e.dst);
      if (!_allEdges.containsKey(key)) {
        added = true;
      }
      _allEdges[key] = e;
    }
    return added;
  }

  /// Visible node ids for the current focus/path (plus optional [extraIds],
  /// e.g. staged neighbourhood endpoints not yet in [_allEdges]).
  Set<String> _computeVisibleNodeIds({Set<String> extraIds = const {}}) {
    final focusId = state.focus;
    final rootId = _focusRootId;
    final hideNegative = state.positiveOnly;
    final visibleNodeIds = <String>{
      if (rootId.isNotEmpty) rootId,
      ..._alwaysVisibleNodeIds,
      ..._focusPathIds,
      if (focusId.isNotEmpty) focusId,
      ...extraIds,
    };
    if (focusId.isEmpty) {
      for (final entry in _allEdges.entries) {
        if (hideNegative && entry.value.weight < 0) {
          continue;
        }
        visibleNodeIds
          ..add(entry.key.$1)
          ..add(entry.key.$2);
      }
    } else {
      for (final entry in _allEdges.entries) {
        if (hideNegative && entry.value.weight < 0) {
          continue;
        }
        if (entry.key.$1 == focusId) {
          visibleNodeIds.add(entry.key.$2);
        } else if (entry.key.$2 == focusId) {
          visibleNodeIds.add(entry.key.$1);
        }
      }
    }
    return visibleNodeIds;
  }

  /// Best-effort structural closure among currently visible trust-graph nodes.
  Future<void> _ensureVisibleStructuralEdges() async {
    if (!_isTrustGraph) {
      return;
    }
    final cacheEpoch = _cacheEpoch;
    // Prefer nodes actually on the canvas — that is the product invariant.
    final ids = {
      for (final node in graphController.nodes) node.id,
    };
    if (ids.length < 2) {
      ids.addAll(_computeVisibleNodeIds());
    }
    if (ids.length < 2) {
      return;
    }
    Set<EdgeDirected> closure;
    try {
      closure = await _graphSource.fetchEdgesBetween(
        nodeIds: ids,
        positiveOnly: state.positiveOnly,
      );
    } catch (e, st) {
      developer.log(
        'graph_edges_between (ensure) failed',
        name: 'GraphCubit',
        error: e,
        stackTrace: st,
      );
      return;
    }
    if (isClosed || cacheEpoch != _cacheEpoch) {
      return;
    }
    await _resolveEdgeEndpoints(closure);
    if (isClosed || cacheEpoch != _cacheEpoch) {
      return;
    }
    if (!_mergeEdgesIntoCache(closure)) {
      return;
    }
    _recomputeVisibility();
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
    final isTrustGraph = mode == GraphMode.trust;
    return EdgeDetails<NodeDetails>(
      source: src,
      destination: dst,
      strokeWidth: branchHighlighted || touchesEgo ? 3 : 2,
      isReciprocal: isTrustGraph && _allEdges.containsKey((dst.id, src.id)),
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

  /// A mutual trust pair is visually an undirected relation. Keep its two
  /// directed records for traversal and focus-path calculations, but render a
  /// single, stable representative so its bidirectional animation stays on
  /// one edge instead of creating overlapping/double-lane geometry.
  bool _shouldRenderEdge((String, String) key) {
    if (mode != GraphMode.trust) return true;
    if (!_allEdges.containsKey((key.$2, key.$1))) return true;
    return key.$1.compareTo(key.$2) <= 0;
  }

  /// Focus-path spotlight: reconciles [graphController] against the tap trail
  /// plus the focus neighbourhood. Once a node is visible, every cached edge
  /// linking it to any other visible node is drawn (including closure chords
  /// to ancestors already on the canvas). Pure filter over [_allEdges] —
  /// hidden data stays cached, so backtracking re-reveals without a refetch.
  void _recomputeVisibility() {
    graphController.spawnPositionResolver = (node) {
      final focusNode = _nodes[state.focus];
      if (focusNode == null || !graphController.canLayout) return null;
      return graphController.layout.getPositionOrNull(focusNode);
    };

    final focusId = state.focus;
    final rootId = _focusRootId;
    final visibleEdges = <(String, String), EdgeDirected>{};
    final hideNegative = state.positiveOnly;

    void reveal((String, String) key, EdgeDirected edge) {
      if (hideNegative && edge.weight < 0) return;
      visibleEdges[key] = edge;
    }

    final visibleNodeIds = _computeVisibleNodeIds();
    if (focusId.isEmpty) {
      for (final entry in _allEdges.entries) {
        reveal(entry.key, entry.value);
      }
    } else {
      for (final entry in _allEdges.entries) {
        if (visibleNodeIds.contains(entry.key.$1) &&
            visibleNodeIds.contains(entry.key.$2)) {
          reveal(entry.key, entry.value);
        }
      }
    }
    graphController.mutate((mutator) {
      for (final node in List.of(graphController.nodes)) {
        if (node.id != rootId && !visibleNodeIds.contains(node.id)) {
          mutator.removeNode(node); // cascades to remove touching edges
        }
      }
      for (final edge in List.of(graphController.edges)) {
        final key = (edge.source.id, edge.destination.id);
        if (!visibleEdges.containsKey(key) || !_shouldRenderEdge(key)) {
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
        final node = _nodeForGraph(id);
        if (node != null) {
          mutator.addNode(node);
          liveNodes[id] = node;
        }
      }
      final liveEdgeKeys = <(String, String)>{
        for (final e in graphController.edges) (e.source.id, e.destination.id),
      };
      for (final entry in visibleEdges.entries) {
        if (!_shouldRenderEdge(entry.key) || liveEdgeKeys.contains(entry.key)) {
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
