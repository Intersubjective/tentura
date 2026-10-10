import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/port/wake_up_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/placement_outbox.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';

// Contract for the user-driven Retry and Discard of a placement that did not
// save (architecture section 5.1, R1 and R7, queued / rejected / in-flight
// branches). Discard of a commit-unknown write and the exact shape and
// ordering of a compensating op are a separate contract; here only the
// observable outcome of discarding an in-flight write is pinned.
const _maxBackoff = Duration(seconds: 30);
const _positionA = ConstellationAnchorPosition(
  xUnits: 1,
  yUnits: 2,
  coordinateSpaceVersion: 1,
);
const _positionB = ConstellationAnchorPosition(
  xUnits: 3,
  yUnits: 4,
  coordinateSpaceVersion: 1,
);

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

ConstellationAnchorProjection _projection(
  int revision,
  Iterable<ConstellationAnchor> anchors,
) => ConstellationAnchorProjection(
  revision: _revision(revision),
  anchors: anchors.toList(),
  pinnedPeers: const [],
  pinnedRequests: const [],
  supportPeers: const [],
  supportEdges: const [],
  serverFilteredBeaconIds: const [],
  serverFilteredBeaconCount: 0,
);

final class _FieldRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 8),
    context: '',
    anchorProjection: _projection(0, const []),
  );
}

final class _ApplyCall {
  _ApplyCall(this.ops);

  final List<ConstellationAnchorApplyOp> ops;
  final reply = Completer<ConstellationAnchorApplyResult>();

  ConstellationAnchorApplyOp get op => ops.single;
}

/// Holds every response until the test settles or fails the call.
final class _AnchorRepository implements ConstellationWriteFake {
  final calls = <_ApplyCall>[];
  final confirmed = <ConstellationAnchorTarget, ConstellationAnchor>{};
  int revision = 0;

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) {
    final call = _ApplyCall(List.of(ops));
    calls.add(call);
    return call.reply.future;
  }

  void fail(int index) =>
      calls[index].reply.completeError(TimeoutException('apply timed out'));

  void settle(
    int index, {
    Set<ConstellationAnchorTarget> rejected = const {},
    String rejectReason = 'target_unavailable',
  }) {
    final call = calls[index];
    final before = revision;
    final results = <ConstellationAnchorOpResult>[];
    for (final op in call.ops) {
      if (rejected.contains(op.target)) {
        results.add(
          ConstellationAnchorOpResult(
            clientOpId: op.clientOpId,
            status: ConstellationAnchorOpStatus.rejected,
            reason: rejectReason,
          ),
        );
        continue;
      }
      revision++;
      if (op.kind == ConstellationAnchorOpKind.delete) {
        confirmed.remove(op.target);
      } else {
        confirmed[op.target] = ConstellationAnchor(
          target: op.target,
          position: op.position!,
          revision: _revision(revision),
          placedAt: DateTime.utc(2026, 10, 8),
        );
      }
      results.add(
        ConstellationAnchorOpResult(
          clientOpId: op.clientOpId,
          status: ConstellationAnchorOpStatus.ok,
          resultingTargetRevision: _revision(revision),
          target: op.target,
          anchor: op.kind == ConstellationAnchorOpKind.delete
              ? null
              : confirmed[op.target],
        ),
      );
    }
    call.reply.complete(
      ConstellationAnchorApplyResult(
        beforeRevision: _revision(before),
        afterRevision: _revision(revision),
        results: results,
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

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _AnchorRepository anchors;
  late FakeWakeUpPort retries;
  late FakeWakeUpPort storeWakeUps;
  late ConstellationStoreFixture fixture;
  late ConstellationPlacementCase placement;

  final targetX = ConstellationAnchorTarget.person('x');
  final targetY = ConstellationAnchorTarget.beacon('y');

  void place(ConstellationAnchorTarget target, ConstellationAnchorPosition p) =>
      placement.place(parent: target, position: p, companions: const []);

  Future<void> elapseRetries() async {
    retries.elapse(_maxBackoff * 2);
    storeWakeUps.elapse(_maxBackoff * 2);
    await _drain();
  }

  /// Settles every request still waiting for a response, including follow-ups
  /// that settling an earlier one triggers, so the test only observes the end
  /// state and not how it was reached.
  Future<void> settleOutstanding() async {
    for (var i = 0; i < 10; i++) {
      for (var j = 0; j < anchors.calls.length; j++) {
        if (!anchors.calls[j].reply.isCompleted) anchors.settle(j);
      }
      await _drain();
      await elapseRetries();
    }
  }

  /// Dispatches X, then has the server reject it; returns the rejected id.
  Future<String> rejectPlacementOnX() async {
    place(targetX, _positionA);
    await _drain();
    final id = anchors.calls.last.op.clientOpId;
    anchors.settle(anchors.calls.length - 1, rejected: {targetX});
    await _drain();
    final slot = placement.current.targets[targetX]!.latestPending!;
    expect(slot.status, PlacementSlotStatus.rejected);
    expect(slot.op.clientOpId, id);
    return id;
  }

  setUp(() async {
    anchors = _AnchorRepository();
    retries = FakeWakeUpPort();
    storeWakeUps = FakeWakeUpPort();
    final realtime = buildTestRealtimeSync();
    addTearDown(realtime.port.dispose);
    final clock = FakeClockPort(DateTime.utc(2026, 10, 8));
    fixture = ConstellationStoreFixture(
      _FieldRepository(),
      accountId: 'viewer',
      clock: clock,
      wakeUp: storeWakeUps,
      realtime: realtime.case_,
    );
    await fixture.ready();
    final lease = fixture.store.lease();
    addTearDown(lease.dispose);
    await fixture.store.requestRefresh(ConstellationRefreshReason.load);
    placement = ConstellationPlacementCase(
      anchors,
      fixture.store,
      clock,
      retries,
      realtime: realtime.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationPlacementRetryDiscardTest'),
    );
    addTearDown(() async {
      // Release gates even when an assertion fails so cleanup cannot hang.
      for (var i = 0; i < 20; i++) {
        for (var j = 0; j < anchors.calls.length; j++) {
          if (!anchors.calls[j].reply.isCompleted) anchors.settle(j);
        }
        await _drain();
      }
      await placement.dispose();
    });
    await _drain();
  });

  group('Retry of a rejected placement', () {
    test('resends the same position under a fresh client op id', () async {
      final rejectedId = await rejectPlacementOnX();
      expect(anchors.calls, hasLength(1));

      placement.retry(targetX);
      await _drain();

      expect(anchors.calls, hasLength(2));
      final op = anchors.calls[1].op;
      expect(op.clientOpId, isNot(rejectedId));
      expect(op.kind, ConstellationAnchorOpKind.upsert);
      expect(op.target, targetX);
      expect(op.position, _positionA);
      final slot = placement.current.targets[targetX]!.inFlight!;
      expect(slot.op.clientOpId, op.clientOpId);
      expect(slot.status, PlacementSlotStatus.inFlight);

      anchors.settle(1);
      await _drain();
      expect(placement.current.targets, isEmpty);
      expect(fixture.store.current.field!.resolvedAnchorProjection.anchors, [
        isA<ConstellationAnchor>()
            .having((a) => a.target, 'target', targetX)
            .having((a) => a.position, 'position', _positionA),
      ]);
    });

    test(
      'retrying a rejected unpin resends a delete under a fresh client op id',
      () async {
        placement.unpin(targetX);
        await _drain();
        final rejectedId = anchors.calls.single.op.clientOpId;
        anchors.settle(0, rejected: {targetX});
        await _drain();

        placement.retry(targetX);
        await _drain();

        expect(anchors.calls, hasLength(2));
        expect(anchors.calls[1].op.kind, ConstellationAnchorOpKind.delete);
        expect(anchors.calls[1].op.target, targetX);
        expect(anchors.calls[1].op.clientOpId, isNot(rejectedId));
      },
    );

    test('a second rejection gets yet another client op id', () async {
      final firstId = await rejectPlacementOnX();
      placement.retry(targetX);
      await _drain();
      final secondId = anchors.calls[1].op.clientOpId;
      anchors.settle(1, rejected: {targetX});
      await _drain();

      expect(
        placement.current.targets[targetX]!.latestPending!.status,
        PlacementSlotStatus.rejected,
      );
      placement.retry(targetX);
      await _drain();

      expect(anchors.calls, hasLength(3));
      final thirdId = anchors.calls[2].op.clientOpId;
      expect({firstId, secondId, thirdId}, hasLength(3));
    });
  });

  group('Retry of a commit-unknown placement', () {
    test('resends the same client op id', () async {
      place(targetX, _positionA);
      await _drain();
      final id = anchors.calls.single.op.clientOpId;
      anchors.fail(0);
      await _drain();
      expect(
        placement.current.targets[targetX]!.inFlight!.status,
        PlacementSlotStatus.commitUnknown,
      );
      final sentBeforeRetry = anchors.calls.length;

      placement.retry(targetX);
      await _drain();

      expect(anchors.calls, hasLength(sentBeforeRetry + 1));
      final op = anchors.calls.last.op;
      expect(op.clientOpId, id);
      expect(op.kind, ConstellationAnchorOpKind.upsert);
      expect(op.target, targetX);
      expect(op.position, _positionA);

      anchors.settle(anchors.calls.length - 1);
      await _drain();
      expect(placement.current.targets, isEmpty);
    });
  });

  group('Discard of a placement that was never confirmed', () {
    test('a queued placement is dropped before it is ever sent', () async {
      place(targetX, _positionA);
      await _drain();
      place(targetY, _positionB);
      await _drain();
      expect(anchors.calls, hasLength(1), reason: 'Y waits for X to settle');
      expect(
        placement.current.targets[targetY]!.latestPending!.status,
        PlacementSlotStatus.queued,
      );

      placement.discard(targetY);

      expect(placement.current.targets.containsKey(targetY), isFalse);
      anchors.settle(0);
      await _drain();
      await elapseRetries();
      expect(anchors.calls, hasLength(1), reason: 'Y was never dispatched');
      expect(placement.current.targets, isEmpty);
    });

    test('a rejected placement is dropped without any request', () async {
      await rejectPlacementOnX();

      placement.discard(targetX);
      await _drain();
      await elapseRetries();

      expect(placement.current.targets, isEmpty);
      expect(anchors.calls, hasLength(1));
    });

    test('a discarded rejected placement is not retried afterwards', () async {
      await rejectPlacementOnX();
      placement.discard(targetX);

      placement.retry(targetX);
      await _drain();

      expect(anchors.calls, hasLength(1));
      expect(placement.current.targets, isEmpty);
    });
  });

  group('Discard of a placement that is in flight', () {
    test('waits for the settlement and then drops a rejected write', () async {
      place(targetX, _positionA);
      await _drain();
      final id = anchors.calls.single.op.clientOpId;

      placement.discard(targetX);
      await _drain();

      final pending = placement.current.targets[targetX]!.inFlight!;
      expect(pending.op.clientOpId, id, reason: 'Still awaiting settlement');
      expect(pending.status, PlacementSlotStatus.inFlight);
      expect(anchors.calls, hasLength(1));

      anchors.settle(0, rejected: {targetX});
      await _drain();
      await elapseRetries();

      expect(
        placement.current.targets,
        isEmpty,
        reason: 'A rejection of a discarded move leaves no marker behind',
      );
      expect(anchors.calls, hasLength(1));
    });

    test(
      'removes the target again once a first-time write is confirmed',
      () async {
        place(targetX, _positionA);
        await _drain();

        placement.discard(targetX);
        await _drain();
        anchors.settle(0);
        await settleOutstanding();

        expect(
          anchors.confirmed,
          isEmpty,
          reason: 'The server no longer pins X',
        );
        expect(placement.current.targets, isEmpty);
        expect(
          fixture.store.current.field!.resolvedAnchorProjection.anchors,
          isEmpty,
        );
      },
    );

    test('restores the earlier position once a move is confirmed', () async {
      place(targetX, _positionA);
      await _drain();
      anchors.settle(0);
      await _drain();
      expect(anchors.confirmed[targetX]!.position, _positionA);

      place(targetX, _positionB);
      await _drain();
      expect(anchors.calls, hasLength(2));
      placement.discard(targetX);
      await _drain();
      anchors.settle(1);
      await settleOutstanding();

      expect(anchors.confirmed[targetX]!.position, _positionA);
      expect(placement.current.targets, isEmpty);
      expect(fixture.store.current.field!.resolvedAnchorProjection.anchors, [
        isA<ConstellationAnchor>()
            .having((a) => a.target, 'target', targetX)
            .having((a) => a.position, 'position', _positionA),
      ]);
    });
  });
}
