import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';

/// «Сбросить позиции» (#251) on the client: placements carry the anchor
/// revision the user saw; a reset waits for the batch in flight, drops
/// unacknowledged writes, retries under one operation id and empties the held
/// projection at the reset revision.

const _position = ConstellationAnchorPosition(
  xUnits: 1,
  yUnits: 2,
  coordinateSpaceVersion: 1,
);
final _person = ConstellationAnchorTarget.person('U_pinned');
final _request = ConstellationAnchorTarget.beacon('B_pinned');

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

ConstellationAnchor _anchor(ConstellationAnchorTarget target, int revision) =>
    ConstellationAnchor(
      target: target,
      position: _position,
      revision: _revision(revision),
      placedAt: DateTime.utc(2026, 10, 22),
    );

final class _FieldRepository implements ConstellationRepositoryPort {
  var fetches = 0;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fetches++;
    return ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 22),
      context: '',
      anchorProjection: ConstellationAnchorProjection(
        revision: _revision(7),
        anchors: [_anchor(_person, 6), _anchor(_request, 7)],
        pinnedPeers: const [ConstellationPerson(id: 'U_pinned')],
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );
  }
}

final class _AnchorRepository implements ConstellationAnchorRepositoryPort {
  final applies = <List<ConstellationAnchorApplyOp>>[];
  final applyReplies = <Completer<ConstellationAnchorApplyResult>>[];
  final resetIds = <String>[];
  var resetFailures = 0;

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) {
    applies.add(List.of(ops));
    final reply = Completer<ConstellationAnchorApplyResult>();
    applyReplies.add(reply);
    return reply.future;
  }

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
  }) async {
    resetIds.add(clientOpId);
    if (resetFailures > 0) {
      resetFailures--;
      throw StateError('transport failure');
    }
    return ConstellationAnchorResetResult(
      beforeRevision: _revision(7),
      afterRevision: _revision(10),
      clearedCount: 2,
    );
  }

  void acknowledge(int index, {required int before, required int after}) {
    applyReplies[index].complete(
      ConstellationAnchorApplyResult(
        beforeRevision: _revision(before),
        afterRevision: _revision(after),
        results: [
          for (final op in applies[index])
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: ConstellationAnchorOpStatus.ok,
              resultingTargetRevision: _revision(after),
              target: op.target,
              anchor: _anchor(op.target, after),
            ),
        ],
      ),
    );
  }
}

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _FieldRepository fields;
  late _AnchorRepository anchors;
  late ConstellationStoreFixture fixture;
  late ConstellationPlacementCase placement;

  void place(ConstellationAnchorTarget target) => placement.place(
    parent: target,
    position: _position,
    companions: const [],
  );

  setUp(() async {
    fields = _FieldRepository();
    anchors = _AnchorRepository();
    final clock = FakeClockPort(DateTime.utc(2026, 10, 22));
    final wakeUp = FakeWakeUpPort();
    fixture = ConstellationStoreFixture(
      fields,
      accountId: 'viewer',
      clock: clock,
      wakeUp: wakeUp,
    );
    await fixture.ready();
    final lease = fixture.store.lease();
    addTearDown(lease.dispose);
    await fixture.store.requestRefresh(ConstellationRefreshReason.load);
    placement = ConstellationPlacementCase(
      anchors,
      fixture.store,
      clock,
      wakeUp,
      realtime: buildTestRealtimeSync().case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationResetPositionsTest'),
    );
    addTearDown(() async {
      for (final reply in anchors.applyReplies) {
        if (!reply.isCompleted) reply.completeError(StateError('torn down'));
      }
      await _drain();
      await placement.dispose();
    });
    await _drain();
  });

  test('a placement carries the anchor revision the user saw', () async {
    place(ConstellationAnchorTarget.person('U_new'));
    await _drain();

    expect(anchors.applies.single.single.baseRevision, _revision(7));
  });

  test('the reset empties the held projection at the reset revision and '
      'reads the field again', () async {
    final fetchesBefore = fields.fetches;

    final result = await placement.resetAll();
    await _drain();

    expect(result.afterRevision, _revision(10));
    final projection = fixture.store.current.field!.resolvedAnchorProjection;
    expect(projection.anchors, isEmpty);
    expect(projection.pinnedPeers, isEmpty);
    expect(projection.revision, _revision(10));
    expect(fixture.store.current.coveredRevision, _revision(10));
    expect(fields.fetches, greaterThan(fetchesBefore));
  });

  test('a failed reset is retried with the same operation id', () async {
    anchors.resetFailures = 1;

    await placement.resetAll();

    expect(anchors.resetIds, hasLength(2));
    expect(anchors.resetIds.toSet(), hasLength(1));
  });

  test('a reset that keeps failing reports the failure and leaves the '
      'held anchors alone', () async {
    anchors.resetFailures = 10;

    await expectLater(placement.resetAll(), throwsStateError);
    expect(
      fixture.store.current.field!.resolvedAnchorProjection.anchors,
      hasLength(2),
    );
  });

  test('the reset waits for the batch in flight and then drops every '
      'unacknowledged write', () async {
    place(ConstellationAnchorTarget.person('U_in_flight'));
    await _drain();
    expect(anchors.applies, hasLength(1));
    // Queued behind the batch in flight (same target).
    place(ConstellationAnchorTarget.person('U_in_flight'));
    await _drain();

    final reset = placement.resetAll();
    await _drain();
    expect(anchors.resetIds, isEmpty, reason: 'waits for the batch in flight');

    anchors.acknowledge(0, before: 7, after: 8);
    await reset;
    await _drain();

    expect(anchors.resetIds, hasLength(1));
    expect(placement.current.targets, isEmpty);
    expect(placement.current.hasUserPlacements, isFalse);
    expect(anchors.applies, hasLength(1), reason: 'the queued write is gone');
    expect(
      fixture.store.current.field!.resolvedAnchorProjection.anchors,
      isEmpty,
    );
  });

  test('a write made after the reset is based on the reset revision', () async {
    await placement.resetAll();
    await _drain();

    place(ConstellationAnchorTarget.person('U_after'));
    await _drain();

    expect(anchors.applies.single.single.baseRevision, _revision(10));
  });

  test('a placement made while the batch in flight settles is kept and '
      'sent after the reset, based on the reset revision', () async {
    place(ConstellationAnchorTarget.person('U_in_flight'));
    await _drain();
    final reset = placement.resetAll();
    await _drain();

    place(ConstellationAnchorTarget.person('U_during'));
    await _drain();
    expect(anchors.applies, hasLength(1), reason: 'nothing sent mid-reset');

    anchors.acknowledge(0, before: 7, after: 8);
    await reset;
    await _drain();

    expect(anchors.applies, hasLength(2));
    final sent = anchors.applies.last.single;
    expect(sent.target, ConstellationAnchorTarget.person('U_during'));
    expect(sent.baseRevision, _revision(10));
  });

  test('concurrent resets share one request', () async {
    final first = placement.resetAll();
    final second = placement.resetAll();

    expect(await first, await second);
    expect(anchors.resetIds, hasLength(1));
  });

  test('a change of account abandons the reset before it is sent', () async {
    place(ConstellationAnchorTarget.person('U_in_flight'));
    await _drain();
    final reset = placement.resetAll();
    await _drain();

    fixture.account.add('another-account');
    await _drain();
    anchors.acknowledge(0, before: 7, after: 8);

    await expectLater(reset, throwsStateError);
    expect(anchors.resetIds, isEmpty);
  });

  test('a late acknowledgement does not bring a reset anchor back', () async {
    place(ConstellationAnchorTarget.person('U_late'));
    await _drain();
    // The reset reaches this device (e.g. made on another one) before the
    // acknowledgement of the write it removed.
    fixture.store.applyReset(_revision(10));

    anchors.acknowledge(0, before: 7, after: 8);
    await _drain();

    expect(
      fixture.store.current.field!.resolvedAnchorProjection.anchors,
      isEmpty,
    );
    expect(fixture.store.current.coveredRevision, _revision(10));
  });
}
