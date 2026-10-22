// Removed members are probed through `dynamic` so the file compiles either way.
// ignore_for_file: avoid_dynamic_calls

import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

final _pinnedPerson = ConstellationAnchorTarget.person('am');
final _freePerson = ConstellationAnchorTarget.person('in');

ConstellationAnchor _anchor(
  ConstellationAnchorPosition position,
  int revision,
) => ConstellationAnchor(
  target: _pinnedPerson,
  position: position,
  revision: ConstellationAnchorRevision(BigInt.from(revision)),
  placedAt: DateTime.utc(2026, 9, 9),
);

const _pinnedAt = ConstellationAnchorPosition(
  xUnits: 0.2,
  yUnits: 0.3,
  coordinateSpaceVersion: 1,
);

final class _FieldRepository implements ConstellationRepositoryPort {
  _FieldRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

/// Holds every apply until the test acknowledges it, like a slow server.
final class _AnchorRepository implements ConstellationWriteFake {
  @override
  Future<ConstellationAnchorResetResult> reset({required String clientOpId}) =>
      throw UnimplementedError('reset is not used by this test');

  _AnchorRepository(this._confirmedBase);

  final ConstellationAnchorProjection _confirmedBase;
  final calls =
      <
        ({
          List<ConstellationAnchorApplyOp> ops,
          Completer<ConstellationAnchorApplyResult> reply,
        })
      >[];

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) {
    final reply = Completer<ConstellationAnchorApplyResult>();
    calls.add((ops: List.of(ops), reply: reply));
    return reply.future;
  }

  /// Acknowledges call [index] with the complete projection the server would
  /// hold afterwards: the same field content, revision 2, the ops applied.
  /// The server derives its pinned entities from the anchor rows, so an unpin
  /// takes its pinned peer or request with it.
  void ack(int index) {
    final call = calls[index];
    final anchors = {
      for (final anchor in _confirmedBase.anchors) anchor.target: anchor,
    };
    final deleted = <ConstellationAnchorTarget>{};
    for (final op in call.ops) {
      if (op.kind == ConstellationAnchorOpKind.delete) {
        anchors.remove(op.target);
        deleted.add(op.target);
      } else {
        anchors[op.target] = _anchor(op.position!, 2);
      }
    }
    final revision = ConstellationAnchorRevision(BigInt.two);
    call.reply.complete(
      ConstellationAnchorApplyResult(
        beforeRevision: _confirmedBase.revision,
        afterRevision: revision,
        results: [
          for (final op in call.ops)
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: ConstellationAnchorOpStatus.ok,
              resultingTargetRevision: revision,
              target: op.target,
              anchor: op.kind == ConstellationAnchorOpKind.delete
                  ? null
                  : anchors[op.target],
            ),
        ],
      ),
    );
  }

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) => throw StateError('Placement must use batched apply');

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) => throw StateError('Unpin must use batched apply');
}

typedef _Harness = ({
  ConstellationCubit cubit,
  ConstellationPlacementCase placement,
  _AnchorRepository server,
});

Future<_Harness> _mount(WidgetTester tester) async {
  final field = constellationReferenceField(
    anchors: [_anchor(_pinnedAt, 1)],
  );
  final server = _AnchorRepository(field.resolvedAnchorProjection);
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    _FieldRepository(field),
    accountId: 'ego',
    realtime: sync.case_,
  ).store;
  final placement = ConstellationPlacementCase(
    server,
    store,
    FakeClockPort(),
    FakeWakeUpPort(),
    realtime: sync.case_,
    env: const Env.fromEnvironment(),
    logger: Logger('ConstellationNodeDragAvailabilityTest'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    placementCase: placement,
    viewer: kRefEgo,
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  await pumpConstellationBody(tester, cubit, size: const Size(800, 700));
  return (cubit: cubit, placement: placement, server: server);
}

Future<void> _settleFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Drops the pinned person somewhere new and leaves the server unanswered.
Future<void> _dropPinnedPersonUnacknowledged(
  WidgetTester tester,
  _Harness harness,
) async {
  const dropCentre = Offset(240, 180);
  harness.cubit
    ..beginDragExisting(target: _pinnedPerson)
    ..updateDragPresentation(nodeId: 'fp:am', sceneCentre: dropCentre);
  await harness.cubit.onExistingNodeDrop(
    target: _pinnedPerson,
    sceneCentre: dropCentre,
  );
  await _settleFrames(tester);
  expect(harness.server.calls, hasLength(1));
}

/// What the camera shows: where a scene point lands plus the zoom.
({Offset origin, Offset probe, double scale}) _camera(
  ConstellationCubit cubit,
) {
  final controller = cubit.graphController;
  return (
    origin: controller.sceneToViewportLocal(Offset.zero),
    probe: controller.sceneToViewportLocal(const Offset(500, 500)),
    scale: controller.cameraScale,
  );
}

Finder _nodeFinder(ConstellationAnchorTarget target) =>
    find.byKey(TestIds.key(TestIds.graphNode(target.graphNodeId)));

void main() {
  group('Dragging a node while an earlier placement is unacknowledged', () {
    testWidgets(
      'a pointer drag on another node drags that node and leaves the camera '
      'alone',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        await _dropPinnedPersonUnacknowledged(tester, harness);
        final callsBeforeDrag = harness.server.calls.length;
        final node = cubit.graphController.nodePayloadForId('fp:in')!;
        expect(cubit.canDragNode(node), isTrue);
        // The unacknowledged write is in flight right now; no flag derived
        // from it may exist for the drag decision to consult.
        expect(
          () => (cubit as dynamic).placementActionsEnabled,
          throwsNoSuchMethodError,
          reason: 'drag availability must not be tracked as write I/O state',
        );
        final cameraBefore = _camera(cubit);
        final nodeFinder = _nodeFinder(_freePerson);
        expect(nodeFinder, findsOneWidget);

        final gesture = await tester.startGesture(
          tester.getCenter(nodeFinder),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(40, 30));
        await tester.pump();
        await gesture.moveBy(const Offset(40, 30));
        await tester.pump();

        expect(
          cubit.state.placementPhase,
          ConstellationPlacementPhase.draggingNew,
          reason: 'the pointer must have picked up node B, not the canvas',
        );
        expect(cubit.state.activePlacementTarget, _freePerson);
        expect(_camera(cubit), cameraBefore);

        await gesture.up();
        await _settleFrames(tester);

        expect(_camera(cubit), cameraBefore);
        // The first write is still unanswered, so B's drop is queued behind it;
        // acknowledging it lets the outbox send B.
        harness.server.ack(0);
        await _settleFrames(tester);
        expect(
          harness.server.calls.length,
          greaterThan(callsBeforeDrag),
          reason: 'the drop of B is handed to the outbox',
        );
        expect(
          {
            for (final call in harness.server.calls.skip(callsBeforeDrag))
              for (final op in call.ops) op.target,
          },
          contains(_freePerson),
        );
      },
    );

    testWidgets(
      'an earlier drop acknowledged mid-drag neither relayouts nor disturbs '
      'the dragged node',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        await _dropPinnedPersonUnacknowledged(tester, harness);
        final droppedAt = cubit.graphController.getPositionOrNullForId('fp:am');
        final cameraBefore = _camera(cubit);

        final gesture = await tester.startGesture(
          tester.getCenter(_nodeFinder(_freePerson)),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(40, 30));
        await tester.pump();
        await gesture.moveBy(const Offset(40, 30));
        await tester.pump();
        expect(
          cubit.state.placementPhase,
          ConstellationPlacementPhase.draggingNew,
        );
        final reconciliations = cubit.layoutReconciliationCount;
        final layoutRuns = cubit.graphController.relayoutInvocationCount;
        final draggedAt = cubit.graphController.getPositionOrNullForId('fp:in');

        harness.server.ack(0);
        await _settleFrames(tester);

        expect(
          cubit.state.confirmedProjection!.revision,
          ConstellationAnchorRevision(BigInt.two),
          reason: 'the acknowledgement must have been consumed',
        );
        expect(cubit.layoutReconciliationCount, reconciliations);
        expect(cubit.graphController.relayoutInvocationCount, layoutRuns);
        expect(
          cubit.state.placementPhase,
          ConstellationPlacementPhase.draggingNew,
        );
        expect(cubit.state.activePlacementTarget, _freePerson);
        expect(
          cubit.graphController.getPositionOrNullForId('fp:am'),
          droppedAt,
        );
        expect(
          cubit.graphController.getPositionOrNullForId('fp:in'),
          draggedAt,
        );
        expect(_camera(cubit), cameraBefore);

        await gesture.up();
        await _settleFrames(tester);
        expect(_camera(cubit), cameraBefore);
      },
    );

    testWidgets(
      'unpinning another node while a pointer drag is in progress reaches the '
      'server and leaves the drag alone',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final cameraBefore = _camera(cubit);

        final gesture = await tester.startGesture(
          tester.getCenter(_nodeFinder(_freePerson)),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(40, 30));
        await tester.pump();
        await gesture.moveBy(const Offset(40, 30));
        await tester.pump();
        expect(
          cubit.state.placementPhase,
          ConstellationPlacementPhase.draggingNew,
        );

        await cubit.unpinAnchor(target: _pinnedPerson);
        await _settleFrames(tester);

        expect(harness.server.calls, hasLength(1));
        final ops = harness.server.calls.single.ops;
        expect(ops.single.target, _pinnedPerson);
        expect(ops.single.kind, ConstellationAnchorOpKind.delete);
        expect(
          cubit.state.placementPhase,
          ConstellationPlacementPhase.draggingNew,
        );
        expect(cubit.state.activePlacementTarget, _freePerson);
        expect(_camera(cubit), cameraBefore);

        await gesture.up();
        await _settleFrames(tester);
        expect(_camera(cubit), cameraBefore);
      },
    );

    testWidgets('both drops reach the server and neither pans the camera', (
      tester,
    ) async {
      final harness = await _mount(tester);
      final cubit = harness.cubit;
      await _dropPinnedPersonUnacknowledged(tester, harness);
      final cameraBefore = _camera(cubit);

      cubit.beginDragNew(target: _freePerson);
      expect(
        cubit.state.placementPhase,
        ConstellationPlacementPhase.draggingNew,
      );
      await cubit.onExistingNodeDrop(
        target: _freePerson,
        sceneCentre: const Offset(300, 260),
      );
      await _settleFrames(tester);
      // The first write is still unanswered; the second is queued behind it.
      harness.server.ack(0);
      await _settleFrames(tester);

      final sentTargets = {
        for (final call in harness.server.calls)
          for (final op in call.ops) op.target,
      };
      expect(sentTargets, {_pinnedPerson, _freePerson});
      expect(_camera(cubit), cameraBefore);
    });

    testWidgets(
      'a second drag begun while the first drop is unacknowledged survives '
      'the first acknowledgement',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        await _dropPinnedPersonUnacknowledged(tester, harness);

        cubit.beginDragNew(target: _freePerson);
        expect(
          cubit.state.placementPhase,
          ConstellationPlacementPhase.draggingNew,
        );

        harness.server.ack(0);
        await _settleFrames(tester);

        expect(
          cubit.state.placementPhase,
          ConstellationPlacementPhase.draggingNew,
          reason: 'an acknowledgement of an earlier write ends no later drag',
        );
        expect(cubit.state.activePlacementTarget, _freePerson);
        expect(cubit.state.placementFailureMessage, isNull);
        expect(
          cubit.state.confirmedProjection!.revision,
          ConstellationAnchorRevision(BigInt.two),
        );
      },
    );
  });

  group('Placement interaction state', () {
    testWidgets('the cubit has no I/O gate on placement actions', (
      tester,
    ) async {
      final harness = await _mount(tester);

      // These probes only prove the members are gone under these names; the
      // behavioural guarantee is the mounted drag scenarios above and
      // 'a node is draggable by kind and ownership alone'. The lib-wide source
      // scan lives in test/architecture/constellation_no_io_drag_gate_test.dart.
      final cubit = harness.cubit as dynamic;
      expect(
        () => cubit.placementActionsEnabled,
        throwsNoSuchMethodError,
        reason: 'whether a node can be dragged must not depend on write I/O',
      );
      expect(() => cubit.hasPendingWrite, throwsNoSuchMethodError);
      expect(() => cubit.deferredRefreshTargets, throwsNoSuchMethodError);
    });

    testWidgets('the state carries no I/O gate or deferred refresh targets', (
      tester,
    ) async {
      final harness = await _mount(tester);
      final state = harness.cubit.state as dynamic;

      expect(() => state.placementActionsEnabled, throwsNoSuchMethodError);
      expect(() => state.deferredRefreshTargets, throwsNoSuchMethodError);
      expect(() => state.hasPendingWrite, throwsNoSuchMethodError);
    });

    testWidgets('a node is draggable by kind and ownership alone', (
      tester,
    ) async {
      final harness = await _mount(tester);
      final cubit = harness.cubit;
      NodeDetails node(String id) =>
          cubit.graphController.nodePayloadForId(id)!;

      // Idle, drag in progress and write in flight all give the same answer.
      expect(cubit.canDragNode(node('fp:am')), isTrue);
      expect(cubit.canDragNode(node('fp:in')), isTrue);
      expect(cubit.canDragNode(node('fp:ego')), isFalse, reason: 'own node');

      await _dropPinnedPersonUnacknowledged(tester, harness);
      expect(cubit.canDragNode(node('fp:am')), isTrue);
      expect(cubit.canDragNode(node('fp:in')), isTrue);
      expect(cubit.canDragNode(node('fp:ego')), isFalse);

      cubit.beginDragNew(target: _freePerson);
      expect(cubit.canDragNode(node('fp:am')), isTrue);
      expect(cubit.canDragNode(node('fp:ego')), isFalse);
    });
  });
}
