import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_scaffold.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

// #615 (V8b): an empty Trust graph shows the viewer's "Me" node and a
// one-line empty state, only once loaded and only when there are no edges.

const _emptyText =
    'No trust links yet. Trust someone from their profile to see them here.';

const _me = Profile(id: 'Ume', displayName: 'Me');

const _edgeColors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

class _FakeGraphSource extends GraphSourceRepository {
  _FakeGraphSource({this.edges = const {}, this.error});

  final Set<EdgeDirected> edges;
  final Object? error;

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
    Set<String> excludeNeighborIds = const {},
  }) async {
    if (error != null) {
      throw error!;
    }
    return focus == null ? edges : const {};
  }
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  Future<Profile> fetchById(String id) async =>
      Profile(id: id, displayName: id);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeBeaconRepository implements BeaconRepository {
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

EdgeDirected _e(String src, String dst) => (
  src: src,
  dst: dst,
  weight: 1.0,
  node: UserNode(
    user: Profile(id: dst, displayName: dst),
  ),
  branch: null,
  srcTotalNeighborCount: null,
  dstTotalNeighborCount: null,
);

Future<void> _settleGraph(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<GraphCubit> _pumpTrustGraph(
  WidgetTester tester, {
  required GraphSourceRepository source,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final cubit = GraphCubit(
    me: _me,
    graphSourceRepository: source,
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
          BlocProvider<ProfileCubit>.value(value: _FakeProfileCubit()),
        ],
        child: GraphScaffold(
          title: const Text('Graph'),
        ),
      ),
    ),
  );

  await tester.pump();
  await _settleGraph(tester);
  return cubit;
}

final _meNode = find.byKey(TestIds.key(TestIds.graphNode(_me.id)));

void main() {
  group('trust graph empty state (#615)', () {
    testWidgets('no edges shows the Me node and the empty-state line', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        final cubit = await _pumpTrustGraph(
          tester,
          source: _FakeGraphSource(),
        );

        expect(cubit.state.isLoading, isFalse);
        expect(cubit.graphController.edges, isEmpty);
        expect(_meNode, findsOneWidget);
        expect(find.bySemanticsLabel('Me'), findsWidgets);
        expect(find.text(_emptyText), findsOneWidget);

        // The Me node stays on screen beside the line.
        final meCenter = tester.getCenter(_meNode);
        expect(meCenter.dx, inInclusiveRange(0, 400));
        expect(meCenter.dy, inInclusiveRange(0, 800));
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('with trust edges the empty-state line is not shown', (
      tester,
    ) async {
      await _pumpTrustGraph(
        tester,
        source: _FakeGraphSource(edges: {_e('Ume', 'Ub')}),
      );

      expect(_meNode, findsOneWidget);
      expect(find.byKey(TestIds.key(TestIds.graphNode('Ub'))), findsOneWidget);
      expect(find.text(_emptyText), findsNothing);
    });

    testWidgets('a failed load does not claim there are no trust links', (
      tester,
    ) async {
      await _pumpTrustGraph(
        tester,
        source: _FakeGraphSource(error: Exception('offline')),
      );

      expect(find.text(_emptyText), findsNothing);
    });

    testWidgets('zoomed in, the empty-state line never covers Me', (
      tester,
    ) async {
      final cubit = await _pumpTrustGraph(
        tester,
        source: _FakeGraphSource(),
      );
      // The name under the Me marker (its key is the node it labels).
      final meLabel = find.byWidgetPredicate((w) {
        final key = w.key;
        return w is Text &&
            key is ValueKey &&
            key.value is UserNode &&
            (key.value as UserNode).id == _me.id;
      });
      expect(meLabel, findsOneWidget);

      void expectClear() {
        final text = tester.getRect(find.text(_emptyText));
        expect(text.overlaps(tester.getRect(meLabel)), isFalse);
        expect(text.overlaps(tester.getRect(_meNode)), isFalse);
      }

      // Guard: at the opening zoom the line already sits under Me.
      expectClear();
      for (final factor in const [1.5, 2.0, 2.0]) {
        cubit.graphController.zoomBy(factor);
        await tester.pump();
        expect(find.text(_emptyText), findsOneWidget);
        expectClear();
      }
      expect(tester.takeException(), isNull);
    });
  });
}
