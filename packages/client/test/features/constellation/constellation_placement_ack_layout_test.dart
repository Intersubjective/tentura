import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

final _person = ConstellationAnchorTarget.person('am');

ConstellationAnchor _anchor(
  ConstellationAnchorPosition position,
  int revision,
) => ConstellationAnchor(
  target: _person,
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

Future<_Harness> _mountPinned(WidgetTester tester) async {
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
    logger: Logger('ConstellationPlacementAckLayoutTest'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    placementCase: placement,
    viewer: kRefEgo,
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  await pumpConstellationBody(tester, cubit);
  return (cubit: cubit, placement: placement, server: server);
}

/// Lets the outbox dispatch, the scene lay out and any follow-up settle.
Future<void> _settleFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

ConstellationAnchor _composedPerson(ConstellationCubit cubit) => cubit
    .state
    .composition!
    .anchorOverlay
    .anchors
    .singleWhere((anchor) => anchor.target == _person);

ConstellationAnchor _confirmedPerson(ConstellationCubit cubit) => cubit
    .state
    .confirmedProjection!
    .anchors
    .singleWhere((anchor) => anchor.target == _person);

bool _composedHasPerson(ConstellationCubit cubit) => cubit
    .state
    .composition!
    .anchorOverlay
    .anchors
    .any((anchor) => anchor.target == _person);

bool _confirmedHasPerson(ConstellationCubit cubit) => cubit
    .state
    .confirmedProjection!
    .anchors
    .any((anchor) => anchor.target == _person);

/// The position the client sent to the server for the single pending op.
ConstellationAnchorPosition _sentPosition(_Harness harness) =>
    harness.server.calls.single.ops.single.position!;

void main() {
  group('Server acknowledgement of a placement', () {
    testWidgets(
      'does not re-run layout when a drop is acknowledged unchanged',
      (tester) async {
        final harness = await _mountPinned(tester);
        final cubit = harness.cubit;
        const dropCentre = Offset(240, 180);

        // Positive control: both counters are driven by real layout work.
        expect(cubit.layoutReconciliationCount, greaterThan(0));
        expect(cubit.graphController.relayoutInvocationCount, greaterThan(0));

        cubit
          ..beginDragExisting(target: _person)
          ..updateDragPresentation(nodeId: 'fp:am', sceneCentre: dropCentre);
        await cubit.onExistingNodeDrop(
          target: _person,
          sceneCentre: dropCentre,
        );
        await _settleFrames(tester);
        expect(harness.server.calls, hasLength(1));
        final sent = _sentPosition(harness);
        expect(sent, isNot(_pinnedAt));

        final reconciliations = cubit.layoutReconciliationCount;
        final layoutRuns = cubit.graphController.relayoutInvocationCount;
        final shown = cubit.graphController.getPositionOrNullForId('fp:am');

        harness.server.ack(0);
        await _settleFrames(tester);

        // The acknowledgement was consumed: confirmed truth moved to the
        // revision and the dropped position the server now holds.
        expect(
          cubit.state.confirmedProjection!.revision,
          ConstellationAnchorRevision(BigInt.two),
        );
        final confirmed = _confirmedPerson(cubit).position;
        expect(confirmed.xUnits, sent.xUnits);
        expect(confirmed.yUnits, sent.yUnits);

        expect(
          cubit.layoutReconciliationCount,
          reconciliations,
          reason: 'The desired layout already contained the dropped position',
        );
        expect(
          cubit.graphController.relayoutInvocationCount,
          layoutRuns,
          reason: 'An acknowledgement must not start a scene layout',
        );
        expect(
          cubit.graphController.getPositionOrNullForId('fp:am'),
          shown,
          reason: 'The dropped node must not move when its write is confirmed',
        );
      },
    );

    testWidgets('does not re-run layout when an unpin is acknowledged', (
      tester,
    ) async {
      final harness = await _mountPinned(tester);
      final cubit = harness.cubit;

      await cubit.unpinAnchor(target: _person);
      await _settleFrames(tester);
      expect(harness.server.calls, hasLength(1));

      final reconciliations = cubit.layoutReconciliationCount;
      final layoutRuns = cubit.graphController.relayoutInvocationCount;
      final shown = cubit.graphController.getPositionOrNullForId('fp:am');

      harness.server.ack(0);
      await _settleFrames(tester);

      // The acknowledgement was consumed: the server no longer holds the pin.
      expect(
        cubit.state.confirmedProjection!.revision,
        ConstellationAnchorRevision(BigInt.two),
      );
      expect(_confirmedHasPerson(cubit), isFalse);
      expect(_composedHasPerson(cubit), isFalse);

      expect(
        cubit.layoutReconciliationCount,
        reconciliations,
        reason: 'The desired layout already lacked the unpinned anchor',
      );
      expect(
        cubit.graphController.relayoutInvocationCount,
        layoutRuns,
        reason: 'An acknowledgement must not start a scene layout',
      );
      expect(
        cubit.graphController.getPositionOrNullForId('fp:am'),
        shown,
        reason: 'The scene must not change when the unpin is confirmed',
      );
    });
  });

  group('Pending placement in the composed scene', () {
    testWidgets(
      'shows a dropped position in the composition before the server answers',
      (tester) async {
        final harness = await _mountPinned(tester);
        final cubit = harness.cubit;
        const dropCentre = Offset(240, 180);

        cubit
          ..beginDragExisting(target: _person)
          ..updateDragPresentation(nodeId: 'fp:am', sceneCentre: dropCentre);
        await cubit.onExistingNodeDrop(
          target: _person,
          sceneCentre: dropCentre,
        );
        await _settleFrames(tester);
        expect(harness.server.calls, hasLength(1));

        final sent = _sentPosition(harness);
        final composed = _composedPerson(cubit).position;
        expect(
          composed.xUnits,
          sent.xUnits,
          reason: 'Composition follows confirmed anchors plus unsent intent',
        );
        expect(composed.yUnits, sent.yUnits);
        expect(
          _confirmedPerson(cubit).position,
          _pinnedAt,
          reason: 'The confirmed projection stays server truth until the ack',
        );
      },
    );

    testWidgets('shows an unpin in the composition before the server answers', (
      tester,
    ) async {
      final harness = await _mountPinned(tester);
      final cubit = harness.cubit;

      await cubit.unpinAnchor(target: _person);
      await _settleFrames(tester);

      expect(harness.server.calls, hasLength(1));
      expect(_composedHasPerson(cubit), isFalse);
      expect(_confirmedHasPerson(cubit), isTrue);
    });
  });
}
