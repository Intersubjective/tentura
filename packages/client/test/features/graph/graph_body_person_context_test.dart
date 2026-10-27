import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/graph_mode.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';

import 'scene_layout_test_support.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_body.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_panel.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/features/graph/ui/widget/graph_scaffold.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/graph_trust_write_fixture.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../../support/people_tags_widget_harness.dart';

class _WidgetTestGraphSource implements GraphSourceRepository {
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
    Set<String> excludeNeighborIds = const {},
  }) async {
    calls += 1;
    return pages[focus] ?? const {};
  }

  @override
  Future<Set<EdgeDirected>> fetchEdgesBetween({
    required Set<String> nodeIds,
    bool positiveOnly = true,
  }) async => const {};
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  final _changes = StreamController<RepositoryEvent<Profile>>.broadcast();

  @override
  Stream<RepositoryEvent<Profile>> get changes => _changes.stream;

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

class _TrackingForwardsCubit extends Cubit<GraphState> implements GraphCubit {
  _TrackingForwardsCubit()
    : super(const GraphState(me: _me, focus: '', isAnimated: false));

  @override
  final bool genealogyMode = false;

  @override
  final String? forwardsGraphBeaconId = 'Btest';

  @override
  GraphMode get mode => GraphMode.forwards;

  @override
  final graphController = testGraphController();

  @override
  Set<String> get forwardsRootIds => const {};

  @override
  String get originNodeId => _me.id;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _GenealogyStubCubit extends Cubit<GraphState> implements GraphCubit {
  _GenealogyStubCubit()
    : super(const GraphState(me: _me, focus: '', isAnimated: false));

  @override
  final bool genealogyMode = true;

  @override
  final String? forwardsGraphBeaconId = null;

  @override
  GraphMode get mode => GraphMode.genealogy;

  @override
  final graphController = testGraphController();

  @override
  Set<String> get forwardsRootIds => const {};

  @override
  String get originNodeId => _me.id;

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

EdgeDirected _e(
  String src,
  String dst, {
  Profile? user,
  int? dstTotal,
}) => (
  src: src,
  dst: dst,
  weight: 1.0,
  node: UserNode(
    user: user ?? Profile(id: dst, displayName: dst),
  ),
  branch: null,
  srcTotalNeighborCount: null,
  dstTotalNeighborCount: dstTotal,
);

Future<void> _settleGraph(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Rect _globalRect(WidgetTester tester, Finder finder) {
  final elements = finder.evaluate();
  expect(elements, isNotEmpty);
  final target = elements.first.renderObject! as RenderBox;
  return MatrixUtils.transformRect(
    target.getTransformTo(null),
    Offset.zero & target.size,
  );
}

Future<void> _tapPeerNode(WidgetTester tester, {String? userId}) async {
  if (userId != null) {
    await tester.tap(find.byKey(TestIds.key(TestIds.graphNode(userId))));
  } else {
    await tester.tap(find.byType(GraphNodeWidget).at(1));
  }
  await _settleGraph(tester);
}

Finder _legendBoundsFinder() {
  final legend = find.byType(GraphLegendPanel);
  final scrollView = find.ancestor(
    of: legend,
    matching: find.byType(SingleChildScrollView),
  );
  if (scrollView.evaluate().isNotEmpty) {
    return scrollView;
  }
  return legend;
}

Future<void> _intentionalSelectUser({
  required ({
    GraphCubit graphCubit,
    GraphPersonContextCubit contextCubit,
    _WidgetTestGraphSource source,
  })
  harness,
  required WidgetTester tester,
  required String userId,
}) async {
  final node = harness.graphCubit.graphController.nodes
      .whereType<UserNode>()
      .firstWhere((n) => n.id == userId);
  harness.graphCubit.handleNodeTap(node);
  harness.contextCubit.selectProfile(node.user, intentional: true);
  await _settleGraph(tester);
}

Future<
  ({
    GraphCubit graphCubit,
    GraphPersonContextCubit contextCubit,
    _WidgetTestGraphSource source,
  })
>
_pumpTrustGraphBody(
  WidgetTester tester, {
  required Size size,
  bool legendExpanded = true,
  Map<String?, Set<EdgeDirected>>? pages,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final source = _WidgetTestGraphSource();
  if (pages != null) {
    source.pages.addAll(pages);
  }
  final graphCubit = GraphCubit(
    me: _me,
    graphSourceRepository: source,
    edgeColors: _edgeColors,
    beaconRepository: _FakeBeaconRepository(),
    profileRepository: _FakeProfileRepository(),
    effects: FakeUiEffectPort(),
  );
  graphCubit.emit(graphCubit.state.copyWith(isAnimated: false));
  final trustFixture = GraphTrustWriteFixture(
    profileRepository: _FakeProfileRepository(),
  );
  final contextCubit = trustFixture.createCubit(
    profileViewCase: trustFixture.profileViewCase,
    viewerId: _me.id,
    onProfilePatched: graphCubit.patchLoadedProfile,
  );
  addTearDown(graphCubit.close);
  addTearDown(trustFixture.dispose);

  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<GraphCubit>.value(value: graphCubit),
              BlocProvider<GraphPersonContextCubit>.value(
                value: contextCubit,
              ),
              BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
              BlocProvider<ProfileCubit>.value(value: _FakeProfileCubit()),
            ],
            child: const GraphScaffold(
              personContextEnabled: true,
              title: Text('Graph'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await _settleGraph(tester);

  if (legendExpanded) {
    await tester.tap(find.byIcon(Icons.legend_toggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  return (
    graphCubit: graphCubit,
    contextCubit: contextCubit,
    source: source,
  );
}

void main() {
  group('GraphBody person context', () {
    testWidgets('trust toggle shows the new value while the write is pending', (
      tester,
    ) async {
      await _pumpTrustGraphBody(
        tester,
        size: const Size(900, 600),
        pages: {
          null: {_e('Ume', 'Ub')},
        },
      );
      await _tapPeerNode(tester, userId: 'Ub');
      final toggle = find.byKey(TestIds.key(TestIds.graphPersonContextTrust));
      await tester.tap(toggle);
      await tester.pump();
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(tester.widget<Switch>(toggle).onChanged, isNotNull);
    });

    testWidgets('new node selection opens panel without profile refetch', (
      tester,
    ) async {
      final harness = await _pumpTrustGraphBody(
        tester,
        size: const Size(900, 600),
        pages: {
          null: {
            _e(
              'Ume',
              'Ub',
              user: const Profile(id: 'Ub', displayName: 'Bob'),
            ),
          },
          'Ub': {_e('Ub', 'Ue')},
        },
      );

      final graphSizeBefore = tester.getSize(find.byType(TenturaFullBleed));
      await _tapPeerNode(tester, userId: 'Ub');

      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        findsOneWidget,
      );
      expect(find.text('Bob'), findsWidgets);
      expect(harness.contextCubit.state.selectedProfile?.id, 'Ub');
      expect(
        tester.getSize(find.byType(TenturaFullBleed)),
        equals(graphSizeBefore),
      );
    });

    testWidgets('visited node rollback opens panel without extra fetch', (
      tester,
    ) async {
      final harness = await _pumpTrustGraphBody(
        tester,
        size: const Size(900, 600),
        legendExpanded: false,
        pages: {
          null: {_e('Ume', 'Ub')},
          'Ub': {_e('Ub', 'Ue')},
        },
      );

      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('Ub'))));
      await _settleGraph(tester);
      final callsAfterExpand = harness.source.calls;

      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('Ume'))));
      await _settleGraph(tester);

      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('Ub'))));
      await _settleGraph(tester);

      expect(harness.source.calls, callsAfterExpand);
      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        findsOneWidget,
      );
    });

    testWidgets('dismiss leaves graph focus and hides panel', (tester) async {
      final harness = await _pumpTrustGraphBody(
        tester,
        size: const Size(900, 600),
        legendExpanded: false,
        pages: {
          null: {_e('Ume', 'Ub')},
        },
      );

      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('Ub'))));
      await _settleGraph(tester);
      expect(harness.graphCubit.state.focus, 'Ub');

      await tester.tap(
        find.byKey(TestIds.key(TestIds.graphPersonContextClose)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        findsNothing,
      );
      expect(harness.graphCubit.state.focus, 'Ub');
      expect(harness.contextCubit.state.dismissedFocusId, 'Ub');
    });

    testWidgets('intentional same-node tap reopens dismissed panel', (
      tester,
    ) async {
      await _pumpTrustGraphBody(
        tester,
        size: const Size(900, 600),
        legendExpanded: false,
        pages: {
          null: {_e('Ume', 'Ub', dstTotal: 1)},
          'Ub': {_e('Ub', 'Ue')},
        },
      );

      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('Ub'))));
      await _settleGraph(tester);
      await tester.tap(
        find.byKey(TestIds.key(TestIds.graphPersonContextClose)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('Ub'))));
      await _settleGraph(tester);

      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        findsOneWidget,
      );
    });

    testWidgets('Previous follows focus into panel', (tester) async {
      final harness = await _pumpTrustGraphBody(
        tester,
        size: const Size(900, 600),
        legendExpanded: false,
        pages: {
          null: {_e('Ume', 'Ub')},
          'Ub': {
            _e(
              'Ub',
              'Ue',
              user: const Profile(id: 'Ue', displayName: 'Eve'),
            ),
          },
        },
      );

      final ub = harness.graphCubit.graphController.nodes.firstWhere(
        (n) => n.id == 'Ub',
      );
      await harness.graphCubit.expandNode(ub);
      await _settleGraph(tester);
      final ue = harness.graphCubit.graphController.nodes.firstWhere(
        (n) => n.id == 'Ue',
      );
      harness.graphCubit.selectNode(ue);
      await _settleGraph(tester);
      expect(find.text('Eve'), findsWidgets);

      await tester.tap(find.byKey(TestIds.key(TestIds.graphBack)));
      await _settleGraph(tester);

      expect(harness.graphCubit.state.focus, 'Ub');
      expect(find.text('Ub'), findsWidgets);
      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        findsOneWidget,
      );
    });

    testWidgets('Reset hides panel', (tester) async {
      final harness = await _pumpTrustGraphBody(
        tester,
        size: const Size(900, 600),
        legendExpanded: false,
        pages: {
          null: {_e('Ume', 'Ub')},
        },
      );

      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('Ub'))));
      await _settleGraph(tester);
      await tester.tap(find.byKey(TestIds.key(TestIds.graphResetToEgo)));
      await _settleGraph(tester);

      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        findsNothing,
      );
      expect(harness.contextCubit.state.selectedProfile, isNull);
    });

    testWidgets('forwards and genealogy never show person context panel', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final cubit in [
        _TrackingForwardsCubit(),
        _GenealogyStubCubit(),
      ]) {
        addTearDown(cubit.close);
        await tester.pumpPeopleTagsWidget(
          MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: BlocProvider<GraphCubit>.value(
              value: cubit,
              child: GraphBody(
                legendExpanded: false,
                onToggleLegend: () {},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
          findsNothing,
        );
      }
    });

    testWidgets('compact 320x800 layout avoids overflow', (tester) async {
      await _pumpTrustGraphBody(
        tester,
        size: const Size(320, 800),
        legendExpanded: false,
        pages: {
          null: {
            _e(
              'Ume',
              'Ub',
              user: const Profile(
                id: 'Ub',
                displayName: 'Long Name Person',
                score: 1,
                rScore: 1,
              ),
            ),
          },
        },
      );

      await _tapPeerNode(tester, userId: 'Ub');

      final panel = find.byKey(TestIds.key(TestIds.graphPersonContextPanel));
      expect(panel, findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(panel).height,
        lessThanOrEqualTo(800 * 0.42 + 64),
      );
    });

    testWidgets('wide 900x600 layout uses token width without overflow', (
      tester,
    ) async {
      await _pumpTrustGraphBody(
        tester,
        size: const Size(900, 600),
        legendExpanded: false,
        pages: {
          null: {
            _e(
              'Ume',
              'Ub',
              user: const Profile(
                id: 'Ub',
                displayName: 'Wide Layout Person',
                score: 1,
                rScore: 1,
              ),
            ),
          },
        },
      );

      await _tapPeerNode(tester, userId: 'Ub');

      final panel = find.byKey(TestIds.key(TestIds.graphPersonContextPanel));
      expect(panel, findsOneWidget);
      expect(tester.getSize(panel).width, 320);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'compact panel open moves legend to upper-left without overlap',
      (
        tester,
      ) async {
        final harness = await _pumpTrustGraphBody(
          tester,
          size: const Size(320, 800),
          pages: {
            null: {_e('Ume', 'Ub')},
          },
        );

        final legendClosed = _globalRect(tester, _legendBoundsFinder());

        await _intentionalSelectUser(
          harness: harness,
          tester: tester,
          userId: 'Ub',
        );

        final legendOpen = _globalRect(tester, _legendBoundsFinder());
        final panel = _globalRect(
          tester,
          find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        );
        expect(legendOpen.top, lessThan(panel.top));
        expect(legendOpen.bottom, lessThanOrEqualTo(panel.top));
        expect(legendOpen.top, lessThan(legendClosed.top));
      },
    );

    testWidgets('focus change swaps panel identity immediately', (
      tester,
    ) async {
      final harness = await _pumpTrustGraphBody(
        tester,
        size: const Size(900, 600),
        legendExpanded: false,
        pages: {
          null: {_e('Ume', 'Ub')},
          'Ub': {
            _e(
              'Ub',
              'Ue',
              user: const Profile(id: 'Ue', displayName: 'Eve'),
            ),
          },
        },
      );

      final ub = harness.graphCubit.graphController.nodes.firstWhere(
        (n) => n.id == 'Ub',
      );
      await harness.graphCubit.expandNode(ub);
      await _settleGraph(tester);

      await _intentionalSelectUser(
        harness: harness,
        tester: tester,
        userId: 'Ue',
      );
      expect(find.text('Eve'), findsWidgets);

      await _intentionalSelectUser(
        harness: harness,
        tester: tester,
        userId: 'Ub',
      );
      expect(find.text('Ub'), findsWidgets);
      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        findsOneWidget,
      );
    });

    testWidgets('different selection reopens dismissed panel', (tester) async {
      final harness = await _pumpTrustGraphBody(
        tester,
        size: const Size(900, 600),
        legendExpanded: false,
        pages: {
          null: {_e('Ume', 'Ub')},
          'Ub': {
            _e(
              'Ub',
              'Ue',
              user: const Profile(id: 'Ue', displayName: 'Eve'),
            ),
          },
        },
      );

      await _tapPeerNode(tester, userId: 'Ub');
      await tester.tap(
        find.byKey(TestIds.key(TestIds.graphPersonContextClose)),
      );
      await tester.pump();

      final ub = harness.graphCubit.graphController.nodes.firstWhere(
        (n) => n.id == 'Ub',
      );
      await harness.graphCubit.expandNode(ub);
      await _settleGraph(tester);

      await _intentionalSelectUser(
        harness: harness,
        tester: tester,
        userId: 'Ue',
      );
      expect(find.text('Eve'), findsWidgets);
      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        findsOneWidget,
      );
    });

    testWidgets('expanded node reselect keeps panel without extra fetch', (
      tester,
    ) async {
      final harness = await _pumpTrustGraphBody(
        tester,
        size: const Size(900, 600),
        legendExpanded: false,
        pages: {
          null: {_e('Ume', 'Ub', dstTotal: 1)},
          'Ub': {_e('Ub', 'Ue')},
        },
      );

      await _tapPeerNode(tester, userId: 'Ub');
      final callsAfterExpand = harness.source.calls;

      await _tapPeerNode(tester, userId: 'Ub');
      expect(harness.source.calls, callsAfterExpand);
      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        findsOneWidget,
      );
    });

    testWidgets('self and beacon focus hide person context panel', (
      tester,
    ) async {
      final harness = await _pumpTrustGraphBody(
        tester,
        size: const Size(900, 600),
        legendExpanded: false,
        pages: {
          null: {_e('Ume', 'Ub')},
        },
      );

      await _tapPeerNode(tester, userId: 'Ub');
      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        findsOneWidget,
      );

      await _tapPeerNode(tester, userId: 'Ume');
      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        findsNothing,
      );

      await _tapPeerNode(tester, userId: 'Ub');
      final beaconNode = BeaconNode(
        beacon: Beacon(
          id: 'Btest',
          title: 'Test request',
          createdAt: DateTime.utc(2024),
          updatedAt: DateTime.utc(2024),
        ),
      );
      harness.graphCubit.graphController.reconcileTopology(
        {...harness.graphCubit.graphController.nodes, beaconNode},
        harness.graphCubit.graphController.edges,
      );
      harness.graphCubit.selectNode(beaconNode);
      await _settleGraph(tester);

      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        findsNothing,
      );
    });

    // #615: on an iPhone SE the sheet covered the node that was tapped.
    testWidgets('compact sheet on 375x667 keeps the tapped node above it', (
      tester,
    ) async {
      final harness = await _pumpTrustGraphBody(
        tester,
        size: const Size(375, 667),
        legendExpanded: false,
        pages: {
          null: {_e('Ume', 'Ub')},
        },
      );
      final controller = harness.graphCubit.graphController;
      final ub = controller.nodes.singleWhere((n) => n.id == 'Ub');
      final ubFinder = find.byKey(TestIds.key(TestIds.graphNode('Ub')));

      // Pan so Bob sits near the bottom of the canvas, where the sheet opens.
      final viewport = controller.viewportSize!;
      final bob = controller.getPositionForId(ub.graphNodeId);
      controller.jumpToPosition(
        bob - Offset(0, (viewport.height / 2 - 90) / controller.cameraScale),
      );
      await tester.pump();
      final before = tester.getRect(ubFinder);

      await _tapPeerNode(tester, userId: 'Ub');

      final panel = _globalRect(
        tester,
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
      );
      // Guard: the node was where the sheet now is.
      expect(before.bottom, greaterThan(panel.top));
      final after = tester.getRect(ubFinder);
      expect(after.bottom, lessThanOrEqualTo(panel.top));
      expect(after.top, greaterThanOrEqualTo(0));
      expect(after.size, before.size);
      expect(tester.takeException(), isNull);
    });

    // #615: Escape left the Graph screen panel open (the Field closes it).
    testWidgets('Escape closes the panel and puts focus back on the node', (
      tester,
    ) async {
      await _pumpTrustGraphBody(
        tester,
        size: const Size(900, 600),
        legendExpanded: false,
        pages: {
          null: {_e('Ume', 'Ub')},
        },
      );
      final panel = find.byKey(TestIds.key(TestIds.graphPersonContextPanel));
      final ubMarker = find.descendant(
        of: find.byKey(TestIds.key(TestIds.graphNode('Ub'))),
        matching: find.byType(GestureDetector),
      );
      final ubFocus = Focus.of(tester.element(ubMarker.first));

      // Keyboard: focus Bob, Enter opens his panel, Tab goes into it.
      ubFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settleGraph(tester);
      expect(panel, findsOneWidget);
      final close = find.byKey(TestIds.key(TestIds.graphPersonContextClose));
      Focus.of(
        tester.element(
          find.descendant(of: close, matching: find.byIcon(Icons.close)),
        ),
      ).requestFocus();
      await tester.pump();
      expect(ubFocus.hasPrimaryFocus, isFalse);
      expect(close, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settleGraph(tester);

      expect(panel, findsNothing);
      // Bob stays the focus of the graph, and keyboard focus is back on him.
      final markerFocus = Focus.of(tester.element(ubMarker.first));
      expect(markerFocus.hasPrimaryFocus, isTrue);

      // Guard: with the panel closed, Escape changes nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settleGraph(tester);
      expect(panel, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
