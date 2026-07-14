// graphController should be here
// ignore_for_file: avoid_public_fields, prefer_void_public_cubit_methods

import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/message/common_messages.dart';

import 'package:tentura/features/invite_genealogy/domain/entity/invite_genealogy_graph.dart';

import '../../domain/entity/edge_details.dart';
import '../../domain/entity/graph_edge_colors.dart';
import '../../domain/entity/edge_directed.dart';
import '../../domain/forward_graph_focus_rules.dart';
import '../../domain/prune_directed_paths.dart';
import '../../domain/entity/node_details.dart';
import '../../domain/use_case/graph_case.dart';
import 'graph_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export '../../domain/forward_graph_focus_rules.dart';
export 'graph_state.dart';

class GraphCubit extends Cubit<GraphState> {
  GraphCubit({
    required Profile me,
    required GraphEdgeColors edgeColors,
    String? focus,
    GraphCase? graphCase,

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
       _case = graphCase ?? GetIt.I<GraphCase>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(
         GraphState(
           focus: focus ?? '',
           me: me,
         ),
       ) {
    _pinnedNodeIds.add(_egoNode.id);
    _focusPathIds.add(_egoNode.id);
    _projectionChangesSub = _case
        .projectionChanges(
          mode: _projectionMode,
          beaconId: forwardsGraphBeaconId,
        )
        .listen(_onProjectionChanged, cancelOnError: false);
    _accountChangesSub = _case.accountChanges.listen(
      _onAccountChanged,
      cancelOnError: false,
    );
    unawaited(_fetch());
  }

  final GraphCase _case;

  final String? forwardsGraphBeaconId;

  final String? helpOffererFocusUserId;

  final bool genealogyMode;

  final String? genealogyTargetId;

  final String? genealogyAnonymousNodeLabel;

  final UiEffectPort _effects;

  final GraphEdgeColors _edgeColors;

  late final StreamSubscription<GraphProjectionChange> _projectionChangesSub;
  late final StreamSubscription<String> _accountChangesSub;

  static const _refreshDebounce = Duration(milliseconds: 100);
  Timer? _refreshTimer;
  int _fetchGeneration = 0;
  bool _accountObserved = false;

  GraphProjectionMode get _projectionMode => genealogyMode
      ? GraphProjectionMode.inviteGenealogy
      : forwardsGraphBeaconId != null
      ? GraphProjectionMode.forwards
      : GraphProjectionMode.meritRank;

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

  final _genealogyParentChainNodeIds = <String>{};

  final _totalNeighborCounts = <String, int>{};

  final _addedEdgeEndpoints = <(String, String)>{};

  final _pinnedNodeIds = <String>{};

  final _focusPathIds = <String>[];

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

  /// Focus-path spotlight is shared by the MeritRank connections graph and
  /// invite genealogy. Forwards graph remains additive/static.
  bool get _usesFocusPathVisibility => forwardsGraphBeaconId == null;

  String get _focusRootId => genealogyMode ? state.egoNodeId : _egoNode.id;

  Set<String> get _alwaysVisibleNodeIds =>
      genealogyMode ? _genealogyParentChainNodeIds : const <String>{};

  @override
  Future<void> close() async {
    _refreshTimer?.cancel();
    _fetchGeneration++;
    await _projectionChangesSub.cancel();
    await _accountChangesSub.cancel();
    _case.disposeProjection();
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
    if (genealogyMode) {
      _pinGenealogyParentChainNodes();
    }
    if (state.focus != node.id) {
      emit(state.copyWith(focus: node.id));
      _updateFocusPath(node.id);
      _pinNode(node);
      if (_usesFocusPathVisibility) {
        _recomputeVisibility();
        // Backtracking onto a node whose neighbors are already loaded is a
        // pure visibility change — re-reveal instantly, no refetch. A repeat
        // tap on the *current* focus still falls through to _fetch to page
        // in more neighbors.
        alreadyFetched = _fetchLimits.containsKey(node.id);
      }
    }
    if (forwardsGraphBeaconId == null && !alreadyFetched) {
      unawaited(_fetch());
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
    _focusPathIds.add(focusId);
  }

  void _resetFocusPathRoot(String rootId) {
    if (rootId.isEmpty) {
      return;
    }
    _focusPathIds
      ..clear()
      ..add(rootId);
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
    _prepareProjectionReplacement();
    _fetchLimits.clear();
    _pinnedNodeIds
      ..clear()
      ..add(_egoNode.id);
    _focusPathIds
      ..clear()
      ..add(_egoNode.id);
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
    _prepareProjectionReplacement();
    _fetchLimits.clear();
    _pinnedNodeIds
      ..clear()
      ..add(_egoNode.id);
    _focusPathIds
      ..clear()
      ..add(_egoNode.id);
    unawaited(_fetch());
  }

  ///
  ///
  Future<void> _fetch({
    bool silent = false,
    bool replace = false,
  }) async {
    final generation = ++_fetchGeneration;
    final replacementBackup = replace ? _captureProjection() : null;
    var replacementApplied = false;

    void prepareReplacement() {
      replacementApplied = true;
      _prepareProjectionReplacement();
    }

    if (!silent) {
      emit(state.copyWith(status: StateStatus.isLoading));
    }
    try {
      final fetchFocus = replace && genealogyMode
          ? ''
          : forwardsGraphBeaconId ?? state.focus;
      final limitKey = fetchFocus;

      Set<EdgeDirected> edges;
      var showNoHelpOffererPathMessage = false;
      String? noPathHelpOffererId;
      var forwardsAuthorId = '';
      if (helpOffererFocusUserId != null && forwardsGraphBeaconId != null) {
        final payload =
            await _case.load(
                  ForwardsGraphLoad(
                    beaconId: forwardsGraphBeaconId!,
                    helpOffererId: helpOffererFocusUserId,
                  ),
                )
                as GraphEdgesResult;
        if (!_isCurrentFetch(generation)) return;
        if (replace) prepareReplacement();
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
      } else if (forwardsGraphBeaconId != null) {
        final payload =
            await _case.load(
                  ForwardsGraphLoad(beaconId: forwardsGraphBeaconId!),
                )
                as GraphEdgesResult;
        if (!_isCurrentFetch(generation)) return;
        if (replace) prepareReplacement();
        edges = payload.edges;
        _helpOffererIds = payload.helpOffererIds;
        forwardsAuthorId = payload.authorId;
      } else if (genealogyMode) {
        List<EdgeDirected> rawEdges;
        if (fetchFocus.isEmpty) {
          final result =
              await _case.load(
                    GenealogyBootstrapGraphLoad(targetId: genealogyTargetId),
                  )
                  as GenealogyBootstrapResult;
          if (!_isCurrentFetch(generation)) return;
          if (replace) prepareReplacement();
          final graph = result.graph;
          if (state.egoNodeId.isEmpty) {
            emit(
              state.copyWith(
                egoNodeId: graph.viewerNodeKey,
                genealogyTargetNodeKey: graph.targetNodeKey ?? '',
              ),
            );
            _resetFocusPathRoot(graph.viewerNodeKey);
          }
          _genealogyParentChainNodeIds.addAll(
            graph.nodes.map((node) => node.nodeKey),
          );
          _preloadGenealogyNodes(graph.nodes);
          await _fetchGenealogyChildCounts(
            graph.nodes.map((node) => node.nodeKey),
          );
          if (!_isCurrentFetch(generation)) return;
          rawEdges = _genealogyEdgesFromGraph(graph);
        } else {
          final cursor = _genealogyChildrenCursors[fetchFocus];
          final result =
              await _case.load(
                    GenealogyChildrenGraphLoad(
                      nodeKey: fetchFocus,
                      afterCreatedAt: cursor?.$1,
                      afterNodeKey: cursor?.$2,
                      limit: kFetchWindowSize,
                    ),
                  )
                  as GenealogyChildrenResult;
          if (!_isCurrentFetch(generation)) return;
          if (replace) prepareReplacement();
          final page = result.page;
          if (page.edges.isNotEmpty) {
            final last = page.edges.last;
            _genealogyChildrenCursors[fetchFocus] = (
              last.descendantUserCreatedAt,
              last.descendantNodeKey,
            );
          }
          _preloadGenealogyNodes(page.nodes);
          await _fetchGenealogyChildCounts(
            {
              fetchFocus,
              for (final edge in page.edges) edge.descendantNodeKey,
            },
          );
          if (!_isCurrentFetch(generation)) return;
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
      } else {
        final result =
            await _case.load(
                  MeritRankGraphLoad(
                    positiveOnly: state.positiveOnly,
                    context: state.context,
                    focus: fetchFocus.isEmpty ? null : fetchFocus,
                    limit: _fetchLimits[limitKey] =
                        (_fetchLimits[limitKey] ?? 0) + kFetchWindowSize,
                    viewerUserId: state.me.id,
                  ),
                )
                as GraphEdgesResult;
        if (!_isCurrentFetch(generation)) return;
        if (replace) prepareReplacement();
        edges = result.edges;
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
          if (!_isCurrentFetch(generation)) return;
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
        if (!_isCurrentFetch(generation)) return;
        if (lazy != null) {
          _nodes[e.src] = lazy;
        }
      }

      // Add FocusNode in case there were no edges containing it
      if (state.focus.isNotEmpty && !_nodes.containsKey(state.focus)) {
        final lazy = await _resolveNodeById(state.focus, pinned: true);
        if (!_isCurrentFetch(generation)) return;
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
        if (!_isCurrentFetch(generation)) return;
        if (lazy != null) {
          _nodes[forwardsAuthorId] = lazy;
        }
      }

      _applyHelpOffererHighlights();

      if (replace) _pruneReplacedProjectionViewState();

      emit(state.copyWith(status: StateStatus.isSuccess));

      _updateGraph(edges);
      unawaited(_replaceWatch());

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
      if (!_isCurrentFetch(generation)) return;
      if (replacementApplied && replacementBackup != null) {
        _restoreProjection(replacementBackup);
      } else {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
      if (!silent) _effects.emit(ShowError(e));
    }
  }

  bool _isCurrentFetch(int generation) =>
      !isClosed && generation == _fetchGeneration;

  void _onProjectionChanged(GraphProjectionChange change) {
    final kind = change.kind;
    final shouldRefresh = switch (kind) {
      null || RealtimeEntityKind.contact => true,
      RealtimeEntityKind.relationship || RealtimeEntityKind.profile =>
        _visibleUserIds().contains(change.aggregateId),
      RealtimeEntityKind.beacon =>
        change.aggregateId == forwardsGraphBeaconId ||
            _nodes.containsKey(change.aggregateId),
      RealtimeEntityKind.forward || RealtimeEntityKind.helpOffer => true,
      _ => false,
    };
    if (shouldRefresh) _scheduleProjectionRefresh();
  }

  void _scheduleProjectionRefresh() {
    if (isClosed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () {
      _refreshTimer = null;
      if (!isClosed) unawaited(_fetch(silent: true, replace: true));
    });
  }

  void _onAccountChanged(String accountId) {
    if (!_accountObserved) {
      _accountObserved = true;
      if (accountId.isEmpty) return;
    }
    if (accountId == state.me.id) return;
    _refreshTimer?.cancel();
    _fetchGeneration++;
    _case.disposeProjection();
    _prepareProjectionReplacement();
    emit(
      state.copyWith(
        focus: '',
        hiddenNeighborCounts: const {},
        status: StateStatus.isSuccess,
      ),
    );
  }

  void _prepareProjectionReplacement() {
    graphController.clear();
    _nodes.clear();
    if (!genealogyMode) _nodes[_egoNode.id] = _egoNode;
    _genealogyChildrenCursors.clear();
    _genealogyParentChainNodeIds.clear();
    _totalNeighborCounts.clear();
    _addedEdgeEndpoints.clear();
    _allEdges.clear();
    _helpOffererIds = const {};
  }

  _GraphProjectionBackup _captureProjection() => _GraphProjectionBackup(
    state: state,
    nodes: Map.of(_nodes),
    renderedNodes: List.of(graphController.nodes),
    renderedEdges: List.of(graphController.edges),
    fetchLimits: Map.of(_fetchLimits),
    genealogyChildrenCursors: Map.of(_genealogyChildrenCursors),
    genealogyParentChainNodeIds: Set.of(_genealogyParentChainNodeIds),
    totalNeighborCounts: Map.of(_totalNeighborCounts),
    addedEdgeEndpoints: Set.of(_addedEdgeEndpoints),
    pinnedNodeIds: Set.of(_pinnedNodeIds),
    focusPathIds: List.of(_focusPathIds),
    allEdges: Map.of(_allEdges),
    helpOffererIds: Set.of(_helpOffererIds),
  );

  void _restoreProjection(_GraphProjectionBackup backup) {
    _nodes
      ..clear()
      ..addAll(backup.nodes);
    _fetchLimits
      ..clear()
      ..addAll(backup.fetchLimits);
    _genealogyChildrenCursors
      ..clear()
      ..addAll(backup.genealogyChildrenCursors);
    _genealogyParentChainNodeIds
      ..clear()
      ..addAll(backup.genealogyParentChainNodeIds);
    _totalNeighborCounts
      ..clear()
      ..addAll(backup.totalNeighborCounts);
    _addedEdgeEndpoints
      ..clear()
      ..addAll(backup.addedEdgeEndpoints);
    _pinnedNodeIds
      ..clear()
      ..addAll(backup.pinnedNodeIds);
    _focusPathIds
      ..clear()
      ..addAll(backup.focusPathIds);
    _allEdges
      ..clear()
      ..addAll(backup.allEdges);
    _helpOffererIds = Set.of(backup.helpOffererIds);

    graphController
      ..clear()
      ..mutate((mutator) {
        backup.renderedNodes.forEach(mutator.addNode);
        backup.renderedEdges.forEach(mutator.addEdge);
      });
    emit(backup.state.copyWith(status: const StateIsSuccess()));
  }

  void _pruneReplacedProjectionViewState() {
    _pinnedNodeIds.removeWhere((id) => !_nodes.containsKey(id));
    if (!genealogyMode) _pinnedNodeIds.add(_egoNode.id);
    _focusPathIds.removeWhere((id) => !_nodes.containsKey(id));
    if (state.focus.isEmpty || _nodes.containsKey(state.focus)) return;
    final fallback = genealogyMode ? state.egoNodeId : _egoNode.id;
    emit(state.copyWith(focus: _nodes.containsKey(fallback) ? fallback : ''));
    _resetFocusPathRoot(fallback);
  }

  Future<void> _replaceWatch() => _case.replaceWatch(
    GraphWatchProjection(
      focusId: _watchFocusId,
      context: state.context,
      positiveOnly: state.positiveOnly,
      userIds: _visibleUserIds(),
    ),
  );

  String get _watchFocusId {
    final forwardsId = forwardsGraphBeaconId;
    if (forwardsId != null && forwardsId.isNotEmpty) return forwardsId;
    final genealogyTarget = genealogyTargetId;
    if (genealogyTarget != null && genealogyTarget.isNotEmpty) {
      return genealogyTarget;
    }
    final focus = state.focus;
    return focus.startsWith('U') || focus.startsWith('B') ? focus : state.me.id;
  }

  Set<String> _visibleUserIds() => {
    for (final node in _nodes.values)
      switch (node) {
        UserNode(:final user) => user.id,
        GenealogyUserNode(:final user) => user.id,
        _ => '',
      },
  }..removeWhere((id) => id.isEmpty);

  Future<NodeDetails?> _resolveNodeById(
    String id, {
    bool pinned = false,
  }) async {
    return _case.resolveNodeById(
      id,
      positionHint: _nodes.length,
      pinned: pinned,
      helpOffererIds: _helpOffererIds,
    );
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
    Iterable<String> nodeKeys,
  ) async {
    final keys = nodeKeys.where((key) => key.isNotEmpty).toSet();
    if (keys.isEmpty) {
      return;
    }
    final counts = await _case.fetchGenealogyChildCounts(keys);
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

  /// Focus-path spotlight: reconciles
  /// [graphController] against the user's current tap trail plus all edges
  /// incident to the current focus (the fresh neighbors a tap just revealed).
  /// Pure filter over [_allEdges] — hidden data stays cached, so backtracking
  /// re-reveals without a refetch.
  void _recomputeVisibility() {
    final focusId = state.focus;
    final rootId = _focusRootId;
    final alwaysVisibleNodeIds = _alwaysVisibleNodeIds;
    final visibleEdges = <(String, String), EdgeDirected>{};
    if (focusId.isEmpty) {
      visibleEdges.addAll(_allEdges);
    } else {
      for (var i = 0; i < _focusPathIds.length - 1; i++) {
        final a = _focusPathIds[i];
        final b = _focusPathIds[i + 1];
        final forward = (a, b);
        final backward = (b, a);
        final forwardEdge = _allEdges[forward];
        if (forwardEdge != null) {
          visibleEdges[forward] = forwardEdge;
        }
        final backwardEdge = _allEdges[backward];
        if (backwardEdge != null) {
          visibleEdges[backward] = backwardEdge;
        }
      }
      for (final entry in _allEdges.entries) {
        if (entry.key.$1 == focusId || entry.key.$2 == focusId) {
          visibleEdges[entry.key] = entry.value;
        }
      }
      for (final entry in _allEdges.entries) {
        if (alwaysVisibleNodeIds.contains(entry.key.$1) &&
            alwaysVisibleNodeIds.contains(entry.key.$2)) {
          visibleEdges[entry.key] = entry.value;
        }
      }
    }
    final visibleNodeIds = <String>{
      if (rootId.isNotEmpty) rootId,
      ...alwaysVisibleNodeIds,
      ..._focusPathIds,
      if (focusId.isNotEmpty) focusId,
      for (final key in visibleEdges.keys) ...[key.$1, key.$2],
    };

    graphController.mutate((mutator) {
      for (final node in List.of(graphController.nodes)) {
        if (node.id != rootId && !visibleNodeIds.contains(node.id)) {
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

final class _GraphProjectionBackup {
  const _GraphProjectionBackup({
    required this.state,
    required this.nodes,
    required this.renderedNodes,
    required this.renderedEdges,
    required this.fetchLimits,
    required this.genealogyChildrenCursors,
    required this.genealogyParentChainNodeIds,
    required this.totalNeighborCounts,
    required this.addedEdgeEndpoints,
    required this.pinnedNodeIds,
    required this.focusPathIds,
    required this.allEdges,
    required this.helpOffererIds,
  });

  final GraphState state;
  final Map<String, NodeDetails> nodes;
  final List<NodeDetails> renderedNodes;
  final List<EdgeDetails<NodeDetails>> renderedEdges;
  final Map<String, int> fetchLimits;
  final Map<String, (DateTime, String)> genealogyChildrenCursors;
  final Set<String> genealogyParentChainNodeIds;
  final Map<String, int> totalNeighborCounts;
  final Set<(String, String)> addedEdgeEndpoints;
  final Set<String> pinnedNodeIds;
  final List<String> focusPathIds;
  final Map<(String, String), EdgeDirected> allEdges;
  final Set<String> helpOffererIds;
}
