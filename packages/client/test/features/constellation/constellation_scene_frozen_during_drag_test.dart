import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_density.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

final _pinnedPerson = ConstellationAnchorTarget.person('am');
final _freePerson = ConstellationAnchorTarget.person('in');

const _pinnedAt = ConstellationAnchorPosition(
  xUnits: 0.2,
  yUnits: 0.3,
  coordinateSpaceVersion: 1,
);

ConstellationAnchor _pinnedAnchor() => ConstellationAnchor(
  target: _pinnedPerson,
  position: _pinnedAt,
  revision: ConstellationAnchorRevision(BigInt.one),
  placedAt: DateTime.utc(2026, 9, 9),
);

final class _FieldRepository implements ConstellationRepositoryPort {
  _FieldRepository(this.field);

  ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

/// A server that answers only when told to: every write stays in flight until
/// [acknowledgeAll].
final class _HeldAnchorRepository implements ConstellationWriteFake {
  @override
  Future<String> saveLayoutSnapshot({
    required String reason,
    required String clientOpId,
  }) => throw UnimplementedError('snapshots are not used by this test');

  @override
  Future<String> restoreLayoutSnapshot({
    required String snapshotId,
    required String clientOpId,
  }) => throw UnimplementedError('restore is not used by this test');

  @override
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
    bool saveHistory = false,
  }) => throw UnimplementedError('reset is not used by this test');

  final applyCalls = <List<ConstellationAnchorApplyOp>>[];
  final _replies = <Completer<ConstellationAnchorApplyResult>>[];

  /// Confirms every held write as applied; the confirmed anchors end up empty.
  void acknowledgeAll() {
    final revision = ConstellationAnchorRevision(BigInt.two);
    for (var i = 0; i < _replies.length; i++) {
      final reply = _replies[i];
      if (reply.isCompleted) continue;
      reply.complete(
        ConstellationAnchorApplyResult(
          beforeRevision: ConstellationAnchorRevision(BigInt.one),
          afterRevision: revision,
          results: [
            for (final op in applyCalls[i])
              ConstellationAnchorOpResult(
                clientOpId: op.clientOpId,
                status: ConstellationAnchorOpStatus.ok,
                resultingTargetRevision: revision,
                target: op.target,
                anchor: op.kind == ConstellationAnchorOpKind.delete
                    ? null
                    : ConstellationAnchor(
                        target: op.target,
                        position: op.position!,
                        revision: revision,
                        placedAt: DateTime.utc(2026, 10, 8),
                      ),
              ),
          ],
        ),
      );
    }
  }

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) {
    applyCalls.add(List.of(ops));
    final reply = Completer<ConstellationAnchorApplyResult>();
    _replies.add(reply);
    return reply.future;
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

/// Puts every node at a fixed, distinctive spot; optionally holds the result
/// back until [release], like a layout job that is still running. With a
/// [shiftPerRequest], every further layout run lands each node somewhere new,
/// so any layout that reaches the committed scene shows up as movement.
final class _FixedSpotsAlgorithm implements SceneLayoutAlgorithm {
  _FixedSpotsAlgorithm({this.hold = false, this.shiftPerRequest = 0});

  final bool hold;
  final double shiftPerRequest;
  final _released = Completer<void>();
  var requests = 0;

  void release() => _released.complete();

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    requests++;
    if (hold) await _released.future;
    final shift = shiftPerRequest * requests;
    var index = 0;
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: {
        for (final id in request.nodeIds)
          id: ScenePoint(
            x: 120.0 + shift + 70 * index,
            y: 90.0 + shift + 45 * index++,
          ),
      },
      isTerminal: true,
    );
  }
}

typedef _Harness = ({
  ConstellationCubit cubit,
  ConstellationFieldStoreCase store,
  ConstellationPlacementCase placement,
  _FieldRepository repository,
  _HeldAnchorRepository server,
});

Future<_Harness> _mount(WidgetTester tester) async {
  final repository = _FieldRepository(
    constellationReferenceField(
      egoRequestCount: 3,
      anchors: [_pinnedAnchor()],
    ),
  );
  final server = _HeldAnchorRepository();
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    repository,
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
    logger: Logger('ConstellationSceneFrozenDuringDragTest'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    placementCase: placement,
    viewer: kRefEgo,
  );
  addTearDown(cubit.close);
  cubit.testSceneLayoutAlgorithmOverride = _FixedSpotsAlgorithm(
    shiftPerRequest: 25,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  await pumpConstellationBody(tester, cubit, size: const Size(800, 700));
  await _settleFrames(tester);
  return (
    cubit: cubit,
    store: store,
    placement: placement,
    repository: repository,
    server: server,
  );
}

Future<void> _settleFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Where each committed node is drawn, leaving out the node being dragged.
Map<String, Offset?> _committedPositions(ConstellationCubit cubit) => {
  for (final id in cubit.graphController.renderSnapshot.topology.nodesById.keys)
    if (id != _freePerson.graphNodeId)
      id: cubit.graphController.getPositionOrNullForId(id),
};

/// The committed scene must really have laid-out nodes, or "nothing moved"
/// would hold for an empty scene too.
void _expectLaidOut(Map<String, Offset?> positions) {
  expect(
    positions.values.whereType<Offset>().length,
    greaterThanOrEqualTo(3),
    reason: 'the committed scene must have laid-out nodes to keep still',
  );
}

void _startDraggingFreePerson(ConstellationCubit cubit) {
  cubit
    ..beginDragNew(target: _freePerson)
    ..updateDragPresentation(
      nodeId: _freePerson.graphNodeId,
      sceneCentre: const Offset(310, 240),
    );
}

// Uses the existing `ConstellationCubit.requestConstellationLayoutForTest` seam
// to start layout work on demand.
void main() {
  group('The committed scene stays still while a node is being dragged', () {
    testWidgets(
      'a store refresh arriving mid-drag is held back instead of recomposed',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        _startDraggingFreePerson(cubit);
        await tester.pump();
        final positions = _committedPositions(cubit);
        _expectLaidOut(positions);
        final nodeIds = cubit
            .graphController
            .renderSnapshot
            .topology
            .nodesById
            .keys
            .toSet();

        harness.repository.field = constellationReferenceField(
          anchors: [_pinnedAnchor()],
        );
        await harness.store.requestRefresh(ConstellationRefreshReason.load);
        await _settleFrames(tester);

        expect(
          harness.store.current.field,
          same(harness.repository.field),
          reason: 'the refresh must have reached the store',
        );
        expect(
          cubit.graphController.renderSnapshot.topology.nodesById.keys.toSet(),
          nodeIds,
        );
        expect(_committedPositions(cubit), positions);
        _expectLaidOut(_committedPositions(cubit));
      },
    );

    testWidgets(
      'a placement write changing while dragging is held back instead of '
      'recomposed',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        _startDraggingFreePerson(cubit);
        await tester.pump();
        final positions = _committedPositions(cubit);
        _expectLaidOut(positions);

        await cubit.unpinAnchor(target: _pinnedPerson);
        await _settleFrames(tester);

        expect(
          harness.server.applyCalls,
          hasLength(1),
          reason: 'the unpin must still reach the server mid-drag',
        );
        expect(_committedPositions(cubit), positions);
        _expectLaidOut(_committedPositions(cubit));
      },
    );

    testWidgets(
      'the server confirming a placement write mid-drag moves no committed '
      'node',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        _startDraggingFreePerson(cubit);
        await tester.pump();
        final positions = _committedPositions(cubit);
        _expectLaidOut(positions);
        await cubit.unpinAnchor(target: _pinnedPerson);
        await _settleFrames(tester);
        expect(harness.server.applyCalls, hasLength(1));

        harness.server.acknowledgeAll();
        await _settleFrames(tester);
        await tester.pump(const Duration(milliseconds: 600));

        expect(
          harness.placement.current.targets[_pinnedPerson]?.inFlight,
          isNull,
          reason: 'the confirmation must have reached the outbox',
        );
        expect(_committedPositions(cubit), positions);
        _expectLaidOut(_committedPositions(cubit));
      },
    );

    testWidgets(
      'a layout transition running when the drag begins stops where it is',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        cubit.requestConstellationLayoutForTest(
          algorithm: _FixedSpotsAlgorithm(),
        );
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final early = _committedPositions(cubit);
        await tester.pump(const Duration(milliseconds: 60));
        final midFlight = _committedPositions(cubit);
        expect(
          midFlight,
          isNot(early),
          reason: 'the transition must be in flight before the drag starts',
        );

        _startDraggingFreePerson(cubit);
        await tester.pump();
        final frozen = _committedPositions(cubit);
        _expectLaidOut(frozen);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));

        expect(_committedPositions(cubit), frozen);
        _expectLaidOut(_committedPositions(cubit));
      },
    );

    testWidgets(
      'a layout transition triggered mid-drag moves no committed node',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        _startDraggingFreePerson(cubit);
        await tester.pump();
        final frozen = _committedPositions(cubit);
        _expectLaidOut(frozen);

        cubit.requestConstellationLayoutForTest(
          algorithm: _FixedSpotsAlgorithm(),
        );
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(_committedPositions(cubit), frozen);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));

        expect(_committedPositions(cubit), frozen);
        _expectLaidOut(_committedPositions(cubit));
      },
    );

    testWidgets(
      'a layout job still running when the drag begins publishes nothing',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final algorithm = _FixedSpotsAlgorithm(hold: true);
        cubit.requestConstellationLayoutForTest(algorithm: algorithm);
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          algorithm.requests,
          greaterThanOrEqualTo(1),
          reason: 'the layout job must be running before the drag starts',
        );

        _startDraggingFreePerson(cubit);
        await tester.pump();
        final frozen = _committedPositions(cubit);
        _expectLaidOut(frozen);
        algorithm.release();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));

        expect(_committedPositions(cubit), frozen);
        _expectLaidOut(_committedPositions(cubit));
      },
    );
  });
}
