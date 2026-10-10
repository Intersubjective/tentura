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

// Contract for the failure and lifetime rules of the account-owned write use
// case (architecture section 5.1, R1 promotion, R4, R8). The placement case
// takes the realtime sync case as `realtime:` so it can hear catch-ups, and
// schedules its own retries only through the WakeUpPort it is given.
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

/// Ordered log shared by both repositories, to compare dispatch order.
final _events = <String>[];

final class _FieldRepository implements ConstellationRepositoryPort {
  final calls = <ConstellationProjection>[];

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    calls.add(projection);
    _events.add('read:${projection.name}');
    return ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 8),
      context: '',
      anchorProjection: _projection(0, const []),
    );
  }
}

final class _ApplyCall {
  _ApplyCall(this.ops);

  final List<ConstellationAnchorApplyOp> ops;
  final reply = Completer<ConstellationAnchorApplyResult>();

  List<String> get ids => [for (final op in ops) op.clientOpId];
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
    _events.add('apply');
    return call.reply.future;
  }

  void fail(int index) =>
      calls[index].reply.completeError(TimeoutException('apply timed out'));

  void settle(int index, {Set<ConstellationAnchorTarget> rejected = const {}}) {
    final call = calls[index];
    final before = revision;
    final results = <ConstellationAnchorOpResult>[];
    for (final op in call.ops) {
      if (rejected.contains(op.target)) {
        results.add(
          ConstellationAnchorOpResult(
            clientOpId: op.clientOpId,
            status: ConstellationAnchorOpStatus.rejected,
            reason: 'target_unavailable',
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

/// Fake wake-ups that also remember every requested delay.
final class _RecordingWakeUpPort implements WakeUpPort {
  final inner = FakeWakeUpPort();

  /// Acknowledgement-timeout timers share the port but are not retries.
  final _overdue = FakeWakeUpPort();
  final delays = <Duration>[];

  int get pendingCount => inner.pendingCount;

  @override
  WakeUpHandle schedule(Duration delay, void Function() callback) {
    if (delay == kLazyWriteAckTimeout)
      return _overdue.schedule(delay, callback);
    delays.add(delay);
    return inner.schedule(delay, callback);
  }

  void elapse(Duration by) {
    inner.elapse(by);
    _overdue.elapse(by);
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
  late _RecordingWakeUpPort retries;
  late FakeWakeUpPort storeWakeUps;
  late TestRealtimeSyncPort realtimePort;
  late ConstellationStoreFixture fixture;
  late ConstellationPlacementCase placement;

  final targetX = ConstellationAnchorTarget.person('x');
  final targetY = ConstellationAnchorTarget.beacon('y');

  void place(ConstellationAnchorTarget target, ConstellationAnchorPosition p) =>
      placement.place(parent: target, position: p, companions: const []);

  /// Elapses past the longest backoff so any scheduled retry is due.
  Future<void> elapseRetries() async {
    retries.elapse(_maxBackoff * 2);
    storeWakeUps.elapse(_maxBackoff * 2);
    await _drain();
  }

  setUp(() async {
    _events.clear();
    fields = _FieldRepository();
    anchors = _AnchorRepository();
    retries = _RecordingWakeUpPort();
    storeWakeUps = FakeWakeUpPort();
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    addTearDown(realtimePort.dispose);
    final clock = FakeClockPort(DateTime.utc(2026, 10, 8));
    fixture = ConstellationStoreFixture(
      fields,
      accountId: 'viewer',
      clock: clock,
      wakeUp: storeWakeUps,
      realtime: realtime.case_,
    );
    await fixture.ready();
    final lease = fixture.store.lease();
    addTearDown(lease.dispose);
    await fixture.store.requestRefresh(ConstellationRefreshReason.load);
    fields.calls.clear();
    _events.clear();
    placement = ConstellationPlacementCase(
      anchors,
      fixture.store,
      clock,
      retries,
      realtime: realtime.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationPlacementFailureLifetimeTest'),
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

  group('A successor on one target waits for its predecessor outcome', () {
    test('an acknowledged predecessor leaves the successor untouched until '
        'it dispatches unchanged', () async {
      place(targetX, _positionA);
      await _drain();
      place(targetX, _positionB);
      final successor = placement.current.targets[targetX]!.latestPending!;
      await _drain();
      expect(anchors.calls, hasLength(1));

      anchors.settle(0);
      await _drain();

      expect(anchors.calls, hasLength(2));
      final op = anchors.calls[1].ops.single;
      expect(op.clientOpId, successor.op.clientOpId);
      expect(op.position, _positionB);
      anchors.settle(1);
      await _drain();
      expect(placement.current.targets, isEmpty);
    });

    test(
      'a rejected predecessor does not mark or replace the successor',
      () async {
        place(targetX, _positionA);
        await _drain();
        place(targetX, _positionB);
        final successor = placement.current.targets[targetX]!.latestPending!;
        await _drain();

        anchors.settle(0, rejected: {targetX});
        await _drain();

        expect(anchors.calls, hasLength(2));
        expect(anchors.calls[1].ops.single.clientOpId, successor.op.clientOpId);
        expect(anchors.calls[1].ops.single.position, _positionB);
        final state = placement.current.targets[targetX]!;
        expect(state.inFlight!.op.clientOpId, successor.op.clientOpId);
        expect(state.inFlight!.status, PlacementSlotStatus.inFlight);
        expect(state.latestPending, isNull);
      },
    );

    test('a timed out predecessor keeps the successor queued and untouched '
        'until the replayed predecessor resolves', () async {
      place(targetX, _positionA);
      await _drain();
      final predecessorId = anchors.calls.single.ops.single.clientOpId;
      place(targetX, _positionB);
      final successor = placement.current.targets[targetX]!.latestPending!;

      anchors.fail(0);
      await _drain();

      var state = placement.current.targets[targetX]!;
      expect(state.inFlight!.op.clientOpId, predecessorId);
      expect(state.inFlight!.status, PlacementSlotStatus.commitUnknown);
      expect(state.latestPending!.op.clientOpId, successor.op.clientOpId);
      expect(state.latestPending!.status, PlacementSlotStatus.queued);
      expect(anchors.calls, hasLength(1), reason: 'B must not overtake A');

      await elapseRetries();

      // The unknown predecessor is replayed first, under its own id.
      expect(anchors.calls, hasLength(2));
      expect(anchors.calls[1].ops.single.clientOpId, predecessorId);
      expect(anchors.calls[1].ops.single.position, _positionA);
      state = placement.current.targets[targetX]!;
      expect(state.latestPending!.op.clientOpId, successor.op.clientOpId);

      anchors.settle(1);
      await _drain();

      expect(anchors.calls, hasLength(3));
      expect(anchors.calls[2].ops.single.clientOpId, successor.op.clientOpId);
      expect(anchors.calls[2].ops.single.position, _positionB);
    });
  });

  group('Transport failure retry', () {
    test(
      'resends identical client op ids and payloads after a backoff',
      () async {
        placement.place(
          parent: targetX,
          position: _positionA,
          companions: [(target: targetY, position: _positionB)],
        );
        await _drain();
        final first = anchors.calls.single;

        anchors.fail(0);
        await _drain();

        expect(
          retries.pendingCount,
          1,
          reason: 'Retry must go through the WakeUpPort',
        );
        expect(retries.delays.single, greaterThan(Duration.zero));
        expect(retries.delays.single, lessThanOrEqualTo(_maxBackoff));
        expect(anchors.calls, hasLength(1), reason: 'No retry before backoff');

        retries.elapse(_maxBackoff);
        await _drain();

        expect(anchors.calls, hasLength(2));
        final retry = anchors.calls[1];
        expect(retry.ids, first.ids);
        expect(
          [for (final op in retry.ops) (op.target, op.kind, op.position)],
          [for (final op in first.ops) (op.target, op.kind, op.position)],
        );

        anchors.settle(1);
        await _drain();
        expect(placement.current.targets, isEmpty);
        expect(fixture.store.current.coveredRevision, _revision(2));
      },
    );

    test('stops after three attempts and stays commit-unknown', () async {
      place(targetX, _positionA);
      await _drain();
      final id = anchors.calls.single.ops.single.clientOpId;

      for (var attempt = 0; attempt < 3; attempt++) {
        anchors.fail(attempt);
        await _drain();
        await elapseRetries();
      }

      expect(anchors.calls, hasLength(3));
      expect(anchors.calls.map((call) => call.ids.single), everyElement(id));
      expect(retries.pendingCount, 0);
      final slot = placement.current.targets[targetX]!.inFlight!;
      expect(slot.op.clientOpId, id);
      expect(slot.status, PlacementSlotStatus.commitUnknown);
      expect(slot.attempts, 3);

      await elapseRetries();
      expect(anchors.calls, hasLength(3), reason: 'No automatic fourth try');
    });
  });

  group('Exhausted commit-unknown promotion', () {
    test(
      'blocks only its own target while other targets keep flushing',
      () async {
        place(targetX, _positionA);
        await _drain();
        for (var attempt = 0; attempt < 3; attempt++) {
          anchors.fail(attempt);
          await _drain();
          await elapseRetries();
        }
        expect(anchors.calls, hasLength(3));

        place(targetX, _positionB);
        place(targetY, _positionA);
        await _drain();

        expect(anchors.calls, hasLength(4));
        expect(anchors.calls[3].ops.map((op) => op.target), [targetY]);
        anchors.settle(3);
        await _drain();
        await elapseRetries();

        expect(anchors.calls, hasLength(4), reason: 'X stays blocked');
        expect(placement.current.targets.containsKey(targetY), isFalse);
        final blocked = placement.current.targets[targetX]!;
        expect(blocked.inFlight!.status, PlacementSlotStatus.commitUnknown);
        expect(blocked.latestPending!.status, PlacementSlotStatus.queued);
        expect(
          (blocked.latestPending!.op as PlacementUpsert).position,
          _positionB,
        );
      },
    );
  });

  group('Catch-up and reconnect replay of an exhausted unknown write', () {
    Future<List<String>> exhaust() async {
      place(targetX, _positionA);
      await _drain();
      for (var attempt = 0; attempt < 3; attempt++) {
        anchors.fail(attempt);
        await _drain();
        await elapseRetries();
      }
      fields.calls.clear();
      _events.clear();
      retries.delays.clear();
      return anchors.calls.first.ids;
    }

    test(
      'is jittered, not dispatched at once, and resends the same ids',
      () async {
        final ids = await exhaust();
        expect(anchors.calls, hasLength(3));

        realtimePort.emitCatchUp();
        await _drain();

        expect(
          anchors.calls,
          hasLength(3),
          reason: 'Replay waits for a jittered wake-up',
        );
        expect(retries.pendingCount, 1);
        expect(retries.delays.single, greaterThan(Duration.zero));
        expect(retries.delays.single, lessThanOrEqualTo(_maxBackoff));

        retries.elapse(_maxBackoff);
        await _drain();

        expect(anchors.calls, hasLength(4));
        expect(anchors.calls[3].ids, ids);
      },
    );

    test(
      'is dispatched before the recovery read of the same catch-up',
      () async {
        await exhaust();

        realtimePort.emitCatchUp();
        await _drain();
        await elapseRetries();
        for (var i = 0; i < anchors.calls.length; i++) {
          if (!anchors.calls[i].reply.isCompleted) anchors.settle(i);
        }
        await _drain();
        await elapseRetries();

        expect(_events, contains('apply'));
        expect(
          _events.where((event) => event.startsWith('read')),
          isNotEmpty,
          reason: 'The catch-up read is deferred, never dropped',
        );
        expect(
          _events.indexOf('apply'),
          lessThan(_events.indexWhere((event) => event.startsWith('read'))),
        );
      },
    );

    test('two catch-ups coalesce into one replay', () async {
      await exhaust();

      realtimePort
        ..emitCatchUp()
        ..emitCatchUp(connectionEpoch: 3);
      await _drain();
      await elapseRetries();

      expect(anchors.calls, hasLength(4));
    });
  });

  group('Account lifetime', () {
    test(
      'logout mid-flight sends no further request and clears the outbox',
      () async {
        place(targetX, _positionA);
        await _drain();
        place(targetY, _positionB);
        await _drain();
        expect(anchors.calls, hasLength(1));
        final generationBefore = fixture.store.current.generation;

        fixture.account.add('');
        await _drain();
        anchors.settle(0);
        await _drain();
        await elapseRetries();

        expect(anchors.calls, hasLength(1), reason: 'Y must never be sent');
        expect(placement.current.targets, isEmpty);
        expect(placement.current.hasUserPlacements, isFalse);
        expect(fixture.store.current.generation, generationBefore + 1);
        expect(placement.current.generation, fixture.store.current.generation);
      },
    );

    test(
      'a completion that arrives after logout is dropped as stale',
      () async {
        place(targetX, _positionA);
        await _drain();

        fixture.account.add('');
        await _drain();
        anchors.settle(0);
        await _drain();

        expect(
          fixture.store.current.coveredRevision,
          ConstellationAnchorRevision.zero,
          reason: 'The old account result must not reach the store',
        );
        expect(placement.current.targets, isEmpty);
      },
    );

    test('a pending retry never fires for the old account', () async {
      place(targetX, _positionA);
      await _drain();
      anchors.fail(0);
      await _drain();
      expect(retries.pendingCount, 1);

      fixture.account.add('other-viewer');
      await _drain();
      await elapseRetries();
      realtimePort.emitCatchUp();
      await _drain();
      await elapseRetries();

      expect(anchors.calls, hasLength(1));
      expect(retries.pendingCount, 0);
      expect(placement.current.targets, isEmpty);
    });
  });
}
