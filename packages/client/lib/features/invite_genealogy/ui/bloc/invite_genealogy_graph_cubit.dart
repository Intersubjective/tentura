import 'dart:async';

import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/invite_genealogy/data/repository/invite_genealogy_repository.dart';
import 'package:tentura/features/invite_genealogy/domain/entity/invite_genealogy_graph.dart';

import 'invite_genealogy_graph_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'invite_genealogy_graph_state.dart';

class InviteGenealogyGraphCubit extends Cubit<InviteGenealogyGraphState> {
  InviteGenealogyGraphCubit({
    required InviteGenealogyRepository repository,
    required GraphEdgeColors edgeColors,
    required String anonymousNodeLabel,
    UiEffectPort? effects,
  }) : _repository = repository,
       _edgeColors = edgeColors,
       _anonymousNodeLabel = anonymousNodeLabel,
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(const InviteGenealogyGraphState()) {
    unawaited(_fetch());
  }

  final InviteGenealogyRepository _repository;
  final GraphEdgeColors _edgeColors;
  final String _anonymousNodeLabel;
  final UiEffectPort _effects;

  final graphController =
      GraphController<NodeDetails, EdgeDetails<NodeDetails>>();

  final Map<String, NodeDetails> _nodes = {};

  @override
  Future<void> close() {
    graphController.dispose();
    return super.close();
  }

  void jumpToViewer() {
    final viewer = _nodes[state.viewerNodeKey];
    if (viewer != null) {
      graphController.jumpToNode(viewer);
    }
  }

  Future<void> _fetch() async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      final graph = await _repository.fetch();
      _nodes
        ..clear()
        ..addAll(_buildNodes(graph));
      emit(
        state.copyWith(
          viewerNodeKey: graph.viewerNodeKey,
          nodeKeys: graph.nodes.map((n) => n.nodeKey).toList(),
          status: const StateIsSuccess(),
        ),
      );
      _updateGraph(graph);
      jumpToViewer();
    } catch (e) {
      _effects.emit(ShowError(e));
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  Map<String, NodeDetails> _buildNodes(InviteGenealogyGraph graph) {
    final sorted = [...graph.nodes]
      ..sort((a, b) {
        final aCreated =
            a.userCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bCreated =
            b.userCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aCreated.compareTo(bCreated);
      });
    final nodes = <String, NodeDetails>{};
    for (var i = 0; i < sorted.length; i++) {
      final node = sorted[i];
      final isViewer = node.nodeKey == graph.viewerNodeKey;
      if (node.profile != null && node.deletedAt == null) {
        nodes[node.nodeKey] = GenealogyUserNode(
          nodeKey: node.nodeKey,
          user: node.profile!,
          pinned: isViewer,
          size: isViewer ? 72 : 48,
          positionHint: i,
        );
      } else {
        nodes[node.nodeKey] = GenealogyDeletedNode(
          nodeKey: node.nodeKey,
          label: _anonymousNodeLabel,
          pinned: isViewer,
          size: isViewer ? 72 : 48,
          positionHint: i,
        );
      }
    }
    return nodes;
  }

  void _updateGraph(InviteGenealogyGraph graph) {
    graphController.mutate((mutator) {
      for (final edge in graph.edges) {
        final src = _nodes[edge.ancestorNodeKey];
        final dst = _nodes[edge.descendantNodeKey];
        if (src == null || dst == null) {
          continue;
        }
        final graphEdge = EdgeDetails<NodeDetails>(
          source: src,
          destination: dst,
          strokeWidth: src.id == state.viewerNodeKey || dst.id == state.viewerNodeKey
              ? 3
              : 2,
          color: src.id == state.viewerNodeKey || dst.id == state.viewerNodeKey
              ? _edgeColors.ego
              : _edgeColors.neutral,
        );
        mutator.addNode(src);
        mutator.addNode(dst);
        mutator.addEdge(graphEdge);
      }
    });
  }
}
