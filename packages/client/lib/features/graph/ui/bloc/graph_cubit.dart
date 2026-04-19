// graphController should be here
// ignore_for_file: avoid_public_fields

import 'dart:async';
import 'package:get_it/get_it.dart';
// TBD: return int instead of Colors?
// ignore: avoid_flutter_imports
import 'package:flutter/material.dart' show Colors;
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

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

  final BeaconRepository _beaconRepository;

  final ProfileRepositoryPort _profileRepository;

  final graphController =
      GraphController<NodeDetails, EdgeDetails<NodeDetails>>();

  final UserNode _egoNode;

  final _fetchLimits = <String, int>{};

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
      if (forwardsGraphBeaconId != null && source is ForwardsGraphRepository) {
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
          _nodes[state.focus] = lazy;
        }
      }

      _applyCommitterHighlights();

      emit(state.copyWith(status: StateStatus.isSuccess));

      _updateGraph(edges);
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<NodeDetails?> _resolveNodeById(
    String id, {
    bool pinned = false,
  }) async {
    if (id.startsWith('U')) {
      return UserNode(
        user: await _profileRepository.fetchById(id),
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
