import 'dart:async';
import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../data/repository/graph_repository.dart';
import '../../domain/entity/edge_details.dart';
import '../../domain/entity/edge_directed.dart';
import '../../domain/entity/node_details.dart';
import 'graph_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'graph_state.dart';

class GraphCubit extends Cubit<GraphState> {
  GraphCubit(
    this.graphRepository, {
    required Profile me,
    String? focus,
  })  : _egoNode = UserNode(
          user: me.copyWith(
            title: 'Me',
            score: 2,
          ),
          pinned: true,
          size: 80,
        ),
        super(GraphState(focus: focus ?? '')) {
    _fetch();
  }

  final GraphRepository graphRepository;

  final graphController =
      GraphController<NodeDetails, EdgeDetails<NodeDetails>>();

  final UserNode _egoNode;

  final _fetchLimits = <String, int>{};

  late final _nodes = <String, NodeDetails>{_egoNode.id: _egoNode};

  @override
  Future<void> close() {
    graphController.dispose();
    return super.close();
  }

  void showNodeDetails(NodeDetails node) => switch (node) {
        final UserNode node => emit(state.copyWith(
            status: StateIsNavigating('$kPathProfileView?id=${node.id}'),
          )),
        final BeaconNode node => emit(state.copyWith(
            status: StateIsNavigating('$kPathBeaconView?id=${node.id}'),
          )),
      };

  void jumpToEgo() => graphController.jumpToNode(_egoNode);

  void setFocus(NodeDetails node) {
    if (state.focus != node.id) {
      emit(state.copyWith(focus: node.id));
      graphController
        ..setPinned(node, true)
        ..jumpToNode(node);
    }
    _fetch();
  }

  Future<void> setContext(String? context) {
    emit(state.copyWith(
      context: context ?? '',
      focus: '',
    ));
    graphController.clear();
    _fetchLimits.clear();
    return _fetch();
  }

  void togglePositiveOnly() {
    emit(state.copyWith(
      positiveOnly: !state.positiveOnly,
      focus: '',
    ));
    graphController.clear();
    _fetchLimits.clear();
    _fetch();
  }

  Future<void> _fetch() async {
    emit(state.copyWith(
      status: StateStatus.isLoading,
    ));
    try {
      final edges = await graphRepository.fetch(
        positiveOnly: state.positiveOnly,
        context: state.context,
        focus: state.focus,
        limit: _fetchLimits[state.focus] = (_fetchLimits[state.focus] ?? 0) + 5,
      );
      emit(state.copyWith(
        status: StateStatus.isSuccess,
      ));
      if (edges.isEmpty) return;

      for (final e in edges) {
        _nodes.putIfAbsent(e.dst, () => e.node);
      }
      _updateGraph(edges);
    } catch (e) {
      emit(state.copyWith(
        status: StateHasError(e),
      ));
    }
  }

  void _updateGraph(Set<EdgeDirected> edges) =>
      graphController.mutate((mutator) {
        for (final e in edges) {
          if (state.positiveOnly && e.weight < 0) continue;
          final src = _nodes[e.src];
          if (src == null) continue;
          final dst = _nodes[e.dst];
          if (dst == null) continue;
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
          if (!mutator.controller.nodes.contains(src)) mutator.addNode(src);
          if (!mutator.controller.nodes.contains(dst)) mutator.addNode(dst);
          if (!mutator.controller.edges.contains(edge)) mutator.addEdge(edge);
        }
      });
}
