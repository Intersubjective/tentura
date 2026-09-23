import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_graph_scene.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/features/graph/ui/utils/tentura_layout_algorithms.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 9, 11, 12);

ConstellationAnchor _anchor({
  required String personId,
  BigInt? revision,
  double x = 1,
  double y = 2,
}) =>
    ConstellationAnchor(
      target: ConstellationAnchorTarget.person(personId),
      position: ConstellationAnchorPosition(
        xUnits: x,
        yUnits: y,
        coordinateSpaceVersion: 1,
      ),
      revision: ConstellationAnchorRevision(revision ?? BigInt.one),
      placedAt: _loadedAt,
    );

ConstellationField _field({
  List<ConstellationPerson> peers = const [
    ConstellationPerson(id: 'p1', displayName: 'Peer'),
  ],
  List<ConstellationAnchor> anchors = const [],
}) =>
    ConstellationField(
      loadedAt: _loadedAt,
      context: '',
      peers: peers,
      requests: const [],
      anchorProjection: ConstellationAnchorProjection(
        revision: ConstellationAnchorRevision(BigInt.one),
        anchors: anchors,
        pinnedPeers: peers,
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );

final class _HarnessFieldRepository implements ConstellationRepositoryPort {
  _HarnessFieldRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      field;
}

final class _HarnessAnchorRepository implements ConstellationAnchorRepositoryPort {
  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async =>
      ConstellationAnchorUpsertResult(
        anchor: ConstellationAnchor(
          target: target,
          position: position,
          revision: ConstellationAnchorRevision(BigInt.two),
          placedAt: _loadedAt,
        ),
        revision: ConstellationAnchorRevision(BigInt.two),
      );

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) async =>
      ConstellationAnchorDeleteResult(
        target: target,
        revision: ConstellationAnchorRevision(BigInt.from(3)),
      );
}

final class _FakeForwardRepository implements ForwardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  void clearSelection() {}
}

Future<ConstellationCubit> _loadedCubitForField(ConstellationField field) async {
  final sync = buildTestRealtimeSync();
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      _HarnessFieldRepository(field),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationSceneHandoffTest'),
    ),
    anchorCase: ConstellationAnchorCase(
      _HarnessFieldRepository(field),
      _HarnessAnchorRepository(),
      sync.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationSceneHandoffTest'),
    ),
    viewer: _ego,
    forwardRepository: _FakeForwardRepository(),
    loadOnCreate: false,
  );
  await cubit.load();
  return cubit;
}

ConstellationField _overlappingPinnedField() {
  const peer = ConstellationPerson(id: 'p1', displayName: 'Peer');
  const request = ConstellationRequest(
    id: 'B-overlap',
    authorId: 'p1',
    title: 'Overlap',
    status: 0,
  );
  final placedAt = _loadedAt;
  return ConstellationField(
    loadedAt: _loadedAt,
    context: '',
    peers: [peer],
    requests: [request],
    edges: const [
      ConstellationTrustEdgeEntity(src: 'ego', dst: 'p1', tier: 1),
    ],
    anchorProjection: ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision(BigInt.one),
      anchors: [
        ConstellationAnchor(
          target: ConstellationAnchorTarget.person('p1'),
          position: const ConstellationAnchorPosition(
            xUnits: 2.5,
            yUnits: 2.5,
            coordinateSpaceVersion: 1,
          ),
          revision: ConstellationAnchorRevision(BigInt.one),
          placedAt: placedAt,
        ),
        ConstellationAnchor(
          target: ConstellationAnchorTarget.beacon('B-overlap'),
          position: const ConstellationAnchorPosition(
            xUnits: 2.5,
            yUnits: 2.5,
            coordinateSpaceVersion: 1,
          ),
          revision: ConstellationAnchorRevision(BigInt.two),
          placedAt: placedAt.add(const Duration(seconds: 1)),
        ),
      ],
      pinnedPeers: [peer],
      pinnedRequests: [request],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

Future<ConstellationCubit> _loadedCubit() async {
  return _loadedCubitForField(
    _field(
      anchors: [_anchor(personId: 'p1')],
    ),
  );
}

Future<void> _pumpConstellationMap(
  WidgetTester tester,
  ConstellationCubit cubit,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ConstellationCubit>.value(value: cubit),
            BlocProvider<GraphPersonContextCubit>(
              create: (_) => _StubContextCubit(),
            ),
            BlocProvider<ScreenCubit>(
              create: (_) => ScreenCubit(FakeUiEffectPort()),
            ),
          ],
          child: Scaffold(
            body: ConstellationBody(
              legendExpanded: false,
              onToggleLegend: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void _requestLayoutHandoff(
  ConstellationCubit cubit, {
  required GraphNodeId handoffGraphId,
  required SceneLayoutAlgorithm algorithm,
}) {
  cubit.testSceneLayoutAlgorithmOverride = algorithm;
  cubit.requestConstellationLayoutForTest(
    algorithm: algorithm,
    bumpGraphRevision: false,
  );
}

final class _TerminalAtAlgorithm implements SceneLayoutAlgorithm {
  _TerminalAtAlgorithm(this.positions);

  final Map<GraphNodeId, ScenePoint> positions;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: positions,
      isTerminal: true,
    );
  }
}

final class _MalformedThenTerminalAlgorithm implements SceneLayoutAlgorithm {
  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: {
        for (final id in request.nodeIds)
          if (id != request.nodeIds.first) id: ScenePoint(x: 0, y: 0),
      },
      isTerminal: false,
    );
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 1,
      positions: {
        for (final id in request.nodeIds) id: ScenePoint(x: 5, y: 5),
      },
      isTerminal: true,
    );
  }
}

final class _SlowLayoutAlgorithm implements SceneLayoutAlgorithm {
  final completer = Completer<void>();

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: {
        for (final id in request.nodeIds) id: ScenePoint(x: 1, y: 1),
      },
      isTerminal: false,
    );
    await completer.future;
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 1,
      positions: {
        for (final id in request.nodeIds) id: ScenePoint(x: 9, y: 9),
      },
      isTerminal: true,
    );
  }
}

Future<void> _settleLayout(
  WidgetTester tester,
  GraphSceneController<NodeDetails, EdgeDetails> scene,
) async {
  for (var i = 0; i < 50; i++) {
    if (scene.layoutOutcome is! GraphLayoutOutcomeRunning) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
}

void main() {
  group('constellation map selection', () {
    testWidgets('overlapping pinned beacon tap selects request', (tester) async {
      final cubit = await _loadedCubitForField(_overlappingPinnedField());
      addTearDown(cubit.close);
      await _pumpConstellationMap(tester, cubit);

      final topmost = cubit.orderedNodesForPaint().reversed.firstWhere(
        (node) => node.id == 'B-overlap' || node.id == 'p1',
      );
      expect(
        cubit.anchorTargetForNode(topmost),
        ConstellationAnchorTarget.beacon('B-overlap'),
      );

      final graphId = constellationGraphNodeIdForTarget(
        ConstellationAnchorTarget.beacon('B-overlap'),
      );
      final point = cubit.graphController.renderSnapshot.resolvePosition(graphId);
      expect(point, isNotNull);
      cubit.selectMapNodeAtSceneCentre(Offset(point!.x, point.y));
      await tester.pump(const Duration(milliseconds: 300));

      expect(cubit.state.selectedRequestId, 'B-overlap');
      expect(cubit.state.selectedPersonId, isNull);
    });
  });

  group('constellation placement handoff', () {
    testWidgets('successful drop releases presentation on terminal layout',
        (tester) async {
      final cubit = await _loadedCubit();
      addTearDown(cubit.close);
      await _pumpConstellationMap(tester, cubit);

      final target = ConstellationAnchorTarget.person('p1');
      final graphId = constellationGraphNodeIdForTarget(target);
      final controller = cubit.graphController;
      expect(controller.canLayout, isTrue);

      const dragCentre = Offset(3000, 2800);
      cubit.beginDragExisting(target: target);
      cubit.updateDragPresentation(
        nodeId: target.graphNodeId,
        sceneCentre: dragCentre,
      );
      await tester.pump();

      final token = controller.activePresentationTokenForNode(graphId);
      expect(token, isNotNull);
      final dragPoint = controller.renderSnapshot.resolvePosition(graphId);
      expect(dragPoint, isNotNull);
      expect(dragPoint!.x, closeTo(dragCentre.dx, 1));
      expect(dragPoint.y, closeTo(dragCentre.dy, 1));

      var notifications = 0;
      GraphSceneSnapshot<NodeDetails, EdgeDetails>? lastSnapshot;
      controller.addListener(() {
        notifications++;
        lastSnapshot = controller.renderSnapshot;
      });

      await cubit.onExistingNodeDrop(
        target: target,
        sceneCentre: dragCentre,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(controller.activePresentationTokenForNode(graphId), isNull);
      expect(
        controller.renderSnapshot.presentation.overrides.containsKey(graphId),
        isFalse,
      );
      expect(controller.scene.layoutOutcome, isA<GraphLayoutOutcomeSucceeded>());
      expect(lastSnapshot, isNotNull);
      expect(
        lastSnapshot!.presentation.overrides.containsKey(graphId),
        isFalse,
      );
      expect(notifications, greaterThanOrEqualTo(1));
    });

    testWidgets('layout failure keeps drag presentation override', (tester) async {
      final cubit = await _loadedCubit();
      addTearDown(cubit.close);
      await _pumpConstellationMap(tester, cubit);

      final target = ConstellationAnchorTarget.person('p1');
      final graphId = constellationGraphNodeIdForTarget(target);
      final controller = cubit.graphController;
      final node = controller.nodePayloadForId(graphId);
      expect(node, isNotNull);

      const dragCentre = Offset(2500, 2600);
      final token = controller.beginNodePresentationDragForId(graphId, dragCentre);

      _requestLayoutHandoff(
        cubit,
        handoffGraphId: graphId,
        algorithm: _MalformedThenTerminalAlgorithm(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await _settleLayout(tester, controller.scene);

      expect(controller.scene.layoutOutcome, isA<GraphLayoutOutcomeFailed>());
      expect(controller.activePresentationTokenForNode(graphId), token);
      final held = controller.renderSnapshot.resolvePosition(graphId);
      expect(held!.x, closeTo(dragCentre.dx, 1));
      expect(held.y, closeTo(dragCentre.dy, 1));
    });

    testWidgets('superseding layout does not release presentation override',
        (tester) async {
      final cubit = await _loadedCubit();
      addTearDown(cubit.close);
      await _pumpConstellationMap(tester, cubit);

      final graphId = constellationGraphNodeIdForTarget(
        ConstellationAnchorTarget.person('p1'),
      );
      final controller = cubit.graphController;
      final node = controller.nodePayloadForId(graphId)!;
      const dragCentre = Offset(2400, 2500);
      final token = controller.beginNodePresentationDragForId(graphId, dragCentre);

      final slow = _SlowLayoutAlgorithm();
      _requestLayoutHandoff(
        cubit,
        handoffGraphId: graphId,
        algorithm: slow,
      );

      final supersedingSlow = _SlowLayoutAlgorithm();
      _requestLayoutHandoff(
        cubit,
        handoffGraphId: graphId,
        algorithm: supersedingSlow,
      );
      await tester.pump(const Duration(milliseconds: 30));

      expect(controller.activePresentationTokenForNode(graphId), token);
      expect(
        controller.renderSnapshot.presentation.overrides[graphId],
        ScenePoint(x: 2400, y: 2500),
      );

      expect(controller.cancelNodePresentationDrag(token), isTrue);
      expect(controller.renderSnapshot.presentation.overrides, isEmpty);

      slow.completer.complete();
      supersedingSlow.completer.complete();
      await _settleLayout(tester, controller.scene);
    });

    testWidgets(
      'reconcileTopology refreshes payload by id without moving camera while dragging',
      (tester) async {
        final cubit = await _loadedCubit();
        addTearDown(cubit.close);
        await _pumpConstellationMap(tester, cubit);

        final controller = cubit.graphController;
        const panTarget = Offset(2800, 2200);
        controller.jumpToPosition(panTarget);
        await tester.pump();

        final screenBefore = controller.sceneToViewportLocal(panTarget);
        final target = ConstellationAnchorTarget.person('p1');
        final graphId = constellationGraphNodeIdForTarget(target);
        cubit.beginDragExisting(target: target);
        cubit.updateDragPresentation(
          nodeId: target.graphNodeId,
          sceneCentre: const Offset(3000, 2900),
        );
        await tester.pump();
        expect(controller.activePresentationTokenForNode(graphId), isNotNull);

        final peer = controller.nodes.singleWhere(
          (n) => n.id == 'p1',
        ) as FieldPersonNode;
        final refreshedPeer = FieldPersonNode(
          person: Profile(id: 'p1', displayName: 'Renamed peer'),
          ring: peer.ring,
          isKept: peer.isKept,
        );
        controller.reconcileTopology(
          {
            for (final n in controller.nodes)
              if (n.id == 'p1') refreshedPeer else n,
          },
          controller.edges.toSet(),
          requestLayout: false,
          layoutOnTopologyChange: false,
        );
        await tester.pump();

        final updated = controller.nodes.singleWhere(
          (n) => n.id == 'p1',
        ) as FieldPersonNode;
        expect(updated.person.displayName, 'Renamed peer');
        expect(controller.activePresentationTokenForNode(graphId), isNotNull);
        final screenAfter = controller.sceneToViewportLocal(panTarget);
        expect(screenAfter.dx, closeTo(screenBefore.dx, 1));
        expect(screenAfter.dy, closeTo(screenBefore.dy, 1));
      },
    );
  });
}
