import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
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

final _author = ConstellationAnchorTarget.person('in');
const _authorGraphId = 'fp:in';
final _satellite = ConstellationAnchorTarget.beacon('req-in-2');
const _satelliteGraphId = 'fr:req-in-2';

/// One envelope unit in scene pixels and the canvas centre (10 units = 1700 px
/// on each side of the centre).
const _unit = 170.0;
const _centre = 2048.0;

/// The pinned Request sits just inside the top envelope edge, so the first
/// few pixels of upward travel already push it against the wall.
const _satelliteYUnits = -9.9;
const _envelopeTopY = _centre - 10 * _unit;

/// Pointer target well inside the envelope for the person's own body.
const _targetY = 600.0;
const _sidewaysShift = 100.0;

ConstellationAnchor _anchor(
  ConstellationAnchorTarget target,
  double xUnits,
  double yUnits,
) => ConstellationAnchor(
  target: target,
  position: ConstellationAnchorPosition(
    xUnits: xUnits,
    yUnits: yUnits,
    coordinateSpaceVersion: 1,
  ),
  revision: ConstellationAnchorRevision(BigInt.one),
  placedAt: DateTime.utc(2026, 9, 9),
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

/// A server that records writes and never answers them.
final class _SilentAnchorRepository implements ConstellationWriteFake {
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

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) {
    applyCalls.add(List.of(ops));
    return Completer<ConstellationAnchorApplyResult>().future;
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
  _SilentAnchorRepository server,
});

/// Mounts the reference field with person `in` pinned at (1, 0) units. When
/// [pinRequest] is set, their Request `req-in-2` is pinned near the top wall.
Future<_Harness> _mount(WidgetTester tester, {required bool pinRequest}) async {
  final repository = _FieldRepository(
    constellationReferenceField(
      anchors: [
        _anchor(_author, 1, 0),
        if (pinRequest) _anchor(_satellite, 1, _satelliteYUnits),
      ],
    ),
  );
  final server = _SilentAnchorRepository();
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    repository,
    accountId: 'ego',
    realtime: sync.case_,
  ).store;
  final cubit = ConstellationCubit(
    case_: store,
    placementCase: ConstellationPlacementCase(
      server,
      store,
      FakeClockPort(),
      FakeWakeUpPort(),
      realtime: sync.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationPersonDragWithPinnedRequestsTest'),
    ),
    viewer: kRefEgo,
  );
  addTearDown(cubit.close);
  if (cubit.state.status is! StateIsSuccess) {
    await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  }
  await pumpConstellationBody(tester, cubit, size: const Size(800, 700));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  return (cubit: cubit, server: server);
}

Offset _centreOf(ConstellationCubit cubit, String graphId) {
  final point = cubit.graphController.renderSnapshot.resolvePosition(graphId);
  expect(point, isNotNull, reason: '$graphId must be laid out');
  return Offset(point!.x, point.y);
}

void main() {
  group('dragging a person whose Request is pinned against the top wall', () {
    testWidgets(
      'the person is clamped to the same position as without the pinned '
      'Request',
      (tester) async {
        final pinned = await _mount(tester, pinRequest: true);
        final pinnedStart = _centreOf(pinned.cubit, _authorGraphId);
        pinned.cubit.beginDragExisting(target: _author);
        final withPinned = pinned.cubit.clampClusterDragPosition(
          pinned.cubit.graphController.nodePayloadForId(_authorGraphId)!,
          Offset(pinnedStart.dx, _targetY),
        );

        final unpinned = await _mount(tester, pinRequest: false);
        final unpinnedStart = _centreOf(unpinned.cubit, _authorGraphId);
        unpinned.cubit.beginDragExisting(target: _author);
        final without = unpinned.cubit.clampClusterDragPosition(
          unpinned.cubit.graphController.nodePayloadForId(_authorGraphId)!,
          Offset(unpinnedStart.dx, _targetY),
        );

        expect(pinnedStart, unpinnedStart);
        expect(withPinned.dy, closeTo(without.dy, 1));
        expect(withPinned.dx, closeTo(without.dx, 1));
        expect(without.dy, closeTo(_targetY, 1));
      },
    );

    testWidgets(
      'the person follows the pointer while the Request follows sideways '
      'and stops at the envelope top',
      (tester) async {
        final harness = await _mount(tester, pinRequest: true);
        final cubit = harness.cubit;
        final authorStart = _centreOf(cubit, _authorGraphId);
        final satelliteStart = _centreOf(cubit, _satelliteGraphId);
        expect(
          satelliteStart.dy,
          closeTo(_centre + _satelliteYUnits * _unit, 1),
          reason: 'the Request must sit pinned against the top envelope edge',
        );

        cubit.beginDragExisting(target: _author);
        expect(
          cubit.graphController.activePresentationTokenForNode(
            _satelliteGraphId,
          ),
          isNotNull,
          reason: 'the pinned Request travels with its author',
        );
        final target = Offset(authorStart.dx + _sidewaysShift, _targetY);
        cubit.updateDragPresentation(
          nodeId: _authorGraphId,
          sceneCentre: target,
        );

        final author = _centreOf(cubit, _authorGraphId);
        final satellite = _centreOf(cubit, _satelliteGraphId);
        expect(author.dx, closeTo(target.dx, 1));
        expect(author.dy, closeTo(target.dy, 1));
        expect(satellite.dx, closeTo(satelliteStart.dx + _sidewaysShift, 1));
        expect(satellite.dy, closeTo(_envelopeTopY, 1));
        expect(
          constellationPointWithinEnvelope((x: satellite.dx, y: satellite.dy)),
          isTrue,
        );
      },
    );

    testWidgets(
      'dropping the person writes the dropped position and a Request '
      'position inside the envelope',
      (tester) async {
        final harness = await _mount(tester, pinRequest: true);
        final cubit = harness.cubit;
        final authorStart = _centreOf(cubit, _authorGraphId);
        final satelliteStart = _centreOf(cubit, _satelliteGraphId);

        cubit.beginDragExisting(target: _author);
        final target = Offset(authorStart.dx + _sidewaysShift, _targetY);
        cubit.updateDragPresentation(
          nodeId: _authorGraphId,
          sceneCentre: target,
        );
        await cubit.onExistingNodeDrop(target: _author, sceneCentre: target);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }

        expect(harness.server.applyCalls, hasLength(1));
        final ops = {
          for (final op in harness.server.applyCalls.single) op.target: op,
        };
        final authorOp = ops[_author]!.position!;
        final satelliteOp = ops[_satellite]!.position!;
        expect(authorOp.xUnits, closeTo((target.dx - _centre) / _unit, 1e-2));
        expect(authorOp.yUnits, closeTo((target.dy - _centre) / _unit, 1e-2));
        expect(
          satelliteOp.xUnits,
          closeTo((satelliteStart.dx + _sidewaysShift - _centre) / _unit, 1e-2),
        );
        expect(satelliteOp.yUnits, greaterThanOrEqualTo(-10));
        expect(satelliteOp.yUnits, closeTo(-10, 1e-2));
      },
    );
  });
}
