import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/invite_genealogy/data/repository/invite_genealogy_repository.dart';
import 'package:tentura/features/invite_genealogy/domain/entity/invite_genealogy_graph.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeInviteGenealogyRepository implements InviteGenealogyRepository {
  InviteGenealogyGraph bootstrapGraph = const InviteGenealogyGraph(
    viewerNodeKey: '',
    nodes: [],
    edges: [],
  );
  final childCounts = <String, int>{};
  final childCountCalls = <Set<String>>[];
  final childrenPages = <InviteGenealogyChildrenPage>[];
  final childrenCalls =
      <
        ({
          String nodeKey,
          DateTime? afterCreatedAt,
          String? afterNodeKey,
          int limit,
        })
      >[];
  String? lastBootstrapTargetId;

  @override
  Future<InviteGenealogyGraph> fetchGenealogyBootstrap({
    String? targetId,
  }) async {
    lastBootstrapTargetId = targetId;
    return bootstrapGraph;
  }

  @override
  Future<InviteGenealogyChildrenPage> fetchChildren({
    required String nodeKey,
    required int limit,
    DateTime? afterCreatedAt,
    String? afterNodeKey,
  }) async {
    childrenCalls.add(
      (
        nodeKey: nodeKey,
        afterCreatedAt: afterCreatedAt,
        afterNodeKey: afterNodeKey,
        limit: limit,
      ),
    );
    if (childrenPages.isEmpty) {
      return const (
        nodes: <InviteGenealogyNode>[],
        edges: <InviteGenealogyEdge>[],
      );
    }
    return childrenPages.removeAt(0);
  }

  @override
  Future<Map<String, int>> fetchChildCounts({
    required List<String> nodeKeys,
  }) async {
    childCountCalls.add(nodeKeys.toSet());
    return {
      for (final key in nodeKeys)
        if (childCounts.containsKey(key)) key: childCounts[key]!,
    };
  }

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
  }) => throw UnsupportedError(
    'generic fetch must not be used in genealogy mode',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeGraphSourceRepository implements GraphSourceRepository {
  int calls = 0;
  Set<EdgeDirected> Function()? fetchResult;

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
  }) async {
    calls += 1;
    return fetchResult?.call() ??
        {
          (
            src: _viewer.id,
            dst: _friend.id,
            weight: 1,
            node: const UserNode(user: _friend),
            branch: null,
            srcTotalNeighborCount: null,
            dstTotalNeighborCount: null,
          ),
        };
  }
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeBeaconRepository implements BeaconRepository {
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
const _friend = Profile(id: 'Ufriend', displayName: 'Friend');

Future<void> _settleCubitFetch() => pumpEventQueue(times: 5);

InviteGenealogyNode _node(
  String nodeKey,
  Profile profile,
  DateTime createdAt,
) => InviteGenealogyNode(
  nodeKey: nodeKey,
  profile: profile,
  userCreatedAt: createdAt,
);

InviteGenealogyEdge _edge(
  String ancestor,
  String descendant,
  DateTime ancestorAt,
  DateTime descendantAt,
) => InviteGenealogyEdge(
  ancestorNodeKey: ancestor,
  descendantNodeKey: descendant,
  ancestorUserCreatedAt: ancestorAt,
  descendantUserCreatedAt: descendantAt,
  createdAt: descendantAt,
);

GraphCubit _cubit({
  required _FakeInviteGenealogyRepository repo,
  String? targetId,
}) => GraphCubit(
  me: _viewer,
  graphSourceRepository: repo,
  genealogyMode: true,
  genealogyTargetId: targetId,
  genealogyAnonymousNodeLabel: 'Anonymous',
  edgeColors: _edgeColors,
  beaconRepository: _FakeBeaconRepository(),
  profileRepository: _FakeProfileRepository(),
  effects: FakeUiEffectPort(),
);

EdgeDetails<NodeDetails> _edgeDetails(
  GraphCubit cubit,
  String src,
  String dst,
) => cubit.graphController.edges.singleWhere(
  (edge) => edge.source.id == src && edge.destination.id == dst,
);

void main() {
  test(
    'genealogy mode renders an isolated viewer with no synthetic ego node',
    () async {
      final repo = _FakeInviteGenealogyRepository()
        ..bootstrapGraph = InviteGenealogyGraph(
          viewerNodeKey: 'Gviewer',
          nodes: [_node('Gviewer', _viewer, DateTime.utc(2026))],
          edges: [],
        );
      final cubit = _cubit(repo: repo);

      await _settleCubitFetch();

      expect(cubit.graphController.edges, isEmpty);
      expect(cubit.graphController.nodes.map((n) => n.id), ['Gviewer']);
      expect(cubit.graphController.nodes.whereType<UserNode>(), isEmpty);

      await cubit.close();
    },
  );

  test(
    'genealogy mode renders disconnected viewer and target endpoints',
    () async {
      final repo = _FakeInviteGenealogyRepository()
        ..bootstrapGraph = InviteGenealogyGraph(
          viewerNodeKey: 'Gviewer',
          targetNodeKey: 'Gtarget',
          nodes: [
            _node('Gviewer', _viewer, DateTime.utc(2026)),
            _node('Gtarget', _target, DateTime.utc(2026, 2)),
          ],
          edges: [],
        );
      final cubit = _cubit(repo: repo, targetId: _target.id);

      await _settleCubitFetch();

      expect(repo.lastBootstrapTargetId, _target.id);
      expect(cubit.state.egoNodeId, 'Gviewer');
      expect(cubit.state.genealogyTargetNodeKey, 'Gtarget');
      expect(
        cubit.graphController.nodes.map((node) => node.id).toSet(),
        {'Gviewer', 'Gtarget'},
      );

      await cubit.close();
    },
  );

  test(
    'preloaded root ancestor is rendered even though it is never a dst',
    () async {
      final rootAt = DateTime.utc(2026);
      final viewerAt = DateTime.utc(2026, 2);
      final repo = _FakeInviteGenealogyRepository()
        ..bootstrapGraph = InviteGenealogyGraph(
          viewerNodeKey: 'Gviewer',
          nodes: [
            _node(
              'Groot',
              const Profile(id: 'Uroot', displayName: 'Root'),
              rootAt,
            ),
            _node('Gviewer', _viewer, viewerAt),
          ],
          edges: [_edge('Groot', 'Gviewer', rootAt, viewerAt)],
        );
      final cubit = _cubit(repo: repo);

      await _settleCubitFetch();

      expect(
        cubit.graphController.nodes.map((node) => node.id).toSet(),
        {'Groot', 'Gviewer'},
      );

      await cubit.close();
    },
  );

  test('repeated focus fetches advance each node cursor', () async {
    final rootAt = DateTime.utc(2026);
    final child1At = DateTime.utc(2026, 2);
    final child2At = DateTime.utc(2026, 3);
    final child1Edge = _edge('Groot', 'Gchild1', rootAt, child1At);
    final child2Edge = _edge('Groot', 'Gchild2', rootAt, child2At);
    final repo = _FakeInviteGenealogyRepository()
      ..bootstrapGraph = InviteGenealogyGraph(
        viewerNodeKey: 'Groot',
        nodes: [_node('Groot', _viewer, rootAt)],
        edges: [],
      )
      ..childrenPages.addAll([
        (
          nodes: [
            _node('Groot', _viewer, rootAt),
            _node('Gchild1', _friend, child1At),
          ],
          edges: [child1Edge],
        ),
        (
          nodes: [
            _node('Groot', _viewer, rootAt),
            _node('Gchild2', _target, child2At),
          ],
          edges: [child2Edge],
        ),
      ]);
    final cubit = _cubit(repo: repo);
    await _settleCubitFetch();
    final root = cubit.graphController.nodes.singleWhere(
      (n) => n.id == 'Groot',
    );

    cubit.setFocus(root);
    await _settleCubitFetch();
    cubit.setFocus(root);
    await _settleCubitFetch();

    expect(repo.childrenCalls, hasLength(2));
    expect(repo.childrenCalls.first.afterCreatedAt, isNull);
    expect(repo.childrenCalls.first.afterNodeKey, isNull);
    expect(repo.childrenCalls.last.afterCreatedAt, child1At);
    expect(repo.childrenCalls.last.afterNodeKey, 'Gchild1');
    expect(
      cubit.graphController.edges.map((e) => e.destination.id).toSet(),
      {'Gchild1', 'Gchild2'},
    );

    await cubit.close();
  });

  test(
    'genealogy bootstrap populates hidden child counts for lineage nodes',
    () async {
      final rootAt = DateTime.utc(2026);
      final viewerAt = DateTime.utc(2026, 2);
      final targetAt = DateTime.utc(2026, 3);
      final repo = _FakeInviteGenealogyRepository()
        ..bootstrapGraph = InviteGenealogyGraph(
          viewerNodeKey: 'Gviewer',
          targetNodeKey: 'Gtarget',
          nodes: [
            _node(
              'Groot',
              const Profile(id: 'Uroot', displayName: 'Root'),
              rootAt,
            ),
            _node('Gviewer', _viewer, viewerAt),
            _node('Gtarget', _target, targetAt),
          ],
          edges: [
            _edge('Groot', 'Gviewer', rootAt, viewerAt),
            _edge('Groot', 'Gtarget', rootAt, targetAt),
          ],
        )
        ..childCounts.addAll({
          'Groot': 3,
          'Gviewer': 1,
          'Gtarget': 0,
        });
      final cubit = _cubit(repo: repo, targetId: _target.id);

      await _settleCubitFetch();

      expect(repo.childCountCalls, [
        {'Groot', 'Gviewer', 'Gtarget'},
      ]);
      expect(cubit.state.hiddenNeighborCounts, {
        'Groot': 1,
        'Gviewer': 1,
      });

      await cubit.close();
    },
  );

  test(
    'genealogy child expansion decreases hidden count to zero across pages',
    () async {
      final rootAt = DateTime.utc(2026);
      final child1At = DateTime.utc(2026, 2);
      final child2At = DateTime.utc(2026, 3);
      final repo = _FakeInviteGenealogyRepository()
        ..bootstrapGraph = InviteGenealogyGraph(
          viewerNodeKey: 'Groot',
          nodes: [_node('Groot', _viewer, rootAt)],
          edges: [],
        )
        ..childCounts.addAll({
          'Groot': 2,
          'Gchild1': 1,
          'Gchild2': 0,
        })
        ..childrenPages.addAll([
          (
            nodes: [
              _node('Groot', _viewer, rootAt),
              _node('Gchild1', _friend, child1At),
            ],
            edges: [_edge('Groot', 'Gchild1', rootAt, child1At)],
          ),
          (
            nodes: [
              _node('Groot', _viewer, rootAt),
              _node('Gchild2', _target, child2At),
            ],
            edges: [_edge('Groot', 'Gchild2', rootAt, child2At)],
          ),
        ]);
      final cubit = _cubit(repo: repo);
      await _settleCubitFetch();
      final root = cubit.graphController.nodes.singleWhere(
        (n) => n.id == 'Groot',
      );

      expect(cubit.state.hiddenNeighborCounts, {'Groot': 2});

      cubit.setFocus(root);
      await _settleCubitFetch();

      expect(cubit.state.hiddenNeighborCounts, {
        'Groot': 1,
        'Gchild1': 1,
      });

      cubit.setFocus(root);
      await _settleCubitFetch();

      expect(cubit.state.hiddenNeighborCounts, {'Gchild1': 1});
      expect(repo.childCountCalls, [
        {'Groot'},
        {'Groot', 'Gchild1'},
        {'Groot', 'Gchild2'},
      ]);

      await cubit.close();
    },
  );

  test(
    'child expansion does not duplicate an existing bootstrap edge',
    () async {
      final rootAt = DateTime.utc(2026);
      final parentAt = DateTime.utc(2026, 2);
      final edge = _edge('Groot', 'Gparent', rootAt, parentAt);
      final repo = _FakeInviteGenealogyRepository()
        ..bootstrapGraph = InviteGenealogyGraph(
          viewerNodeKey: 'Gparent',
          commonAncestorNodeKey: 'Groot',
          nodes: [
            _node(
              'Groot',
              const Profile(id: 'Uroot', displayName: 'Root'),
              rootAt,
            ),
            _node('Gparent', _viewer, parentAt),
          ],
          edges: [edge],
        )
        ..childrenPages.add((
          nodes: [
            _node(
              'Groot',
              const Profile(id: 'Uroot', displayName: 'Root'),
              rootAt,
            ),
            _node('Gparent', _viewer, parentAt),
          ],
          edges: [edge],
        ));
      final cubit = _cubit(repo: repo);
      await _settleCubitFetch();
      final root = cubit.graphController.nodes.singleWhere(
        (n) => n.id == 'Groot',
      );

      cubit.setFocus(root);
      await _settleCubitFetch();

      expect(
        cubit.graphController.edges.where(
          (e) => e.source.id == 'Groot' && e.destination.id == 'Gparent',
        ),
        hasLength(1),
      );

      await cubit.close();
    },
  );

  test('between mode colors viewer branch, target branch, and trunk', () async {
    final rootAt = DateTime.utc(2026);
    final lcaAt = DateTime.utc(2026, 2);
    final viewerAt = DateTime.utc(2026, 3);
    final targetAt = DateTime.utc(2026, 4);
    final repo = _FakeInviteGenealogyRepository()
      ..bootstrapGraph = InviteGenealogyGraph(
        viewerNodeKey: 'Gviewer',
        targetNodeKey: 'Gtarget',
        commonAncestorNodeKey: 'Glca',
        nodes: [
          _node(
            'Groot',
            const Profile(id: 'Uroot', displayName: 'Root'),
            rootAt,
          ),
          _node('Glca', const Profile(id: 'Ulca', displayName: 'Lca'), lcaAt),
          _node('Gviewer', _viewer, viewerAt),
          _node('Gtarget', _target, targetAt),
        ],
        edges: [
          _edge('Groot', 'Glca', rootAt, lcaAt),
          _edge('Glca', 'Gviewer', lcaAt, viewerAt),
          _edge('Glca', 'Gtarget', lcaAt, targetAt),
        ],
      );
    final cubit = _cubit(repo: repo, targetId: _target.id);

    await _settleCubitFetch();

    expect(_edgeDetails(cubit, 'Groot', 'Glca').color, _edgeColors.neutral);
    expect(_edgeDetails(cubit, 'Glca', 'Gviewer').color, _edgeColors.ego);
    expect(_edgeDetails(cubit, 'Glca', 'Gtarget').color, _edgeColors.target);

    await cubit.close();
  });

  test(
    'genealogy parent-chain nodes pin on first exploration tap and remain visible',
    () async {
      final rootAt = DateTime.utc(2026);
      final lcaAt = DateTime.utc(2026, 2);
      final viewerAt = DateTime.utc(2026, 3);
      final targetAt = DateTime.utc(2026, 4);
      final childAt = DateTime.utc(2026, 5);
      final repo = _FakeInviteGenealogyRepository()
        ..bootstrapGraph = InviteGenealogyGraph(
          viewerNodeKey: 'Gviewer',
          targetNodeKey: 'Gtarget',
          commonAncestorNodeKey: 'Glca',
          nodes: [
            _node(
              'Groot',
              const Profile(id: 'Uroot', displayName: 'Root'),
              rootAt,
            ),
            _node('Glca', const Profile(id: 'Ulca', displayName: 'Lca'), lcaAt),
            _node('Gviewer', _viewer, viewerAt),
            _node('Gtarget', _target, targetAt),
          ],
          edges: [
            _edge('Groot', 'Glca', rootAt, lcaAt),
            _edge('Glca', 'Gviewer', lcaAt, viewerAt),
            _edge('Glca', 'Gtarget', lcaAt, targetAt),
          ],
        )
        ..childrenPages.add((
          nodes: [
            _node('Gtarget', _target, targetAt),
            _node('Gchild', _friend, childAt),
          ],
          edges: [_edge('Gtarget', 'Gchild', targetAt, childAt)],
        ));
      final cubit = _cubit(repo: repo, targetId: _target.id);

      await _settleCubitFetch();

      final parentChainIds = {'Groot', 'Glca', 'Gviewer', 'Gtarget'};
      expect(
        cubit.graphController.nodes
            .where((node) => parentChainIds.contains(node.id))
            .where((node) => node.pinned)
            .map((node) => node.id)
            .toSet(),
        {'Gviewer', 'Gtarget'},
      );

      final target = cubit.graphController.nodes.singleWhere(
        (node) => node.id == 'Gtarget',
      );
      cubit.setFocus(target);
      await _settleCubitFetch();

      expect(
        cubit.graphController.nodes
            .where((node) => parentChainIds.contains(node.id))
            .map((node) => node.pinned)
            .toSet(),
        {true},
      );
      expect(
        cubit.graphController.nodes.map((node) => node.id).toSet(),
        containsAll({...parentChainIds, 'Gchild'}),
      );
      expect(
        cubit.graphController.edges
            .map((edge) => (edge.source.id, edge.destination.id))
            .toSet(),
        containsAll({
          ('Groot', 'Glca'),
          ('Glca', 'Gviewer'),
          ('Glca', 'Gtarget'),
          ('Gtarget', 'Gchild'),
        }),
      );

      await cubit.close();
    },
  );

  test('genealogy mode ignores context and positive-only controls', () async {
    final repo = _FakeInviteGenealogyRepository()
      ..bootstrapGraph = InviteGenealogyGraph(
        viewerNodeKey: 'Gviewer',
        nodes: [_node('Gviewer', _viewer, DateTime.utc(2026))],
        edges: [],
      );
    final cubit = _cubit(repo: repo);
    await _settleCubitFetch();

    cubit.togglePositiveOnly();
    await cubit.setContext('ignored-context');
    await _settleCubitFetch();

    expect(cubit.state.positiveOnly, isTrue);
    expect(cubit.state.context, isEmpty);
    expect(cubit.state.focus, isEmpty);
    expect(repo.childrenCalls, isEmpty);
    expect(cubit.graphController.nodes.map((node) => node.id), ['Gviewer']);

    await cubit.close();
  });

  test(
    'regular graph redraws edges after context clears the controller',
    () async {
      final source = _FakeGraphSourceRepository();
      final cubit = GraphCubit(
        me: _viewer,
        graphSourceRepository: source,
        edgeColors: _edgeColors,
        beaconRepository: _FakeBeaconRepository(),
        profileRepository: _FakeProfileRepository(),
        effects: FakeUiEffectPort(),
      );
      await _settleCubitFetch();
      expect(cubit.graphController.edges, hasLength(1));

      await cubit.setContext('new-context');
      await _settleCubitFetch();

      expect(source.calls, greaterThanOrEqualTo(2));
      expect(cubit.graphController.edges, hasLength(1));

      await cubit.close();
    },
  );

  test(
    'regular graph derives hidden counts from endpoint total degrees',
    () async {
      final source = _FakeGraphSourceRepository()
        ..fetchResult = () => {
          (
            src: _viewer.id,
            dst: _friend.id,
            weight: 1,
            node: const UserNode(user: _friend),
            branch: null,
            srcTotalNeighborCount: 3,
            dstTotalNeighborCount: 1,
          ),
        };
      final cubit = GraphCubit(
        me: _viewer,
        graphSourceRepository: source,
        edgeColors: _edgeColors,
        beaconRepository: _FakeBeaconRepository(),
        profileRepository: _FakeProfileRepository(),
        effects: FakeUiEffectPort(),
      );

      await _settleCubitFetch();

      expect(cubit.graphController.edges, hasLength(1));
      expect(cubit.state.hiddenNeighborCounts, {_viewer.id: 2});

      await cubit.close();
    },
  );

  test(
    'regular graph hidden count is stable when an unrelated focus tap '
    'later surfaces the reverse edge of an already-mutual relationship',
    () async {
      const stranger = Profile(id: 'Ustranger', displayName: 'Stranger');
      final fetches = <Set<EdgeDirected>>[
        {
          (
            src: _viewer.id,
            dst: _friend.id,
            weight: 1,
            node: const UserNode(user: _friend),
            branch: null,
            srcTotalNeighborCount: 3,
            dstTotalNeighborCount: 1,
          ),
          (
            src: _viewer.id,
            dst: stranger.id,
            weight: 1,
            node: const UserNode(user: stranger),
            branch: null,
            srcTotalNeighborCount: 3,
            dstTotalNeighborCount: 0,
          ),
        },
        // MeritRank reports a mutual relationship as two directed rows.
        // This is the reverse direction of the *same* viewer<->friend
        // relationship above, surfaced only because `stranger` — an
        // unrelated node — was tapped.
        {
          (
            src: _friend.id,
            dst: _viewer.id,
            weight: 1,
            node: const UserNode(user: _viewer),
            branch: null,
            srcTotalNeighborCount: 1,
            dstTotalNeighborCount: 3,
          ),
        },
      ];
      final source = _FakeGraphSourceRepository()
        ..fetchResult = () => fetches.removeAt(0);
      final cubit = GraphCubit(
        me: _viewer,
        graphSourceRepository: source,
        edgeColors: _edgeColors,
        beaconRepository: _FakeBeaconRepository(),
        profileRepository: _FakeProfileRepository(),
        effects: FakeUiEffectPort(),
      );

      await _settleCubitFetch();
      expect(cubit.state.hiddenNeighborCounts, {_viewer.id: 1});

      final strangerNode = cubit.graphController.nodes.singleWhere(
        (n) => n.id == stranger.id,
      );
      cubit.setFocus(strangerNode);
      await _settleCubitFetch();

      expect(cubit.state.hiddenNeighborCounts, {_viewer.id: 2});

      await cubit.close();
    },
  );

  test('generic repository fetch adapter fails loudly', () async {
    final remote = RemoteApiService(const Env());
    final repository = InviteGenealogyRepository(
      remoteApiService: remote,
      log: Logger('InviteGenealogyRepositoryTest'),
    );
    addTearDown(remote.close);

    expect(
      repository.fetch,
      throwsA(isA<UnsupportedError>()),
    );
  });
}
