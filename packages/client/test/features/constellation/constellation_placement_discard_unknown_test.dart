import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
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

// Contract for Discard of a placement whose outcome is unknown, and for the
// compensating write that undoes a discarded write which turned out to be
// confirmed (architecture section 5.1, R7): replay first, then compensate or
// drop; a conflict on a compensation is dropped; an unsent compensation yields
// to newer intent while a dispatched one settles before its successor.
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

  void place(ConstellationAnchorTarget target, ConstellationAnchorPosition p) =>
      placement.place(parent: target, position: p, companions: const []);

  Future<void> elapseRetries() async {
    retries.elapse(_maxBackoff * 2);
    storeWakeUps.elapse(_maxBackoff * 2);
    await _drain();
  }

  /// Dispatches a placement on [target] whose response never arrives, so the
  /// write may or may not have committed; returns its client op id.
  Future<String> leaveUnknown(
    ConstellationAnchorTarget target,
    ConstellationAnchorPosition p,
  ) async {
    place(target, p);
    await _drain();
    final index = anchors.calls.length - 1;
    final id = anchors.calls[index].op.clientOpId;
    anchors.fail(index);
    await _drain();
    expect(
      placement.current.targets[target]!.inFlight!.status,
      PlacementSlotStatus.commitUnknown,
    );
    return id;
  }

  void expectConfirmedAnchors(
    Map<ConstellationAnchorTarget, ConstellationAnchorPosition> expected,
  ) {
    expect(
      {
        for (final anchor
            in fixture.store.current.field!.resolvedAnchorProjection.anchors)
          anchor.target: anchor.position,
      },
      expected,
    );
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
      logger: Logger('ConstellationPlacementDiscardUnknownTest'),
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

  group('Discard of a placement whose outcome is unknown', () {
    test(
      'replays the same client op id instead of dropping the slot',
      () async {
        final id = await leaveUnknown(targetX, _positionA);
        expect(anchors.calls, hasLength(1));

        placement.discard(targetX);
        await _drain();

        expect(anchors.calls, hasLength(2));
        final replay = anchors.calls[1].op;
        expect(replay.clientOpId, id);
        expect(replay.kind, ConstellationAnchorOpKind.upsert);
        expect(replay.target, targetX);
        expect(replay.position, _positionA);
        final slot = placement.current.targets[targetX]!.inFlight!;
        expect(slot.op.clientOpId, id, reason: 'Kept until the replay settles');
        expect(slot.status, PlacementSlotStatus.inFlight);
      },
    );

    test('drops a replay the server rejects without compensating', () async {
      final id = await leaveUnknown(targetX, _positionA);
      placement.discard(targetX);
      await _drain();
      expect(
        anchors.calls,
        hasLength(2),
        reason: 'Discard replays the unknown pin',
      );
      expect(anchors.calls[1].op.clientOpId, id);

      anchors.settle(1, rejected: {targetX});
      await _drain();
      await elapseRetries();

      expect(anchors.calls, hasLength(2), reason: 'Nothing to undo');
      expect(placement.current.targets, isEmpty);
      expectConfirmedAnchors({});
    });

    test(
      'drops a rejected move replay without restoring its position',
      () async {
        place(targetX, _positionA);
        await _drain();
        expect(anchors.calls, hasLength(1));
        anchors.settle(0);
        await _drain();
        expectConfirmedAnchors({targetX: _positionA});
        final preOpConfirmed = anchors.confirmed[targetX]!;

        final id = await leaveUnknown(targetX, _positionB);
        expect(anchors.calls, hasLength(2));
        placement.discard(targetX);
        await _drain();
        expect(
          anchors.calls,
          hasLength(3),
          reason: 'Discard replays the unknown move',
        );
        expect(anchors.calls[2].op.clientOpId, id);
        expect(anchors.calls[2].op.position, _positionB);
        anchors.settle(2, rejected: {targetX});
        await _drain();
        await elapseRetries();

        expect(
          anchors.calls,
          hasLength(3),
          reason: 'A rejected move needs no compensation',
        );
        expect(anchors.confirmed[targetX]!.position, _positionA);
        expect(
          fixture.store.current.field!.resolvedAnchorProjection.anchors,
          [preOpConfirmed],
          reason:
              'Rejecting the move preserves the original anchor and revision',
        );
        expectConfirmedAnchors({targetX: _positionA});
        expect(placement.current.targets, isEmpty);
      },
    );

    test(
      'deletes a first-time pin the replay turned out to have committed',
      () async {
        final id = await leaveUnknown(targetX, _positionA);
        placement.discard(targetX);
        await _drain();
        expect(
          anchors.calls,
          hasLength(2),
          reason: 'Discard replays the unknown pin',
        );
        anchors.settle(1);
        await _drain();

        expect(anchors.calls, hasLength(3));
        final compensation = anchors.calls[2].op;
        expect(compensation.kind, ConstellationAnchorOpKind.delete);
        expect(compensation.target, targetX);
        expect(compensation.clientOpId, isNot(id));
        expect(
          compensation.ifRevision,
          _revision(1),
          reason: 'Guarded by the revision the replay produced',
        );

        anchors.settle(2);
        await _drain();
        await elapseRetries();

        expect(anchors.calls, hasLength(3));
        expect(anchors.confirmed, isEmpty);
        expect(placement.current.targets, isEmpty);
        expectConfirmedAnchors({});
      },
    );

    test(
      'restores the position held before the first dispatch of a committed move',
      () async {
        place(targetX, _positionA);
        await _drain();
        anchors.settle(0);
        await _drain();
        final id = await leaveUnknown(targetX, _positionB);
        expect(anchors.calls, hasLength(2));

        placement.discard(targetX);
        await _drain();
        expect(
          anchors.calls,
          hasLength(3),
          reason: 'Discard replays the unknown move',
        );
        expect(anchors.calls[2].op.clientOpId, id);
        anchors.settle(2);
        await _drain();

        expect(
          fixture
              .store
              .current
              .field!
              .resolvedAnchorProjection
              .anchors
              .single
              .position,
          _positionB,
          reason: 'The replay committed the discarded move',
        );
        expect(anchors.calls, hasLength(4));
        final compensation = anchors.calls[3].op;
        expect(compensation.kind, ConstellationAnchorOpKind.upsert);
        expect(compensation.target, targetX);
        expect(compensation.position, _positionA);
        expect(compensation.clientOpId, isNot(id));
        expect(compensation.ifRevision, _revision(2));

        anchors.settle(3);
        await _drain();
        await elapseRetries();

        expect(anchors.calls, hasLength(4));
        expect(anchors.confirmed[targetX]!.position, _positionA);
        expect(placement.current.targets, isEmpty);
        expectConfirmedAnchors({targetX: _positionA});
      },
    );

    test('keeps replaying one id until it settles, then compensates', () async {
      final id = await leaveUnknown(targetX, _positionA);
      placement.discard(targetX);
      await _drain();
      expect(
        anchors.calls,
        hasLength(2),
        reason: 'Discard replays the unknown pin',
      );
      anchors.fail(1);
      await _drain();
      await elapseRetries();

      expect(anchors.calls, hasLength(3));
      expect(anchors.calls[2].op.clientOpId, id);
      expect(
        anchors.calls[1].op.ifRevision,
        anchors.calls[0].op.ifRevision,
      );
      expect(anchors.calls[2].op.ifRevision, anchors.calls[0].op.ifRevision);

      anchors.settle(2);
      await _drain();

      expect(anchors.calls, hasLength(4));
      expect(anchors.calls[3].op.kind, ConstellationAnchorOpKind.delete);
      expect(anchors.calls[3].op.ifRevision, _revision(1));
    });
  });

  group('Conflict on a compensating write', () {
    test('is dropped when the discarded write was unknown', () async {
      await leaveUnknown(targetX, _positionA);
      placement.discard(targetX);
      await _drain();
      expect(
        anchors.calls,
        hasLength(2),
        reason: 'Discard replays the unknown pin',
      );
      anchors.settle(1);
      await _drain();
      expect(
        anchors.calls,
        hasLength(3),
        reason: 'An OK replay dispatches compensation',
      );
      expect(anchors.calls[2].op.ifRevision, _revision(1));
      expect(anchors.calls[2].op.kind, ConstellationAnchorOpKind.delete);
      expect(anchors.calls[2].op.target, targetX);

      anchors.settle(2, rejected: {targetX}, rejectReason: 'conflict');
      await _drain();
      expect(
        placement.current.targets,
        isEmpty,
        reason: 'Conflict rejection drops the compensating slot immediately',
      );
      placement.retry(targetX);
      await _drain();
      await elapseRetries();

      expect(anchors.calls, hasLength(3), reason: 'No second compensation');
      expect(
        placement.current.targets,
        isEmpty,
        reason: 'Newer server state wins; no marker is left behind',
      );
      expectConfirmedAnchors({targetX: _positionA});
    });

    test('is dropped when the discarded write was in flight', () async {
      place(targetX, _positionA);
      await _drain();
      placement.discard(targetX);
      await _drain();
      anchors.settle(0);
      await _drain();
      expect(anchors.calls, hasLength(2));
      expect(anchors.calls[1].op.kind, ConstellationAnchorOpKind.delete);
      expect(anchors.calls[1].op.ifRevision, _revision(1));

      anchors.settle(1, rejected: {targetX}, rejectReason: 'conflict');
      await _drain();
      expect(
        placement.current.targets,
        isEmpty,
        reason: 'Conflict rejection drops the compensating slot immediately',
      );
      placement.retry(targetX);
      await _drain();
      await elapseRetries();

      expect(
        anchors.calls,
        hasLength(2),
        reason: 'Dropped compensation cannot retry',
      );
      expect(placement.current.targets, isEmpty);
      expectConfirmedAnchors({targetX: _positionA});
    });
  });

  group('Compensation against newer intent', () {
    test(
      'newer placement prevents an undispatched compensation from deleting its target',
      () async {
        await leaveUnknown(targetX, _positionA);
        placement.discard(targetX);
        await _drain();
        expect(
          anchors.calls,
          hasLength(2),
          reason: 'Discard replays the unknown pin',
        );

        // Keep the replay response gated until newer intent is queued. There is
        // nothing to compensate yet, so no compensation can have been sent.
        expect(anchors.calls[1].reply.isCompleted, isFalse);
        place(targetX, _positionB);
        await _drain();
        expect(
          anchors.calls,
          hasLength(2),
          reason: 'The successor waits for replay',
        );
        final queued = placement.current.targets[targetX]!.latestPending!;
        expect(queued.op, isA<PlacementUpsert>());
        expect(queued.op.ifRevision, isNull);

        anchors.settle(1);
        await _drain();
        expect(anchors.calls, hasLength(3));
        final successor = anchors.calls[2].op;
        expect(successor.kind, ConstellationAnchorOpKind.upsert);
        expect(successor.target, targetX);
        expect(successor.position, _positionB);
        expect(successor.ifRevision, isNull);
        anchors.settle(2);
        await _drain();
        await elapseRetries();
        expect(
          anchors.calls
              .skip(2)
              .where(
                (call) =>
                    call.op.target == targetX &&
                    call.op.kind == ConstellationAnchorOpKind.delete,
              ),
          isEmpty,
          reason: 'Newer intent prevents an undispatched compensation',
        );
        expect(anchors.confirmed[targetX]!.position, _positionB);
        expectConfirmedAnchors({targetX: _positionB});
        expect(placement.current.targets, isEmpty);
      },
    );

    test('a dispatched compensation settles before its successor', () async {
      await leaveUnknown(targetX, _positionA);
      placement.discard(targetX);
      await _drain();
      expect(
        anchors.calls,
        hasLength(2),
        reason: 'Discard replays the unknown pin',
      );
      anchors.settle(1);
      await _drain();
      expect(anchors.calls, hasLength(3));
      expect(anchors.calls[2].op.kind, ConstellationAnchorOpKind.delete);
      expect(anchors.calls[2].reply.isCompleted, isFalse);

      place(targetX, _positionB);
      await _drain();
      await elapseRetries();

      expect(
        anchors.calls,
        hasLength(3),
        reason: 'The successor waits for the compensation',
      );
      expect(
        placement.current.targets[targetX]!.inFlight!.op.clientOpId,
        anchors.calls[2].op.clientOpId,
      );

      anchors.settle(2);
      await _drain();

      expect(anchors.calls, hasLength(4));
      final successor = anchors.calls[3].op;
      expect(successor.kind, ConstellationAnchorOpKind.upsert);
      expect(successor.position, _positionB);
      expect(successor.ifRevision, isNull);

      anchors.settle(3);
      await _drain();
      expect(anchors.confirmed[targetX]!.position, _positionB);
      expect(placement.current.targets, isEmpty);
    });
  });
}
