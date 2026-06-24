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
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../data/repository/forwards_graph_repository.dart';
import '../../data/repository/graph_repository.dart';
import '../../data/repository/graph_source_repository.dart';
import '../../domain/entity/edge_details.dart';
import '../../domain/entity/graph_edge_colors.dart';
import '../../domain/entity/edge_directed.dart';
import '../../domain/prune_directed_paths.dart';
import '../../domain/entity/node_details.dart';
import 'graph_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'graph_state.dart';

/// Viewer's relationship to the focused chain in help-offerer-path mode.
enum ForwardsGraphViewerRole {
  /// Viewer is the beacon author (root of the chain).
  author,

  /// Viewer is the focused help offerer themselves; the focus is rotated onto
  /// the author so the chain reads "in reverse" from the viewer's PoV.
  self,

  /// Viewer is neither the author nor the help offerer but has at least one
  /// forward edge for the beacon; their own sub-chain is overlaid on top
  /// of the help offerer's chain so they see how they fit between the two.
  involvedOther,
}

class GraphCubit extends Cubit<GraphState> {
  // TODO(contract): Phase-2 DTO migration — route multi-repo orchestration through a *Case.
  // ignore: tentura_lints/cubit_requires_use_case_for_multi_repos
  GraphCubit({
    required Profile me,
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
    BeaconRepository? beaconRepository,
    ProfileRepositoryPort? profileRepository,
    UiEffectPort? effects,
    required GraphEdgeColors edgeColors,
  }) : _edgeColors = edgeColors,
       _egoNode = UserNode(
         user: me.copyWith(displayName: 'Me', score: 2),
         pinned: true,
         size: 80,
         positionHint: 0,
       ),
       _graphSource = graphSourceRepository ?? GetIt.I<GraphRepository>(),
       _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _profileRepository = profileRepository ?? GetIt.I<ProfileRepositoryPort>(),
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

  // Heuristic for isolated focus placement: initialPositionExtractor uses
  // y = 200 - 100*positionHint (given current constants). So hints >= 3 start
  // "north" (negative y offset) of center.
  static const int _isolatedFocusNorthHint = 4;

  late final Map<String, NodeDetails> _nodes = <String, NodeDetails>{
    _egoNode.id: _egoNode,
  };

  /// Active help offerers for [forwardsGraphBeaconId] (forwards graph only).
  /// Highlighted via [UserNode.isHelpOfferer] in the renderer.
  Set<String> _helpOffererIds = const <String>{};

  @override
  Future<void> close() {
    graphController.dispose();
    return super.close();
  }

  ///
  ///
  void jumpToEgo() => graphController.jumpToNode(_egoNode);

  ///
  ///
  void setFocus(NodeDetails node) {
    if (state.focus != node.id) {
      emit(state.copyWith(focus: node.id));
      graphController
        ..setPinned(node, true)
        // ignore: discarded_futures //
        ..jumpToNode(node);
    }
    if (forwardsGraphBeaconId == null) {
      unawaited(_fetch());
    }
  }

  ///
  ///
  Future<void> setContext(String? context) {
    if (forwardsGraphBeaconId != null) {
      return Future.value();
    }
    emit(state.copyWith(context: context ?? '', focus: ''));
    graphController.clear();
    _fetchLimits.clear();
    return _fetch();
  }

  ///
  ///
  void togglePositiveOnly() {
    if (forwardsGraphBeaconId != null) {
      return;
    }
    emit(state.copyWith(positiveOnly: !state.positiveOnly, focus: ''));
    graphController.clear();
    _fetchLimits.clear();
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
        final isAuthor = viewerId == authorId;
        final isSelf = viewerId == helpOffererId;
        final viewerRole = isAuthor
            ? ForwardsGraphViewerRole.author
            : isSelf
                ? ForwardsGraphViewerRole.self
                : ForwardsGraphViewerRole.involvedOther;
        if (state.helpOffererViewerRole != viewerRole) {
          emit(state.copyWith(helpOffererViewerRole: viewerRole));
        }
        final hasHelpOffererEndpoint = edges.any(
          (e) => e.src == helpOffererId || e.dst == helpOffererId,
        );
        final derivedFocus =
            isSelf ? authorId : helpOffererId;
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
        final payload =
            await source.fetchForwardsGraph(beaconId: forwardsGraphBeaconId!);
        edges = payload.edges;
        _helpOffererIds = payload.helpOffererIds;
        forwardsAuthorId = payload.authorId;
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
              state.focus == noPathHelpOffererId &&
              lazy.positionHint != 0) {
            _nodes[state.focus] =
                lazy.copyWithPositionHint(_isolatedFocusNorthHint);
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

  ///
  ///
  void _updateGraph(Set<EdgeDirected> edges) => graphController.mutate((
    mutator,
  ) {
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
      final edge = EdgeDetails<NodeDetails>(
        source: src,
        destination: dst,
        strokeWidth: (src == _egoNode || dst == _egoNode) ? 3 : 2,
        color: e.weight < 0
            ? _edgeColors.negative
            : src == _egoNode || dst == _egoNode
            ? _edgeColors.ego
            : _edgeColors.neutral,
      );
      if (!mutator.controller.nodes.contains(src)) {
        mutator.addNode(src);
      }
      if (!mutator.controller.nodes.contains(dst)) {
        mutator.addNode(dst);
      }
      if (src.id != dst.id && !mutator.controller.edges.contains(edge)) {
        mutator.addEdge(edge);
      }
    }

    if (!mutator.controller.nodes.contains(_egoNode)) {
      mutator.addNode(_egoNode);
    }
    final focusNode = _nodes[state.focus];
    if (focusNode != null && !mutator.controller.nodes.contains(focusNode)) {
      mutator.addNode(focusNode);
    }
  });
}
