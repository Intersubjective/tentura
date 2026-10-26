import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_body.dart';
import 'package:tentura/features/graph/ui/widget/graph_scaffold.dart';
import 'package:tentura/features/invite_genealogy/data/repository/invite_genealogy_repository.dart';
import 'package:tentura/features/invite_genealogy/domain/entity/invite_genealogy_graph.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

/// #464: on a wide window (>= 840 px) the shared invite lineage runs left to
/// right (root ancestor on the left, each generation to its right); below
/// 840 px it keeps the top-to-bottom layout. Either way the whole path opens
/// on screen without overflow.

class _FakeInviteGenealogyRepository implements InviteGenealogyRepository {
  _FakeInviteGenealogyRepository(this.bootstrapGraph);

  final InviteGenealogyGraph bootstrapGraph;

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
  }) async => const (
    nodes: <InviteGenealogyNode>[],
    edges: <InviteGenealogyEdge>[],
  );

  @override
  Future<Map<String, int>> fetchChildCounts({
    required List<String> nodeKeys,
  }) async => const {};

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
    Set<String> excludeNeighborIds = const {},
  }) => throw UnsupportedError('generic fetch is not used in genealogy mode');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
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

/// Root ancestor first, viewer last: `hops` invite edges above the viewer.
InviteGenealogyGraph _lineage(int hops) {
  final keys = [for (var i = 0; i < hops; i++) 'Ganc$i', 'Gviewer'];
  final at = DateTime.utc(2026);
  return InviteGenealogyGraph(
    viewerNodeKey: 'Gviewer',
    nodes: [
      for (final key in keys)
        InviteGenealogyNode(
          nodeKey: key,
          profile: key == 'Gviewer'
              ? _viewer
              : Profile(id: 'U$key', displayName: key),
          userCreatedAt: at,
        ),
    ],
    edges: [
      for (var i = 0; i + 1 < keys.length; i++)
        InviteGenealogyEdge(
          ancestorNodeKey: keys[i],
          descendantNodeKey: keys[i + 1],
          ancestorUserCreatedAt: at,
          descendantUserCreatedAt: at,
          createdAt: at,
        ),
    ],
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pump();
}

Future<GraphCubit> _pumpInviteTree(
  WidgetTester tester, {
  required int hops,
  required Size size,
}) async {
  // The view size (not setSurfaceSize) is what MediaQuery, and so the
  // window class, reads.
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final cubit = GraphCubit(
    me: _viewer,
    graphSourceRepository: _FakeInviteGenealogyRepository(_lineage(hops)),
    genealogyMode: true,
    genealogyAnonymousNodeLabel: 'Anonymous',
    edgeColors: _edgeColors,
    beaconRepository: _FakeBeaconRepository(),
    profileRepository: _FakeProfileRepository(),
    effects: FakeUiEffectPort(),
  );
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
        ],
        child: const GraphScaffold(title: Text('Invite tree')),
      ),
    ),
  );
  await _settle(tester);
  return cubit;
}

const _hops = 4;

List<String> get _pathKeys => [
  for (var i = 0; i < _hops; i++) 'Ganc$i',
  'Gviewer',
];

List<Offset> _nodeCentres(WidgetTester tester) => [
  for (final key in _pathKeys) _nodeRect(tester, key).center,
];

Rect _nodeRect(WidgetTester tester, String nodeKey) {
  final finder = find.byKey(TestIds.key(TestIds.graphNode(nodeKey)));
  expect(finder, findsOneWidget, reason: '$nodeKey should be on screen');
  return tester.getRect(finder);
}

void _expectAllNodesInViewport(WidgetTester tester) {
  final viewport = tester.getRect(find.byType(GraphBody));
  for (final key in _pathKeys) {
    final rect = _nodeRect(tester, key);
    expect(
      viewport.contains(rect.topLeft) && viewport.contains(rect.bottomRight),
      isTrue,
      reason: '$key at $rect is outside viewport $viewport',
    );
  }
}

void _expectHorizontal(List<Offset> centres) {
  for (var i = 1; i < centres.length; i++) {
    expect(
      centres[i].dx,
      greaterThan(centres[i - 1].dx + 1),
      reason: 'generation $i should sit right of generation ${i - 1}',
    );
    expect(centres[i].dy, closeTo(centres[0].dy, 1));
  }
}

void _expectVertical(List<Offset> centres) {
  for (var i = 1; i < centres.length; i++) {
    expect(
      centres[i].dy,
      greaterThan(centres[i - 1].dy + 1),
      reason: 'generation $i should sit below generation ${i - 1}',
    );
    expect(centres[i].dx, closeTo(centres[0].dx, 1));
  }
}

void main() {
  testWidgets(
    'at 1280 px wide the lineage runs left to right, root first, all on '
    'screen',
    (tester) async {
      final cubit = await _pumpInviteTree(
        tester,
        hops: _hops,
        size: const Size(1280, 800),
      );
      expect(cubit.graphController.nodes, hasLength(_hops + 1));

      _expectHorizontal(_nodeCentres(tester));
      _expectAllNodesInViewport(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'at exactly 840 px wide the lineage is already horizontal',
    (tester) async {
      await _pumpInviteTree(tester, hops: _hops, size: const Size(840, 800));

      _expectHorizontal(_nodeCentres(tester));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'at 400 px wide the lineage keeps the top-to-bottom layout, all on '
    'screen',
    (tester) async {
      await _pumpInviteTree(tester, hops: _hops, size: const Size(400, 800));

      _expectVertical(_nodeCentres(tester));
      _expectAllNodesInViewport(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrowing the window below 840 px turns the lineage back to vertical',
    (tester) async {
      final cubit = await _pumpInviteTree(
        tester,
        hops: _hops,
        size: const Size(1280, 800),
      );
      _expectHorizontal(_nodeCentres(tester));

      tester.view.physicalSize = const Size(400, 800);
      await _settle(tester);
      cubit.fitCurrentPath();
      await _settle(tester);

      _expectVertical(_nodeCentres(tester));
      _expectAllNodesInViewport(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
