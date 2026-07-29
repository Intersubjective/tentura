import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_body.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _WidgetTestGraphSource extends GraphSourceRepository {
  final pages = <String?, Set<EdgeDirected>>{};
  int calls = 0;

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
    return pages[focus] ?? const {};
  }
}

const _edgeColors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

const _me = Profile(id: 'Ume', displayName: 'Me');

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
}

Future<GraphCubit> _pumpGraphBody(
  WidgetTester tester, {
  required _WidgetTestGraphSource source,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 600));
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
        child: const Scaffold(body: GraphBody()),
      ),
    ),
  );

  await tester.pump();
  await _settleGraph(tester);
  return cubit;
}

void main() {
  testWidgets('one node tap selects focus without fetching', (tester) async {
    final source = _WidgetTestGraphSource()
      ..pages.addAll({
        null: {_e('Ume', 'Ub')},
      });
    final cubit = await _pumpGraphBody(tester, source: source);
    expect(source.calls, 1);

    await tester.tap(find.byType(GraphNodeWidget).at(1));
    await _settleGraph(tester);

    expect(cubit.state.focus, isNotEmpty);
    expect(source.calls, 1);
  });

  testWidgets('Expand performs exactly one fetch', (tester) async {
    final source = _WidgetTestGraphSource()
      ..pages.addAll({
        null: {_e('Ume', 'Ub')},
        'Ub': {_e('Ub', 'Ue')},
      });
    final cubit = await _pumpGraphBody(tester, source: source);
    expect(source.calls, 1);

    await tester.tap(find.byType(GraphNodeWidget).at(1));
    await _settleGraph(tester);
    expect(source.calls, 1);

    await tester.tap(find.text('Expand'));
    await _settleGraph(tester);

    expect(source.calls, 2);
    expect(
      cubit.graphController.edges.map((e) => e.destination.id),
      contains('Ue'),
    );
  });
}
