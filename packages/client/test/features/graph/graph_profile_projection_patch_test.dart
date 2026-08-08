import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_scaffold.dart';
import 'package:tentura/features/invite_genealogy/data/repository/invite_genealogy_repository.dart';
import 'package:tentura/features/invite_genealogy/domain/entity/invite_genealogy_graph.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:mockito/mockito.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeGraphSource implements GraphSourceRepository {
  final pages = <String?, Set<EdgeDirected>>{};

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
    Set<String> excludeNeighborIds = const {},
  }) async => pages[focus] ?? const {};

  @override
  Future<Set<EdgeDirected>> fetchEdgesBetween({
    required Set<String> nodeIds,
    bool positiveOnly = true,
  }) async => const {};
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  final fetchedIds = <String>[];

  @override
  Future<Profile> fetchById(String id) async {
    fetchedIds.add(id);
    return Profile(id: id, displayName: id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeInviteGenealogyRepository implements InviteGenealogyRepository {
  InviteGenealogyGraph bootstrapGraph = const InviteGenealogyGraph(
    viewerNodeKey: '',
    nodes: [],
    edges: [],
  );

  @override
  Future<InviteGenealogyGraph> fetchGenealogyBootstrap({
    String? targetId,
  }) async => bootstrapGraph;

  @override
  Future<InviteGenealogyChildrenPage> fetchChildren({
    required String nodeKey,
    required int limit,
    DateTime? afterCreatedAt,
    String? afterNodeKey,
  }) async =>
      const (nodes: <InviteGenealogyNode>[], edges: <InviteGenealogyEdge>[]);

  @override
  Future<Map<String, int>> fetchChildCounts({
    required List<String> nodeKeys,
  }) async => {};

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
    Set<String> excludeNeighborIds = const {},
  }) => throw UnsupportedError('genealogy mode');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

const _edgeColors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

const _me = Profile(id: 'Ume', displayName: 'Me');

EdgeDirected _e(
  String src,
  String dst, {
  double weight = 1,
  NodeDetails? dstNode,
}) => (
  src: src,
  dst: dst,
  weight: weight,
  node: dstNode,
  branch: null,
  srcTotalNeighborCount: null,
  dstTotalNeighborCount: null,
);

Future<void> _settle() => pumpEventQueue(times: 5);

GraphCubit _trustCubit(
  _FakeGraphSource source,
  _FakeProfileRepository profileRepo,
) => GraphCubit(
  me: _me,
  graphSourceRepository: source,
  edgeColors: _edgeColors,
  beaconRepository: _FakeBeaconRepository(),
  profileRepository: profileRepo,
  effects: FakeUiEffectPort(),
);

NodeDetails _liveNode(GraphCubit cubit, String id) =>
    cubit.graphController.nodes.singleWhere((n) => n.id == id);

Set<(String, String)> _edgePairs(GraphCubit cubit) => {
  for (final e in cubit.graphController.edges) (e.source.id, e.destination.id),
};

InviteGenealogyNode _genealogyNode(
  String nodeKey,
  Profile profile,
  DateTime createdAt,
) => InviteGenealogyNode(
  nodeKey: nodeKey,
  profile: profile,
  userCreatedAt: createdAt,
);

Future<void> _settleGraph(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<GraphCubit> _pumpTrustGraphView(
  WidgetTester tester, {
  required _FakeGraphSource source,
  required _FakeProfileRepository profileRepo,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final cubit = _trustCubit(source, profileRepo);
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MultiBlocProvider(
        providers: [
          BlocProvider<GraphCubit>.value(value: cubit),
          BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
          BlocProvider<ProfileCubit>.value(value: _FakeProfileCubit()),
        ],
        child: GraphScaffold(
          title: const Text('Graph'),
        ),
      ),
    ),
  );

  return cubit;
}

void main() {
  test('myVote 0→1 keeps metadata and replaces controller node', () async {
    final aliceProfile = Profile(id: 'Ualice', displayName: 'Alice', myVote: 0);
    final source = _FakeGraphSource()
      ..pages.addAll({
        null: {
          _e(
            'Ume',
            'Ualice',
            dstNode: UserNode(
              user: aliceProfile,
              size: 56,
              pinned: true,
            ),
          ),
        },
      });
    final profileRepo = _FakeProfileRepository();
    final cubit = _trustCubit(source, profileRepo);
    await _settle();

    cubit.selectNode(_liveNode(cubit, 'Ualice'));
    await _settle();

    final fetchCount = profileRepo.fetchedIds.length;
    final aliceBefore = _liveNode(cubit, 'Ualice') as UserNode;
    final edgesBefore = _edgePairs(cubit);

    cubit.patchLoadedProfile(aliceProfile.copyWith(myVote: 1));
    await _settle();

    expect(profileRepo.fetchedIds.length, fetchCount);

    final aliceAfter = _liveNode(cubit, 'Ualice') as UserNode;
    expect(aliceAfter, isNot(same(aliceBefore)));
    expect(aliceAfter.id, 'Ualice');
    expect(aliceAfter.size, 56);
    expect(aliceAfter.pinned, isTrue);
    expect(aliceAfter.user.myVote, 1);
    expect(aliceAfter.isHelpOfferer, aliceBefore.isHelpOfferer);
    expect(_edgePairs(cubit), edgesBefore);

    await cubit.close();
  });

  test('incoming-trust-only patch updates loaded projection', () async {
    final alice = Profile(id: 'Ualice', displayName: 'Alice');
    final source = _FakeGraphSource()
      ..pages[null] = {
        _e('Ume', 'Ualice', dstNode: UserNode(user: alice)),
      };
    final cubit = _trustCubit(source, _FakeProfileRepository());
    await _settle();

    cubit.patchLoadedProfile(
      alice.copyWith(subjectExplicitlyTrustsViewer: true),
    );

    final node = _liveNode(cubit, 'Ualice') as UserNode;
    expect(node.user.subjectExplicitlyTrustsViewer, isTrue);

    await cubit.close();
  });

  test('isHelpOfferer survives profile patch', () async {
    final alice = Profile(id: 'Ualice');
    final source = _FakeGraphSource()
      ..pages[null] = {
        _e(
          'Ume',
          'Ualice',
          dstNode: UserNode(user: alice, isHelpOfferer: true),
        ),
      };
    final cubit = _trustCubit(source, _FakeProfileRepository());
    await _settle();

    cubit.patchLoadedProfile(alice.copyWith(myVote: 1));

    final node = _liveNode(cubit, 'Ualice') as UserNode;
    expect(node.isHelpOfferer, isTrue);

    await cubit.close();
  });

  test('rScore patch updates loaded projection', () async {
    final alice = Profile(id: 'Ualice', rScore: 0);
    final source = _FakeGraphSource()
      ..pages[null] = {
        _e('Ume', 'Ualice', dstNode: UserNode(user: alice)),
      };
    final cubit = _trustCubit(source, _FakeProfileRepository());
    await _settle();

    cubit.patchLoadedProfile(alice.copyWith(rScore: 1.5));

    final node = _liveNode(cubit, 'Ualice') as UserNode;
    expect(node.user.rScore, 1.5);
    expect(node.rScore, 1.5);

    await cubit.close();
  });

  test('isMutualFriend patch updates loaded projection', () async {
    final alice = Profile(id: 'Ualice', isMutualFriend: false);
    final source = _FakeGraphSource()
      ..pages[null] = {
        _e('Ume', 'Ualice', dstNode: UserNode(user: alice)),
      };
    final cubit = _trustCubit(source, _FakeProfileRepository());
    await _settle();

    cubit.patchLoadedProfile(alice.copyWith(isMutualFriend: true));

    final node = _liveNode(cubit, 'Ualice') as UserNode;
    expect(node.user.isMutualFriend, isTrue);

    await cubit.close();
  });

  test('Alice update leaves Bob identical and unreplaced', () async {
    final source = _FakeGraphSource()
      ..pages[null] = {
        _e(
          'Ume',
          'Ualice',
          dstNode: UserNode(user: Profile(id: 'Ualice')),
        ),
        _e(
          'Ume',
          'Ubob',
          dstNode: UserNode(user: Profile(id: 'Ubob')),
        ),
      };
    final cubit = _trustCubit(source, _FakeProfileRepository());
    await _settle();

    final bobBefore = _liveNode(cubit, 'Ubob');
    final bobMapBefore = cubit.graphController.nodes.singleWhere(
      (n) => n.id == 'Ubob',
    );

    cubit.patchLoadedProfile(Profile(id: 'Ualice', myVote: 1));
    await _settle();

    final bobAfter = _liveNode(cubit, 'Ubob');
    expect(bobAfter, same(bobBefore));
    expect(
      cubit.graphController.nodes.singleWhere((n) => n.id == 'Ubob'),
      same(bobMapBefore),
    );

    await cubit.close();
  });

  test(
    'self profile patch asserts in debug and preserves ego Me projection',
    () async {
      final source = _FakeGraphSource()
        ..pages[null] = {
          _e(
            'Ume',
            'Ualice',
            dstNode: UserNode(user: Profile(id: 'Ualice')),
          ),
        };
      final cubit = _trustCubit(source, _FakeProfileRepository());
      await _settle();

      final egoBefore =
          cubit.graphController.nodes.singleWhere(
                (n) => n.id == 'Ume',
              )
              as UserNode;

      expect(
        () => cubit.patchLoadedProfile(
          _me.copyWith(displayName: 'Not Me', score: 99),
        ),
        throwsAssertionError,
      );

      final egoAfter =
          cubit.graphController.nodes.singleWhere(
                (n) => n.id == 'Ume',
              )
              as UserNode;
      expect(egoAfter.user.displayName, egoBefore.user.displayName);
      expect(egoAfter.user.score, egoBefore.user.score);
      expect(egoAfter.label, 'Me');

      await cubit.close();
    },
  );

  test('multiple genealogy occurrences of one account all update', () async {
    final alice = Profile(id: 'Ualice', displayName: 'Alice');
    final at = DateTime.utc(2026);
    final repo = _FakeInviteGenealogyRepository()
      ..bootstrapGraph = InviteGenealogyGraph(
        viewerNodeKey: 'Gviewer',
        nodes: [
          _genealogyNode('Galice1', alice, at),
          _genealogyNode('Galice2', alice, at),
        ],
        edges: [],
      );
    final cubit = GraphCubit(
      me: _me,
      graphSourceRepository: repo,
      genealogyMode: true,
      genealogyAnonymousNodeLabel: 'Anonymous',
      edgeColors: _edgeColors,
      beaconRepository: _FakeBeaconRepository(),
      profileRepository: _FakeProfileRepository(),
      effects: FakeUiEffectPort(),
    );
    await _settle();

    cubit.patchLoadedProfile(alice.copyWith(myVote: 1));
    await _settle();

    final keys = cubit.graphController.nodes
        .whereType<GenealogyUserNode>()
        .where((n) => n.user.id == 'Ualice')
        .toList();
    expect(keys.length, 2);
    expect(keys.map((n) => n.nodeKey).toSet(), {'Galice1', 'Galice2'});
    expect(keys.every((n) => n.user.myVote == 1), isTrue);

    await cubit.close();
  });

  test('genealogy nodeKey survives profile patch', () async {
    final alice = Profile(id: 'Ualice');
    final at = DateTime.utc(2026);
    final repo = _FakeInviteGenealogyRepository()
      ..bootstrapGraph = InviteGenealogyGraph(
        viewerNodeKey: 'Gviewer',
        nodes: [_genealogyNode('Galice', alice, at)],
        edges: [],
      );
    final cubit = GraphCubit(
      me: _me,
      graphSourceRepository: repo,
      genealogyMode: true,
      genealogyAnonymousNodeLabel: 'Anonymous',
      edgeColors: _edgeColors,
      beaconRepository: _FakeBeaconRepository(),
      profileRepository: _FakeProfileRepository(),
      effects: FakeUiEffectPort(),
    );
    await _settle();

    cubit.patchLoadedProfile(alice.copyWith(myVote: 1));

    final node =
        cubit.graphController.nodes.singleWhere(
              (n) => n.id == 'Galice',
            )
            as GenealogyUserNode;
    expect(node.nodeKey, 'Galice');
    expect(node.user.myVote, 1);

    await cubit.close();
  });

  testWidgets('patch preserves layout position via replaceNode', (
    tester,
  ) async {
    final alice = Profile(id: 'Ualice', displayName: 'Alice');
    final source = _FakeGraphSource()
      ..pages[null] = {
        _e('Ume', 'Ualice', dstNode: UserNode(user: alice)),
        _e(
          'Ume',
          'Ubob',
          dstNode: UserNode(user: Profile(id: 'Ubob')),
        ),
      };
    final profileRepo = _FakeProfileRepository();
    final cubit = await _pumpTrustGraphView(
      tester,
      source: source,
      profileRepo: profileRepo,
    );
    await _settleGraph(tester);

    expect(cubit.graphController.canLayout, isTrue);
    final fetchCount = profileRepo.fetchedIds.length;

    final aliceBefore = _liveNode(cubit, 'Ualice');
    final positionBefore = cubit.graphController.layout.getPosition(
      aliceBefore,
    );
    final edgesBefore = _edgePairs(cubit);

    cubit.patchLoadedProfile(alice.copyWith(myVote: 1));

    final aliceAfter = _liveNode(cubit, 'Ualice');
    expect(aliceAfter, isNot(same(aliceBefore)));
    expect(
      cubit.graphController.layout.getPosition(aliceAfter),
      positionBefore,
    );
    expect(_edgePairs(cubit), edgesBefore);
    expect(profileRepo.fetchedIds.length, fetchCount);
  });
}
