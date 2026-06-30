import 'dart:async';
import 'dart:ui' show Color;

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
    String? targetId,
    UiEffectPort? effects,
  }) : _repository = repository,
       _edgeColors = edgeColors,
       _anonymousNodeLabel = anonymousNodeLabel,
       _targetId = targetId,
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(const InviteGenealogyGraphState()) {
    unawaited(_fetch());
  }

  final InviteGenealogyRepository _repository;
  final GraphEdgeColors _edgeColors;
  final String _anonymousNodeLabel;
  final String? _targetId;
  final UiEffectPort _effects;

  bool get _isBetween => _targetId != null;

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
      final graph = _isBetween
          ? await _repository.fetchBetween(_targetId!)
          : await _repository.fetch();
      _nodes
        ..clear()
        ..addAll(_buildNodes(graph));
      emit(
        state.copyWith(
          viewerNodeKey: graph.viewerNodeKey,
          targetNodeKey: graph.targetNodeKey ?? '',
          commonAncestorNodeKey: graph.commonAncestorNodeKey ?? '',
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
      final isEndpoint = node.nodeKey == graph.viewerNodeKey ||
          node.nodeKey == graph.targetNodeKey;
      if (node.profile != null && node.deletedAt == null) {
        nodes[node.nodeKey] = GenealogyUserNode(
          nodeKey: node.nodeKey,
          user: node.profile!,
          pinned: isEndpoint,
          size: isEndpoint ? 72 : 48,
          positionHint: i,
        );
      } else {
        nodes[node.nodeKey] = GenealogyDeletedNode(
          nodeKey: node.nodeKey,
          label: _anonymousNodeLabel,
          pinned: isEndpoint,
          size: isEndpoint ? 72 : 48,
          positionHint: i,
        );
      }
    }
    return nodes;
  }

  void _updateGraph(InviteGenealogyGraph graph) {
    // In pairwise mode, color the two branches that meet at the closest common
    // ancestor (LCA): viewer→LCA in [ego], target→LCA in [target], the shared
    // trunk above the LCA (and any other edge) in [neutral].
    final viewerBranch =
        _isBetween ? _branchBelowLca(graph, graph.viewerNodeKey) : const <String>{};
    final targetBranch = _isBetween && graph.targetNodeKey != null
        ? _branchBelowLca(graph, graph.targetNodeKey!)
        : const <String>{};

    graphController.mutate((mutator) {
      for (final edge in graph.edges) {
        final src = _nodes[edge.ancestorNodeKey];
        final dst = _nodes[edge.descendantNodeKey];
        if (src == null || dst == null) {
          continue;
        }

        final Color color;
        final double strokeWidth;
        if (_isBetween) {
          if (viewerBranch.contains(edge.descendantNodeKey)) {
            color = _edgeColors.ego;
            strokeWidth = 3;
          } else if (targetBranch.contains(edge.descendantNodeKey)) {
            color = _edgeColors.target;
            strokeWidth = 3;
          } else {
            color = _edgeColors.neutral;
            strokeWidth = 2;
          }
        } else {
          final touchesViewer = src.id == state.viewerNodeKey ||
              dst.id == state.viewerNodeKey;
          color = touchesViewer ? _edgeColors.ego : _edgeColors.neutral;
          strokeWidth = touchesViewer ? 3 : 2;
        }

        final graphEdge = EdgeDetails<NodeDetails>(
          source: src,
          destination: dst,
          strokeWidth: strokeWidth,
          color: color,
        );
        mutator.addNode(src);
        mutator.addNode(dst);
        mutator.addEdge(graphEdge);
      }
    });
  }

  /// Node keys on the upward chain from [start] up to — but excluding — the
  /// closest common ancestor. With no LCA (disconnected users) this walks the
  /// whole chain to the root.
  Set<String> _branchBelowLca(InviteGenealogyGraph graph, String start) {
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
}
