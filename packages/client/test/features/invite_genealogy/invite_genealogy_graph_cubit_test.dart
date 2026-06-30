import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/invite_genealogy/data/repository/invite_genealogy_repository.dart';
import 'package:tentura/features/invite_genealogy/domain/entity/invite_genealogy_graph.dart';
import 'package:tentura/features/invite_genealogy/ui/bloc/invite_genealogy_graph_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeInviteGenealogyRepository implements InviteGenealogyRepository {
  InviteGenealogyGraph graph = const InviteGenealogyGraph(
    viewerNodeKey: '',
    nodes: [],
    edges: [],
  );
  InviteGenealogyGraph? betweenGraph;
  String? lastTargetId;

  @override
  Future<InviteGenealogyGraph> fetch() async => graph;

  @override
  Future<InviteGenealogyGraph> fetchBetween(String targetId) async {
    lastTargetId = targetId;
    return betweenGraph ?? graph;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _edgeColors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

const _viewer = Profile(id: 'Uviewer', displayName: 'Viewer');
const _target = Profile(id: 'Utarget', displayName: 'Target');

Future<void> _settleCubitFetch() => pumpEventQueue();

void main() {
  test(
    'self lineage renders the viewer even when there are no edges',
    () async {
      final repo = _FakeInviteGenealogyRepository()
        ..graph = InviteGenealogyGraph(
          viewerNodeKey: 'Nviewer',
          nodes: [
            InviteGenealogyNode(
              nodeKey: 'Nviewer',
              profile: _viewer,
              userCreatedAt: DateTime.utc(2026),
            ),
          ],
          edges: [],
        );
      final cubit = InviteGenealogyGraphCubit(
        repository: repo,
        edgeColors: _edgeColors,
        anonymousNodeLabel: 'Anonymous',
        effects: FakeUiEffectPort(),
      );

      await _settleCubitFetch();

      expect(cubit.graphController.edges, isEmpty);
      expect(cubit.graphController.nodes, hasLength(1));
      expect(cubit.graphController.nodes.single, isA<GenealogyUserNode>());
      expect(cubit.graphController.nodes.single.id, 'Nviewer');

      await cubit.close();
    },
  );

  test(
    'pairwise lineage renders disconnected viewer and target endpoints',
    () async {
      final repo = _FakeInviteGenealogyRepository()
        ..betweenGraph = InviteGenealogyGraph(
          viewerNodeKey: 'Nviewer',
          targetNodeKey: 'Ntarget',
          nodes: [
            InviteGenealogyNode(
              nodeKey: 'Nviewer',
              profile: _viewer,
              userCreatedAt: DateTime.utc(2026),
            ),
            InviteGenealogyNode(
              nodeKey: 'Ntarget',
              profile: _target,
              userCreatedAt: DateTime.utc(2026, 2),
            ),
          ],
          edges: [],
        );
      final cubit = InviteGenealogyGraphCubit(
        repository: repo,
        edgeColors: _edgeColors,
        anonymousNodeLabel: 'Anonymous',
        targetId: _target.id,
        effects: FakeUiEffectPort(),
      );

      await _settleCubitFetch();

      expect(repo.lastTargetId, _target.id);
      expect(cubit.graphController.edges, isEmpty);
      expect(
        cubit.graphController.nodes.map((node) => node.id).toSet(),
        {'Nviewer', 'Ntarget'},
      );
      expect(cubit.state.targetNodeKey, 'Ntarget');

      await cubit.close();
    },
  );
}
