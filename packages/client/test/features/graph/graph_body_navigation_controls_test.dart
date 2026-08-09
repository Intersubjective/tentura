import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/graph_mode.dart';
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

class _StubGraphCubit extends Cubit<GraphState> implements GraphCubit {
  _StubGraphCubit({
    this.genealogyMode = false,
    this.forwardsGraphBeaconId,
    String focus = '',
  }) : super(GraphState(me: _me, focus: focus, isAnimated: false));

  @override
  final bool genealogyMode;

  @override
  final String? forwardsGraphBeaconId;

  @override
  GraphMode get mode => forwardsGraphBeaconId != null
      ? GraphMode.forwards
      : genealogyMode
      ? GraphMode.genealogy
      : GraphMode.trust;

  @override
  final graphController =
      GraphController<NodeDetails, EdgeDetails<NodeDetails>>();

  @override
  bool get canPopFocus => state.focusPathDepth > 1;

  @override
  List<String> get focusPath => [
    _me.id,
    if (state.focus.isNotEmpty) state.focus,
  ];

  @override
  Set<String> get forwardsRootIds => const {};

  @override
  String get originNodeId => _me.id;

  @override
  void jumpToEgo({bool resetScale = false}) {}

  @override
  void popFocus() {}

  @override
  void resetToEgo() {}

  @override
  void fitCurrentPath() {}

  @override
  void togglePositiveOnly() {}

  @override
  void selectNode(NodeDetails node, {bool ensureStructuralEdges = true}) {}

  @override
  Future<void> expandNode(NodeDetails node) async {}

  @override
  bool canExpandNode(String id) => false;

  @override
  bool canPageMore(String id) => false;

  @override
  bool isCurrentFocus(String id) => state.focus == id;

  @override
  void handleNodeTap(NodeDetails node) {}

  @override
  bool hasEverFocused(String id) => false;

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

void _expectTrustModeControls(
  WidgetTester tester, {
  required bool focused,
}) {
  expect(find.byKey(TestIds.key(TestIds.graphBack)), findsOneWidget);
  expect(find.byKey(TestIds.key(TestIds.graphFit)), findsOneWidget);
  expect(find.byKey(TestIds.key(TestIds.graphResetToEgo)), findsOneWidget);
  expect(find.byTooltip('Reset to me'), findsOneWidget);
  expect(find.byIcon(Icons.map_outlined), findsOneWidget);
  expect(find.byKey(TestIds.key(TestIds.graphCenterView)), findsNothing);
  expect(find.byKey(TestIds.key(TestIds.graphExpand)), findsNothing);
  expect(find.byKey(TestIds.key(TestIds.graphOpenDetails)), findsNothing);
  if (!focused) {
    expect(
      tester
          .widget<IconButton>(find.byKey(TestIds.key(TestIds.graphBack)))
          .onPressed,
      isNull,
    );
  }
}

void _expectGenealogyModeControls(
  WidgetTester tester, {
  required bool withProfile,
}) {
  expect(find.byKey(TestIds.key(TestIds.graphBack)), findsOneWidget);
  expect(find.byKey(TestIds.key(TestIds.graphFit)), findsOneWidget);
  expect(find.byKey(TestIds.key(TestIds.graphResetToEgo)), findsOneWidget);
  expect(find.byTooltip('Reset to origin'), findsOneWidget);
  expect(find.byTooltip('Reset to me'), findsNothing);
  expect(find.byIcon(Icons.map_outlined), findsOneWidget);
  expect(find.byKey(TestIds.key(TestIds.graphCenterView)), findsNothing);
  expect(find.byKey(TestIds.key(TestIds.graphExpand)), findsNothing);
  expect(
    find.byKey(TestIds.key(TestIds.graphOpenDetails)),
    withProfile ? findsOneWidget : findsNothing,
  );
  if (withProfile) {
    expect(find.byTooltip('Profile'), findsOneWidget);
  }
}

void _expectForwardsModeControls(
  WidgetTester tester, {
  bool withProfile = false,
  bool withOpenBeacon = false,
}) {
  expect(find.byKey(TestIds.key(TestIds.graphCenterView)), findsOneWidget);
  expect(find.byIcon(Icons.map_outlined), findsOneWidget);
  expect(find.byKey(TestIds.key(TestIds.graphBack)), findsNothing);
  expect(find.byKey(TestIds.key(TestIds.graphFit)), findsNothing);
  expect(find.byKey(TestIds.key(TestIds.graphResetToEgo)), findsNothing);
  expect(find.byKey(TestIds.key(TestIds.graphExpand)), findsNothing);
  expect(
    find.byKey(TestIds.key(TestIds.graphOpenDetails)),
    withProfile || withOpenBeacon ? findsOneWidget : findsNothing,
  );
  if (withProfile) {
    expect(find.byTooltip('Profile'), findsOneWidget);
  }
  if (withOpenBeacon) {
    expect(find.byTooltip('Open Request'), findsOneWidget);
  }
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

Future<_StubGraphCubit> _pumpStubGraphBody(
  WidgetTester tester, {
  required _StubGraphCubit cubit,
  Size size = const Size(900, 600),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
  group('trust mode app bar controls', () {
    testWidgets('compact layout exposes navigation and legend only', (
      tester,
    ) async {
      await _pumpGraphBody(tester, size: const Size(360, 800));

      _expectTrustModeControls(tester, focused: false);

      final fitButton = tester.widget<IconButton>(
        find.byKey(TestIds.key(TestIds.graphFit)),
      );
      expect(find.byTooltip('Fit current path'), findsOneWidget);
      expect(fitButton.onPressed, isNotNull);
      expect(find.byTooltip('Show legend'), findsOneWidget);
    });

    testWidgets('expand is never shown in app bar', (tester) async {
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
      _expectTrustModeControls(tester, focused: true);

      await tester.tap(find.byKey(TestIds.key(TestIds.graphResetToEgo)));
      await _settleGraph(tester);

      expect(cubit.state.focus, isEmpty);
      expect(cubit.state.focusPathDepth, 1);
      expect(cubit.canPopFocus, isFalse);
      expect(cubit.focusPath, ['Ume']);
      _expectTrustModeControls(tester, focused: false);
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
      _expectTrustModeControls(tester, focused: true);

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

    testWidgets('compact focus keeps navigation controls without profile', (
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

      await tester.tap(find.byType(GraphNodeWidget).at(1));
      await _settleGraph(tester);

      _expectTrustModeControls(tester, focused: true);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow width toolbar does not overflow after focus', (
      tester,
    ) async {
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

      _expectTrustModeControls(tester, focused: true);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'focused node omits profile from app bar when neighbourhood is fully paged',
      (tester) async {
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
        _expectTrustModeControls(tester, focused: true);
      },
    );
  });

  group('genealogy mode app bar controls', () {
    testWidgets('expanded layout exposes genealogy navigation and legend', (
      tester,
    ) async {
      final cubit = _StubGraphCubit(genealogyMode: true);
      await _pumpStubGraphBody(tester, cubit: cubit);

      _expectGenealogyModeControls(tester, withProfile: false);
    });

    testWidgets('focused live user exposes profile in app bar', (tester) async {
      const liveUser = Profile(id: 'Upeer', displayName: 'Peer');
      final cubit = _StubGraphCubit(
        genealogyMode: true,
        focus: 'Gpeer',
      );
      cubit.graphController.mutate((mutator) {
        mutator.addNode(
          const GenealogyUserNode(nodeKey: 'Gpeer', user: liveUser),
        );
      });
      await _pumpStubGraphBody(tester, cubit: cubit);

      _expectGenealogyModeControls(tester, withProfile: true);
    });
  });

  group('forwards mode app bar controls', () {
    testWidgets('expanded layout exposes center view and legend only', (
      tester,
    ) async {
      final cubit = _StubGraphCubit(forwardsGraphBeaconId: 'Btest');
      await _pumpStubGraphBody(tester, cubit: cubit);

      _expectForwardsModeControls(tester);
    });

    testWidgets('focused user exposes profile in app bar', (tester) async {
      const peer = Profile(id: 'Upeer', displayName: 'Peer');
      final cubit = _StubGraphCubit(
        forwardsGraphBeaconId: 'Btest',
        focus: 'Upeer',
      );
      cubit.graphController.mutate((mutator) {
        mutator.addNode(UserNode(user: peer));
      });
      await _pumpStubGraphBody(tester, cubit: cubit);

      _expectForwardsModeControls(tester, withProfile: true);
    });

    testWidgets('focused beacon exposes open request in app bar', (
      tester,
    ) async {
      final cubit = _StubGraphCubit(
        forwardsGraphBeaconId: 'Btest',
        focus: 'Btest',
      );
      cubit.graphController.mutate((mutator) {
        mutator.addNode(
          BeaconNode(
            beacon: Beacon(
              id: 'Btest',
              title: 'Help needed',
              author: _me,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          ),
        );
      });
      await _pumpStubGraphBody(tester, cubit: cubit);

      _expectForwardsModeControls(tester, withOpenBeacon: true);
    });
  });
}
