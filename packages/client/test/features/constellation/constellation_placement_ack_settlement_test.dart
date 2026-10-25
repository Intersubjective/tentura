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

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';

// Settlement of placements from the minimal acknowledgement: the store learns
// the new pin from the record captured when the node was grabbed (no read, no
// support closure), and an ack that stays missing for the lazy-write timeout
// raises one notice per overdue episode, measured from the first dispatch.

const _position = ConstellationAnchorPosition(
  xUnits: 1,
  yUnits: 2,
  coordinateSpaceVersion: 1,
);

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

final class _FieldRepository implements ConstellationRepositoryPort {
  final calls = <ConstellationProjection>[];
  var peers = <ConstellationPerson>[];
  var requests = <ConstellationRequest>[];

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
      peers: peers,
      requests: requests,
      anchorProjection: ConstellationAnchorProjection.empty,
    );
  }
}

final class _ApplyCall {
  _ApplyCall(this.ops);

  final List<ConstellationAnchorApplyOp> ops;
  final reply = Completer<ConstellationAnchorApplyResult>();
}

final class _AnchorRepository implements ConstellationWriteFake {
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

  final calls = <_ApplyCall>[];
  var revision = 0;

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) {
    final call = _ApplyCall(List.of(ops));
    calls.add(call);
    return call.reply.future;
  }

  /// Answers call [index] with the minimal ack: before/after plus the stored
  /// row of every upsert, never a projection.
  void ack(int index) {
    final call = calls[index];
    final before = revision;
    final results = <ConstellationAnchorOpResult>[];
    for (final op in call.ops) {
      revision++;
      results.add(
        ConstellationAnchorOpResult(
          clientOpId: op.clientOpId,
          status: ConstellationAnchorOpStatus.ok,
          resultingTargetRevision: _revision(revision),
          target: op.target,
          anchor: op.kind == ConstellationAnchorOpKind.upsert
              ? ConstellationAnchor(
                  target: op.target,
                  position: op.position!,
                  revision: _revision(revision),
                  placedAt: DateTime.utc(2026, 10, 8),
                )
              : null,
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

  /// Answers call [index] with a rejection of every op.
  void reject(int index) {
    final call = calls[index];
    call.reply.complete(
      ConstellationAnchorApplyResult(
        beforeRevision: _revision(revision),
        afterRevision: _revision(revision),
        results: [
          for (final op in call.ops)
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: ConstellationAnchorOpStatus.rejected,
              reason: 'target_not_found',
            ),
        ],
      ),
    );
  }

  // Single-target hooks of the fixture interface; a client that routes a
  // pin through them is served the same ack rows.
  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    revision++;
    return ConstellationAnchorUpsertResult(
      anchor: ConstellationAnchor(
        target: target,
        position: position,
        revision: _revision(revision),
        placedAt: DateTime.utc(2026, 10, 8),
      ),
      revision: _revision(revision),
    );
  }

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) async {
    revision++;
    return ConstellationAnchorDeleteResult(
      target: target,
      revision: _revision(revision),
    );
  }
}

void main() {
  late _FieldRepository fields;
  late _AnchorRepository anchors;
  late FakeClockPort clock;
  late FakeWakeUpPort wakeUp;
  late ConstellationStoreFixture fixture;
  late ConstellationPlacementCase placement;
  late List<Object> notices;

  Future<void> drain() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> advance(Duration by) async {
    clock.advance(by);
    wakeUp.elapse(by);
    await drain();
  }

  Future<void> build({
    List<ConstellationPerson> peers = const [],
    List<ConstellationRequest> requests = const [],
  }) async {
    fields = _FieldRepository()
      ..peers = List.of(peers)
      ..requests = List.of(requests);
    anchors = _AnchorRepository();
    clock = FakeClockPort(DateTime.utc(2026, 10, 8));
    wakeUp = FakeWakeUpPort();
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
      logger: Logger('ConstellationPlacementAckSettlementTest'),
    );
    notices = [];
    final sub = placement.lazyWriteNotices.listen(notices.add);
    addTearDown(() async {
      for (var j = 0; j < anchors.calls.length; j++) {
        if (!anchors.calls[j].reply.isCompleted) anchors.ack(j);
      }
      await drain();
      await sub.cancel();
      await placement.dispose();
    });
    await drain();
  }

  ConstellationAnchorProjection confirmed() =>
      fixture.store.current.field!.resolvedAnchorProjection;

  group('pin settlement without a support fetch', () {
    test('pinning a person from the field keeps that person record in '
        'confirmed and reads nothing', () async {
      await build(peers: [const ConstellationPerson(id: 'p1')]);

      placement.place(
        parent: ConstellationAnchorTarget.person('p1'),
        position: _position,
        companions: const [],
      );
      await drain();
      anchors.ack(0);
      await drain();

      expect(placement.current.targets, isEmpty);
      expect(confirmed().anchors.map((a) => a.target.id), ['p1']);
      expect(confirmed().pinnedPeers.map((p) => p.id), ['p1']);
      expect(fields.calls, isEmpty);
    });

    test('pinning a request from the field keeps that request record in '
        'confirmed and reads nothing', () async {
      await build(
        requests: [
          const ConstellationRequest(
            id: 'b1',
            authorId: 'a',
            title: 'A request',
            status: 0,
          ),
        ],
      );

      placement.place(
        parent: ConstellationAnchorTarget.beacon('b1'),
        position: _position,
        companions: const [],
      );
      await drain();
      anchors.ack(0);
      await drain();

      expect(confirmed().pinnedRequests.map((r) => r.id), ['b1']);
      expect(fields.calls, isEmpty);
    });

    test('pinning a composer-only person keeps the captured record in '
        'confirmed and requests no support peers or edges', () async {
      await build();

      placement.place(
        parent: ConstellationAnchorTarget.person('composer-only'),
        position: _position,
        companions: const [],
        grabbedPerson: const ConstellationPerson(
          id: 'composer-only',
          displayName: 'Composer Only',
        ),
      );
      await drain();
      anchors.ack(0);
      await drain();

      expect(confirmed().pinnedPeers.map((p) => p.displayName), [
        'Composer Only',
      ]);
      expect(confirmed().supportPeers, isEmpty);
      expect(confirmed().supportEdges, isEmpty);
      expect(fields.calls, isEmpty);
    });

    test('unpinning removes the anchor row and its pinned record', () async {
      await build(peers: [const ConstellationPerson(id: 'p1')]);
      final target = ConstellationAnchorTarget.person('p1');
      placement.place(
        parent: target,
        position: _position,
        companions: const [],
      );
      await drain();
      anchors.ack(0);
      await drain();

      placement.unpin(target);
      await drain();
      anchors.ack(1);
      await drain();

      expect(confirmed().anchors, isEmpty);
      expect(confirmed().pinnedPeers, isEmpty);
      expect(fields.calls, isEmpty);
    });
  });

  group('overdue acknowledgement notice', () {
    void placePerson(String id) => placement.place(
      parent: ConstellationAnchorTarget.person(id),
      position: _position,
      companions: const [],
    );

    test('the timeout is 15 seconds', () {
      expect(kLazyWriteAckTimeout, const Duration(seconds: 15));
    });

    test('no notice just before the timeout, one at the timeout', () async {
      await build();
      placePerson('p1');
      await drain();

      await advance(const Duration(milliseconds: 14900));
      expect(notices, isEmpty);

      await advance(const Duration(milliseconds: 100));
      expect(notices, hasLength(1));

      await advance(const Duration(seconds: 30));
      expect(notices, hasLength(1));
    });

    test('an ack at 10 seconds raises no notice', () async {
      await build();
      placePerson('p1');
      await drain();

      await advance(const Duration(seconds: 10));
      anchors.ack(0);
      await drain();
      await advance(const Duration(seconds: 30));

      expect(notices, isEmpty);
    });

    test(
      'three overdue ops dispatched in one burst raise one notice',
      () async {
        await build();
        placement.place(
          parent: ConstellationAnchorTarget.person('p1'),
          position: _position,
          companions: [
            (
              target: ConstellationAnchorTarget.person('p2'),
              position: _position,
            ),
            (
              target: ConstellationAnchorTarget.person('p3'),
              position: _position,
            ),
          ],
        );
        await drain();
        expect(anchors.calls.single.ops, hasLength(3));

        await advance(kLazyWriteAckTimeout + const Duration(seconds: 1));

        expect(notices, hasLength(1));
      },
    );

    test('a second overdue episode after the first settled raises a second '
        'notice', () async {
      await build();
      placePerson('p1');
      await drain();
      await advance(kLazyWriteAckTimeout + const Duration(seconds: 1));
      expect(notices, hasLength(1));

      anchors.ack(0);
      await drain();
      placePerson('p2');
      await drain();
      expect(anchors.calls, hasLength(2));
      await advance(kLazyWriteAckTimeout + const Duration(seconds: 1));

      expect(notices, hasLength(2));
    });

    test(
      'an ack after the notice does not repeat it and still settles',
      () async {
        await build(peers: [const ConstellationPerson(id: 'p1')]);
        placePerson('p1');
        await drain();
        await advance(kLazyWriteAckTimeout + const Duration(seconds: 1));
        expect(notices, hasLength(1));

        anchors.ack(0);
        await drain();
        await advance(const Duration(seconds: 30));

        expect(notices, hasLength(1));
        expect(placement.current.targets, isEmpty);
        expect(confirmed().anchors.map((a) => a.target.id), ['p1']);
      },
    );

    test('a rejected result raises no notice', () async {
      await build();
      placePerson('p1');
      await drain();

      await advance(const Duration(seconds: 5));
      anchors.reject(0);
      await drain();
      await advance(const Duration(seconds: 30));

      expect(notices, isEmpty);
    });

    test('a retry does not restart the timer', () async {
      await build();
      placePerson('p1');
      await drain();

      await advance(const Duration(seconds: 5));
      anchors.calls.first.reply.completeError(StateError('transport'));
      await drain();
      // The automatic retry resends the same op; its own wait must not push
      // the notice past 15 s from the first dispatch.
      await advance(const Duration(seconds: 9, milliseconds: 900));
      expect(notices, isEmpty);
      await advance(const Duration(milliseconds: 100));

      expect(notices, hasLength(1));
    });
  });
}
