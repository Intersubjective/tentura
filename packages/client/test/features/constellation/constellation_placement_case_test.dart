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

// Contract for the account-owned write use case (architecture section 5.1):
// place accepts a parent target, position, and target/position companion records;
// current exposes PlacementOutboxState. No legacy AnchorCase fallback is used.
const _position = ConstellationAnchorPosition(
  xUnits: 1,
  yUnits: 2,
  coordinateSpaceVersion: 1,
);
const _movedPosition = ConstellationAnchorPosition(
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
  final calls = <ConstellationProjection>[];

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    calls.add(projection);
    return ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 8),
      context: '',
      anchorProjection: _projection(0, const []),
    );
  }
}

final class _ApplyCall {
  _ApplyCall(this.ops, this.params);

  final List<ConstellationAnchorApplyOp> ops;
  final ConstellationFieldMembershipFilters params;
  final reply = Completer<ConstellationAnchorApplyResult>();
}

/// Holds every response until the test releases it, exposing overlapping calls.
final class _AnchorRepository implements ConstellationWriteFake {
  final calls = <_ApplyCall>[];
  final confirmed = <ConstellationAnchorTarget, ConstellationAnchor>{};
  int activeRequests = 0;
  int maxActiveRequests = 0;
  int legacyUpserts = 0;
  int legacyDeletes = 0;
  int revision = 0;

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) async {
    final call = _ApplyCall(List.of(ops), params);
    calls.add(call);
    activeRequests++;
    if (activeRequests > maxActiveRequests) {
      maxActiveRequests = activeRequests;
    }
    try {
      return await call.reply.future;
    } finally {
      activeRequests--;
    }
  }

  void settle(
    int index, {
    Set<ConstellationAnchorTarget> rejected = const {},
    ConstellationAnchorPosition? canonicalPosition,
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
          position: canonicalPosition ?? op.position!,
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
        // Deliberately differs from request order: settlement is by op id.
        results: results.reversed.toList(),
      ),
    );
  }

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    legacyUpserts++;
    throw StateError('Placement must use batched apply, not legacy upsert');
  }

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) async {
    legacyDeletes++;
    throw StateError('Unpin must use batched apply, not legacy delete');
  }
}

/// Drain async notifications without real-time waits or retry wake-ups.
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

  List<ConstellationAnchorTarget> placeCluster(String name, int size) {
    final targets = [
      ConstellationAnchorTarget.person('$name-parent'),
      for (var i = 1; i < size; i++)
        ConstellationAnchorTarget.beacon('$name-companion-$i'),
    ];
    placement.place(
      parent: targets.first,
      position: _position,
      companions: [
        for (final target in targets.skip(1))
          (target: target, position: _movedPosition),
      ],
    );
    return targets;
  }

  setUp(() async {
    fields = _FieldRepository();
    anchors = _AnchorRepository();
    final clock = FakeClockPort(DateTime.utc(2026, 10, 8));
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
    fields.calls.clear();
    placement = ConstellationPlacementCase(
      anchors,
      fixture.store,
      clock,
      wakeUp,
      realtime: buildTestRealtimeSync().case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationPlacementCaseTest'),
    );
    addTearDown(() async {
      // Release gates even when an assertion fails so cleanup cannot hang.
      for (var i = 0; i < 20; i++) {
        for (var j = 0; j < anchors.calls.length; j++) {
          if (!anchors.calls[j].reply.isCompleted) anchors.settle(j);
        }
        await _drain();
        if (anchors.activeRequests == 0) break;
      }
      await placement.dispose();
    });
    await _drain();
  });

  group('Placement acknowledgements', () {
    test(
      'one place applies its entire cluster without an ANCHORS fetch',
      () async {
        final targets = placeCluster('drag', 3);
        await _drain();

        expect(anchors.calls, hasLength(1));
        final call = anchors.calls.single;
        expect(call.ops.map((op) => op.target), unorderedEquals(targets));
        expect(
          call.ops.every((op) => op.kind == ConstellationAnchorOpKind.upsert),
          isTrue,
        );
        expect(call.ops.first.position, _position);
        expect(
          call.ops.skip(1).map((op) => op.position),
          everyElement(_movedPosition),
        );
        expect(call.ops.map((op) => op.clientOpId).toSet(), hasLength(3));
        expect(call.ops.map((op) => op.clientOpId), everyElement(isNotEmpty));
        expect(call.params, fixture.store.projectionParams.membershipFilters);

        anchors.settle(0, canonicalPosition: _movedPosition);
        await _drain();

        expect(anchors.calls, hasLength(1));
        expect(anchors.legacyUpserts, 0);
        expect(anchors.legacyDeletes, 0);
        expect(
          fields.calls.where((p) => p == ConstellationProjection.anchors),
          isEmpty,
        );
        expect(fields.calls, isEmpty);
        expect(placement.current.targets, isEmpty);
        expect(fixture.store.current.coveredRevision, _revision(3));
        final confirmed = fixture.store.current.field!.resolvedAnchorProjection;
        expect(
          confirmed.anchors.map((a) => a.target),
          unorderedEquals(targets),
        );
        expect(
          confirmed.anchors.map((a) => a.position),
          everyElement(_movedPosition),
        );
      },
    );

    test(
      'unpin settles a delete through apply without a recovery read',
      () async {
        final target = placeCluster('pin', 1).single;
        await _drain();
        anchors.settle(0);
        await _drain();

        placement.unpin(target);
        await _drain();
        expect(anchors.calls, hasLength(2));
        final op = anchors.calls.last.ops.single;
        expect(op.kind, ConstellationAnchorOpKind.delete);
        expect(op.target, target);
        expect(op.position, isNull);
        expect(op.clientOpId, isNot(anchors.calls.first.ops.single.clientOpId));
        anchors.settle(1);
        await _drain();

        expect(placement.current.targets, isEmpty);
        expect(
          fixture.store.current.field!.resolvedAnchorProjection.anchors,
          isEmpty,
        );
        expect(fixture.store.current.coveredRevision, _revision(2));
        expect(anchors.legacyDeletes, 0);
        expect(fields.calls, isEmpty);
      },
    );

    test(
      'reordered results settle op ids before the confirmed store emits',
      () async {
        final targets = placeCluster('mixed', 2);
        await _drain();
        final rejectedId = anchors.calls.single.ops
            .singleWhere((op) => op.target == targets.last)
            .clientOpId;
        final snapshots = <PlacementOutboxState>[];
        final sub = fixture.store.changes.listen((state) {
          if (state.coveredRevision == _revision(1)) {
            snapshots.add(placement.current);
          }
        });
        addTearDown(sub.cancel);

        anchors.settle(0, rejected: {targets.last});
        await _drain();

        expect(snapshots, hasLength(1));
        for (final state in [snapshots.single, placement.current]) {
          expect(state.targets.containsKey(targets.first), isFalse);
          final rejected = state.targets[targets.last]!;
          final slot = rejected.latestPending ?? rejected.inFlight;
          expect(slot, isNotNull);
          expect(slot!.op.clientOpId, rejectedId);
          expect(slot.status, PlacementSlotStatus.rejected);
          expect(slot.reasonCode, 'target_unavailable');
          expect(
            rejected.inFlight?.status,
            isNot(PlacementSlotStatus.inFlight),
          );
        }
        expect(
          fixture.store.current.field!.resolvedAnchorProjection.anchors.map(
            (a) => a.target,
          ),
          [targets.first],
        );
        expect(fields.calls, isEmpty);
      },
    );
  });

  group('Cluster bounded single flight flushing', () {
    for (final sizes in [
      [40, 30],
      [64, 1],
      [40, 24, 30],
    ]) {
      test(
        'queued clusters of ${sizes.join(', ')} stay whole below the 64 op cap',
        () async {
          placeCluster('blocker', 1);
          await _drain();
          expect(anchors.calls, hasLength(1));

          final clusters = [
            for (var i = 0; i < sizes.length; i++)
              placeCluster('cluster-$i', sizes[i]),
          ];
          await _drain();
          expect(
            anchors.calls,
            hasLength(1),
            reason: 'Queued clusters must wait for the held apply response',
          );
          expect(
            placement.current.targets,
            hasLength(1 + sizes.reduce((a, b) => a + b)),
          );

          anchors.settle(0);
          await _drain();
          var next = 1;
          while (next < anchors.calls.length) {
            expect(
              anchors.calls,
              hasLength(next + 1),
              reason: 'Only the currently released batch can be dispatched',
            );
            expect(anchors.calls[next].ops.length, inInclusiveRange(1, 64));
            anchors.settle(next);
            next++;
            await _drain();
          }

          final batches = anchors.calls
              .skip(1)
              .map((call) => call.ops)
              .toList();
          expect(batches.length, greaterThan(1));
          expect(
            batches.expand((ops) => ops).map((op) => op.target),
            unorderedEquals(clusters.expand((cluster) => cluster)),
          );
          for (final cluster in clusters) {
            final owners = batches.where(
              (batch) => batch.any((op) => cluster.contains(op.target)),
            );
            expect(
              owners,
              hasLength(1),
              reason: 'A drag cluster cannot be split',
            );
            expect(
              owners.single.map((op) => op.target).toSet().containsAll(cluster),
              isTrue,
            );
          }
          expect(anchors.maxActiveRequests, 1);
          expect(anchors.activeRequests, 0);
          expect(placement.current.targets, isEmpty);
          expect(fields.calls, isEmpty);
        },
      );
    }

    test(
      'new queued intent replaces an unsent target in an older cluster',
      () async {
        placeCluster('blocker', 1);
        await _drain();
        final oldCluster = placeCluster('drag', 2);
        final superseded = placement
            .current
            .targets[oldCluster.first]!
            .latestPending!
            .op
            .clientOpId;
        placement.place(
          parent: oldCluster.first,
          position: _movedPosition,
          companions: const [],
        );
        await _drain();

        final replacement =
            placement.current.targets[oldCluster.first]!.latestPending!.op;
        expect(replacement.clientOpId, isNot(superseded));
        expect((replacement as PlacementUpsert).position, _movedPosition);
        expect(anchors.calls, hasLength(1));
        anchors.settle(0);
        await _drain();
        var next = 1;
        while (next < anchors.calls.length) {
          anchors.settle(next++);
          await _drain();
        }

        final sent = anchors.calls.skip(1).expand((call) => call.ops).toList();
        expect(sent.map((op) => op.target), unorderedEquals(oldCluster));
        expect(sent.map((op) => op.clientOpId), isNot(contains(superseded)));
        expect(
          sent.singleWhere((op) => op.target == oldCluster.first).position,
          _movedPosition,
        );
        expect(anchors.maxActiveRequests, 1);
        expect(placement.current.targets, isEmpty);
      },
    );
  });
}
