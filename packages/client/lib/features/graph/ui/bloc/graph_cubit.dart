// graphController should be here
// ignore_for_file: avoid_public_fields, prefer_void_public_cubit_methods

import 'dart:async';
import 'package:get_it/get_it.dart';
// TBD: return int instead of Colors?
// ignore: avoid_flutter_imports
import 'package:flutter/material.dart' show Colors;
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/message/common_messages.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../data/repository/forwards_graph_repository.dart';
import '../../data/repository/graph_repository.dart';
import '../../data/repository/graph_source_repository.dart';
import '../../domain/entity/edge_details.dart';
import '../../domain/entity/edge_directed.dart';
import '../../domain/entity/node_details.dart';
import 'graph_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'graph_state.dart';

/// Viewer's relationship to the focused chain in committer-path mode.
enum ForwardsGraphViewerRole {
  /// Viewer is the beacon author (root of the chain).
  author,

  /// Viewer is the focused committer themselves; the focus is rotated onto
  /// the author so the chain reads "in reverse" from the viewer's PoV.
  self,

  /// Viewer is neither the author nor the committer but has at least one
  /// forward edge for the beacon; their own sub-chain is overlaid on top
  /// of the committer's chain so they see how they fit between the two.
  involvedOther,
}

class GraphCubit extends Cubit<GraphState> {
  // TODO(contract): Phase-2 DTO migration — route multi-repo orchestration through a *Case.
  // ignore: cubit_requires_use_case_for_multi_repos
  GraphCubit({
    required Profile me,
    String? focus,
    GraphSourceRepository? graphSourceRepository,
    /// When set, [GraphCubit] always loads forwards for this beacon id and
    /// does not refetch on node focus changes (forwards graph is static).
    this.forwardsGraphBeaconId,

    /// When set together with [forwardsGraphBeaconId], the cubit fetches the
    /// per-committer forward path (V2 `beaconCommitterForwardPath`) instead
    /// of the broader `beaconForwardGraph`. Focus auto-rotates onto the
    /// committer (or the author when the viewer IS the committer — case 3).
    this.committerFocusUserId,
    BeaconRepository? beaconRepository,
    ProfileRepositoryPort? profileRepository,
  }) : _egoNode = UserNode(
         user: me.copyWith(title: 'Me', score: 2),
         pinned: true,
         size: 80,
         positionHint: 0,
       ),
       _graphSource = graphSourceRepository ?? GetIt.I<GraphRepository>(),
       _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _profileRepository = profileRepository ?? GetIt.I<ProfileRepositoryPort>(),
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

  final String? committerFocusUserId;

  final BeaconRepository _beaconRepository;

  final ProfileRepositoryPort _profileRepository;

  /// Resolved viewer role for the committer-path view; null when the cubit
  /// is operating in any other mode (regular forwards graph or MeritRank).
  /// Set during [_fetch] once `authorId`/`viewerId` are known.
  ForwardsGraphViewerRole? _committerViewerRole;

  ForwardsGraphViewerRole? get committerViewerRole => _committerViewerRole;

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

  /// Active committers for [forwardsGraphBeaconId] (forwards graph only).
  /// Highlighted via [UserNode.isCommitter] in the renderer.
  Set<String> _committerIds = const <String>{};

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
      var showNoCommitterPathMessage = false;
      String? noPathCommitterId;
      if (committerFocusUserId != null &&
          forwardsGraphBeaconId != null &&
          source is ForwardsGraphRepository) {
        final payload = await source.fetchCommitterForwardsGraph(
          beaconId: forwardsGraphBeaconId!,
          committerId: committerFocusUserId!,
        );
        edges = payload.edges;
        _committerIds = payload.committerIds;

        // Focus rule for the three viewer-role cases (see plan):
        //   case 1 (author):         focus = committer
        //   case 2 (involved-other): focus = committer
        //   case 3 (committer-self): focus = author (chain reads "in reverse")
        // Ego node is always `me` (existing pattern); the role rotates onto
        // whichever principal happens to be the viewer.
        final viewerId = payload.viewerId ?? state.me.id;
        final authorId = payload.authorId;
        final committerId = committerFocusUserId!;
        final isAuthor = viewerId == authorId;
        final isSelf = viewerId == committerId;
        _committerViewerRole = isAuthor
            ? ForwardsGraphViewerRole.author
            : isSelf
                ? ForwardsGraphViewerRole.self
                : ForwardsGraphViewerRole.involvedOther;
        final hasCommitterEndpoint = edges.any(
          (e) => e.src == committerId || e.dst == committerId,
        );
        final derivedFocus =
            isSelf ? authorId : committerId;
        if (state.focus != derivedFocus) {
          emit(state.copyWith(focus: derivedFocus));
        }
        showNoCommitterPathMessage = !hasCommitterEndpoint;
        noPathCommitterId = !hasCommitterEndpoint ? committerId : null;
      } else if (forwardsGraphBeaconId != null &&
          source is ForwardsGraphRepository) {
        final payload =
            await source.fetchForwardsGraph(beaconId: forwardsGraphBeaconId!);
        edges = payload.edges;
        _committerIds = payload.committerIds;
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
          // When the focused committer has no path edges, we still want to show
          // them as an isolated focus node. Give it a stable hint north of root.
          if (noPathCommitterId != null &&
              state.focus == noPathCommitterId &&
              lazy.positionHint != 0) {
            _nodes[state.focus] =
                lazy.copyWithPositionHint(_isolatedFocusNorthHint);
          } else {
            _nodes[state.focus] = lazy;
          }
        }
      }

      _applyCommitterHighlights();

      emit(state.copyWith(status: StateStatus.isSuccess));

      _updateGraph(edges);

      if (showNoCommitterPathMessage) {
        emit(
          state.copyWith(
            status: StateIsMessaging(const NoCommitterForwardPathMessage()),
          ),
        );
        emit(state.copyWith(status: StateStatus.isSuccess));
      }

      // Recenter on the derived focus node in committer-path mode so the
      // viewer immediately lands on the relevant principal (committer for
      // case 1/2, author for case 3) instead of the floating ego "Me".
      if (committerFocusUserId != null && state.focus.isNotEmpty) {
        final focusNode = _nodes[state.focus];
        if (focusNode != null) {
          // `jumpToNode` expects the *same instance* that the graph controller
          // currently tracks positions for. When `NodeDetails` instances get
          // replaced in `_nodes` (pinned/committer highlight), passing a stale
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
      emit(state.copyWith(status: StateHasError(e)));
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
        isCommitter: _committerIds.contains(id),
      );
    }
    if (id.startsWith('B')) {
      return BeaconNode(
        beacon: await _beaconRepository.fetchBeaconById(id),
        positionHint: _nodes.length,
        pinned: pinned,
      );
    }
    return null;
  }

  /// Stamps `isCommitter` on every committer's [UserNode] currently in
  /// [_nodes]. Called after each fetch so late-arriving nodes pick up the flag.
  void _applyCommitterHighlights() {
    if (_committerIds.isEmpty) return;
    for (final id in _committerIds) {
      final node = _nodes[id];
      if (node is UserNode && !node.isCommitter) {
        _nodes[id] = node.copyWithIsCommitter(true);
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
            ? Colors.redAccent
            : src == _egoNode || dst == _egoNode
            ? Colors.amberAccent
            : Colors.cyanAccent,
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
