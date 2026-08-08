import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
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
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _WidgetTestGraphSource extends GraphSourceRepository {
  final pages = <String?, Set<EdgeDirected>>{};
  int ubFetches = 0;

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
    if (focus == 'Ub') {
      ubFetches += 1;
      if (ubFetches == 1) {
        return {_e('Ub', 'Ue', srcTotal: 3)};
      }
    }
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

EdgeDirected _e(
  String src,
  String dst, {
  int? srcTotal,
  int? dstTotal,
}) => (
  src: src,
  dst: dst,
  weight: 1.0,
  node: UserNode(
    user: Profile(id: dst, displayName: dst),
  ),
  branch: null,
  srcTotalNeighborCount: srcTotal,
  dstTotalNeighborCount: dstTotal,
);

Future<void> _settleGraph(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<GraphCubit> _pumpGraphBody(
  WidgetTester tester, {
  Size size = const Size(400, 800),
  _WidgetTestGraphSource? source,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final cubit = GraphCubit(
    me: _me,
    graphSourceRepository: source ?? _WidgetTestGraphSource(),
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

void main() {
  testWidgets('compact layout exposes reset and legend controls', (
    tester,
  ) async {
    await _pumpGraphBody(tester);

    final backButton = tester.widget<IconButton>(
      find.byKey(TestIds.key(TestIds.graphBack)),
    );
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(backButton.onPressed, isNull);

    final fitButton = tester.widget<IconButton>(
      find.byKey(TestIds.key(TestIds.graphFit)),
    );
    expect(find.byTooltip('Fit current path'), findsOneWidget);
    expect(fitButton.onPressed, isNotNull);
    expect(find.byTooltip('Reset to me'), findsOneWidget);
    expect(find.byKey(TestIds.key(TestIds.graphResetToEgo)), findsOneWidget);
    expect(find.byTooltip('Show legend'), findsOneWidget);
  });

  testWidgets('expand is hidden while fetch is in flight', (tester) async {
    final source = _WidgetTestGraphSource()
      ..pages.addAll({
        null: {_e('Ume', 'Ub')},
      });
    await _pumpGraphBody(
      tester,
      size: const Size(360, 800),
      source: source,
    );

    await tester.tap(find.byType(GraphNodeWidget).at(1));
    await tester.pump();

    expect(find.byKey(TestIds.key(TestIds.graphExpand)), findsNothing);
  });

  testWidgets('reset clears trail focus and recenters', (tester) async {
    final source = _WidgetTestGraphSource()
      ..pages.addAll({
        null: {_e('Ume', 'Ub')},
        'Ub': {_e('Ub', 'Ue')},
      });
    final cubit = await _pumpGraphBody(
      tester,
      size: const Size(360, 800),
      source: source,
    );

    await tester.tap(find.byType(GraphNodeWidget).at(1));
    await _settleGraph(tester);

    expect(cubit.state.focus, 'Ub');
    expect(cubit.state.focusPathDepth, greaterThan(1));

    await tester.tap(find.byKey(TestIds.key(TestIds.graphResetToEgo)));
    await _settleGraph(tester);

    expect(cubit.state.focus, isEmpty);
    expect(cubit.state.focusPathDepth, 1);
    expect(cubit.canPopFocus, isFalse);
    expect(cubit.focusPath, ['Ume']);
    expect(
      tester
          .widget<IconButton>(find.byKey(TestIds.key(TestIds.graphBack)))
          .onPressed,
      isNull,
    );
    expect(find.byKey(TestIds.key(TestIds.graphBack)), findsOneWidget);
  });

  testWidgets('previous focus decrements depth without refetch', (
    tester,
  ) async {
    final source = _WidgetTestGraphSource()
      ..pages.addAll({
        null: {_e('Ume', 'Ub')},
        'Ub': {_e('Ub', 'Ue')},
      });
    final cubit = await _pumpGraphBody(
      tester,
      size: const Size(360, 800),
      source: source,
    );

    await tester.tap(find.byType(GraphNodeWidget).at(1));
    await _settleGraph(tester);
    final callsAfterFirstExpand = source.ubFetches;
    expect(
      tester
          .widget<IconButton>(find.byKey(TestIds.key(TestIds.graphBack)))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byType(GraphNodeWidget).at(2));
    await _settleGraph(tester);
    expect(cubit.state.focusPathDepth, 3);

    expect(find.byKey(TestIds.key(TestIds.graphBack)), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(TestIds.key(TestIds.graphBack)))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(TestIds.key(TestIds.graphBack)));
    await _settleGraph(tester);

    expect(cubit.state.focus, 'Ub');
    expect(cubit.state.focusPathDepth, 2);
    expect(source.ubFetches, callsAfterFirstExpand);
  });

  testWidgets('fit current path is available after layout settles', (
    tester,
  ) async {
    final source = _WidgetTestGraphSource()
      ..pages.addAll({
        null: {_e('Ume', 'Ub')},
      });
    await _pumpGraphBody(
      tester,
      size: const Size(360, 800),
      source: source,
    );

    expect(find.byKey(TestIds.key(TestIds.graphFit)), findsOneWidget);
    await tester.tap(find.byKey(TestIds.key(TestIds.graphFit)));
    await _settleGraph(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact focus exposes expand and home in app bar',
    (tester) async {
      final source = _WidgetTestGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub')},
        });
      await _pumpGraphBody(
        tester,
        size: const Size(360, 800),
        source: source,
      );

      await tester.tap(find.byType(GraphNodeWidget).at(1));
      await _settleGraph(tester);

      expect(find.byKey(TestIds.key(TestIds.graphExpand)), findsOneWidget);
      expect(find.byTooltip('Reset to me'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow width toolbar does not overflow after focus with expand',
    (tester) async {
      final source = _WidgetTestGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub')},
        });
      await _pumpGraphBody(
        tester,
        size: const Size(320, 800),
        source: source,
      );

      await tester.tap(find.byType(GraphNodeWidget).at(1));
      await _settleGraph(tester);

      expect(find.byKey(TestIds.key(TestIds.graphExpand)), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'focused node keeps Profile after neighbourhood is fully paged',
    (tester) async {
      // Use Uc (not Ub): this file's stub pages Ub as a partial window.
      final source = _WidgetTestGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Uc', dstTotal: 1)},
          'Uc': {_e('Uc', 'Ue')},
        });
      final cubit = await _pumpGraphBody(
        tester,
        size: const Size(900, 600),
        source: source,
      );

      await tester.tap(find.byType(GraphNodeWidget).at(1));
      await _settleGraph(tester);

      expect(cubit.state.focus, 'Uc');
      expect(cubit.canPageMore('Uc'), isFalse);
      expect(find.byKey(TestIds.key(TestIds.graphOpenDetails)), findsOneWidget);
      expect(find.byTooltip('Profile'), findsOneWidget);
      expect(find.byKey(TestIds.key(TestIds.graphExpand)), findsNothing);
    },
  );
}
