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

/// Drags and unpins made through the placement case are recorded in the
/// screen-session arrangement history, and undo / redo go back through the
/// same anchor apply path as the original write.

ConstellationAnchorPosition _at(double x, double y) =>
    ConstellationAnchorPosition(
      xUnits: x,
      yUnits: y,
      coordinateSpaceVersion: 1,
    );

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

final _pinned = ConstellationAnchorTarget.person('U1');

final class _FieldRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 24),
    context: '',
    anchorProjection: ConstellationAnchorProjection(
      revision: _revision(1),
      anchors: [
        ConstellationAnchor(
          target: _pinned,
          position: _at(7, 8),
          revision: _revision(1),
          placedAt: DateTime.utc(2026, 10, 24),
        ),
      ],
      pinnedPeers: const [],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

final class _AnchorRepository implements ConstellationAnchorRepositoryPort {
  final applies = <List<ConstellationAnchorApplyOp>>[];
  final _replies = <Completer<ConstellationAnchorApplyResult>>[];

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) {
    applies.add(List.of(ops));
    final reply = Completer<ConstellationAnchorApplyResult>();
    _replies.add(reply);
    return reply.future;
  }

  void settle(int index, {required int after, bool reject = false}) {
    _replies[index].complete(
      ConstellationAnchorApplyResult(
        beforeRevision: _revision(after - 1),
        afterRevision: _revision(after),
        results: [
          for (final op in applies[index])
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: reject
                  ? ConstellationAnchorOpStatus.rejected
                  : ConstellationAnchorOpStatus.ok,
              reason: reject ? 'forbidden' : null,
              resultingTargetRevision: _revision(after),
              target: op.target,
              anchor: reject || op.kind == ConstellationAnchorOpKind.delete
                  ? null
                  : ConstellationAnchor(
                      target: op.target,
                      position: op.position!,
                      revision: _revision(after),
                      placedAt: DateTime.utc(2026, 10, 24),
                    ),
            ),
        ],
      ),
    );
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
  }) => throw UnimplementedError('reset is not used by this test');
}

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _AnchorRepository anchors;
  late ConstellationStoreFixture fixture;
  late ConstellationPlacementCase placement;

  setUp(() async {
    anchors = _AnchorRepository();
    final clock = FakeClockPort(DateTime.utc(2026, 10, 24));
    final wakeUp = FakeWakeUpPort();
    fixture = ConstellationStoreFixture(
      _FieldRepository(),
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
      logger: Logger('ConstellationPlacementArrangementHistoryTest'),
    );
    addTearDown(() async {
      for (final reply in anchors._replies) {
        if (!reply.isCompleted) reply.completeError(StateError('torn down'));
      }
      await _drain();
      await placement.dispose();
    });
    await _drain();
  });

  Future<void> settleAll({bool reject = false}) async {
    await _drain();
    for (var i = 0; i < anchors.applies.length; i++) {
      if (!anchors._replies[i].isCompleted) {
        anchors.settle(i, after: i + 2, reject: reject);
        await _drain();
      }
    }
  }

  group('placement arrangement history', () {
    test(
      'dragging an already pinned person records one undoable entry',
      () async {
        placement.place(
          parent: _pinned,
          position: _at(1, 1),
          companions: const [],
        );
        await settleAll();

        expect(placement.history.length, 1);
        expect(placement.history.canUndo, isTrue);
      },
    );

    test(
      'undo of a drag writes the previous anchor back and redo re-applies it',
      () async {
        placement.place(
          parent: _pinned,
          position: _at(1, 1),
          companions: const [],
        );
        await settleAll();

        final undone = placement.undo();
        await settleAll();
        expect(await undone, isTrue);
        final undo = anchors.applies.last.single;
        expect(undo.kind, ConstellationAnchorOpKind.upsert);
        expect(undo.target, _pinned);
        expect(undo.position, _at(7, 8));

        final redone = placement.redo();
        await settleAll();
        expect(await redone, isTrue);
        expect(anchors.applies.last.single.position, _at(1, 1));
      },
    );

    test('undo of the first placement of a person unpins them', () async {
      final fresh = ConstellationAnchorTarget.person('U9');
      placement.place(
        parent: fresh,
        position: _at(3, 3),
        companions: const [],
      );
      await settleAll();

      final undone = placement.undo();
      await settleAll();
      await undone;

      final undo = anchors.applies.last.single;
      expect(undo.kind, ConstellationAnchorOpKind.delete);
      expect(undo.target, fresh);
    });

    test('unpinning is undoable and undo pins the person back', () async {
      placement.unpin(_pinned);
      await settleAll();
      expect(placement.history.canUndo, isTrue);

      final undone = placement.undo();
      await settleAll();
      await undone;

      final undo = anchors.applies.last.single;
      expect(undo.kind, ConstellationAnchorOpKind.upsert);
      expect(undo.position, _at(7, 8));
    });

    test(
      'a cluster of thirty people dragged together is a single entry',
      () async {
        final cluster = [
          for (var i = 0; i < 30; i++) ConstellationAnchorTarget.person('C$i'),
        ];
        placement.place(
          parent: cluster.first,
          position: _at(1, 1),
          companions: [
            for (final t in cluster.skip(1)) (target: t, position: _at(2, 2)),
          ],
        );
        await settleAll();

        expect(placement.history.length, 1);
        final undone = placement.undo();
        await settleAll();
        await undone;
        expect(anchors.applies.last, hasLength(30));
        expect(placement.history.canUndo, isFalse);
      },
    );

    test('a new drag after an undo clears redo', () async {
      placement.place(
        parent: _pinned,
        position: _at(1, 1),
        companions: const [],
      );
      await settleAll();
      final undone = placement.undo();
      await settleAll();
      await undone;
      expect(placement.history.canRedo, isTrue);

      placement.place(
        parent: _pinned,
        position: _at(2, 2),
        companions: const [],
      );
      await settleAll();

      expect(placement.history.canRedo, isFalse);
    });

    test('a drag whose batch the server rejects is not undoable', () async {
      placement.place(
        parent: _pinned,
        position: _at(1, 1),
        companions: const [],
      );
      await settleAll(reject: true);

      expect(placement.history.canUndo, isFalse);
      expect(await placement.undo(), isFalse);
      expect(anchors.applies, hasLength(1));
    });

    test('a rejected drag leaves earlier accepted drags undoable', () async {
      placement.place(
        parent: _pinned,
        position: _at(1, 1),
        companions: const [],
      );
      await settleAll();
      placement.place(
        parent: _pinned,
        position: _at(2, 2),
        companions: const [],
      );
      await settleAll(reject: true);

      expect(placement.history.canUndo, isTrue);
      final undone = placement.undo();
      await settleAll();
      await undone;
      expect(anchors.applies.last.single.position, _at(7, 8));
    });
  });
}
