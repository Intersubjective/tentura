import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';

// The minimal acknowledgement of an anchor batch is merged into the store's
// confirmed anchors without any read: the acked rows are merged, coverage
// advances only when the batch followed the covered revision directly, replayed
// results and results for obsolete params merge nothing.

const _account = 'account-a';

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

ConstellationAnchorTarget _target(String id) =>
    ConstellationAnchorTarget.person(id);

ConstellationAnchor _anchor(String personId, int revision) =>
    ConstellationAnchor(
      target: _target(personId),
      position: const ConstellationAnchorPosition(
        xUnits: 1,
        yUnits: 2,
        coordinateSpaceVersion: 1,
      ),
      revision: _revision(revision),
      placedAt: DateTime.utc(2026, 10, 8),
    );

ConstellationPerson _person(String id) => ConstellationPerson(id: id);

ConstellationAnchorOpResult _okUpsert(String opId, ConstellationAnchor row) =>
    ConstellationAnchorOpResult(
      clientOpId: opId,
      status: ConstellationAnchorOpStatus.ok,
      resultingTargetRevision: row.revision,
      anchor: row,
    );

ConstellationAnchorApplyResult _ack(
  int before,
  int after,
  List<ConstellationAnchorOpResult> results,
) => ConstellationAnchorApplyResult(
  beforeRevision: _revision(before),
  afterRevision: _revision(after),
  results: results,
);

final class _AccountPort implements ConstellationAccountPort {
  _AccountPort(this.currentAccountChanges);

  @override
  final Stream<String> currentAccountChanges;
}

final class _ServerRepository implements ConstellationRepositoryPort {
  var serverRevision = 0;
  var serverAnchors = <ConstellationAnchor>[];
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
      anchorProjection: ConstellationAnchorProjection(
        revision: _revision(serverRevision),
        anchors: List.of(serverAnchors),
        pinnedPeers: [for (final a in serverAnchors) _person(a.target.id)],
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );
  }
}

void main() {
  late BehaviorSubject<String> account;
  late FakeClockPort clock;
  late FakeWakeUpPort wakeUp;
  late ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) sync;
  late _ServerRepository server;
  late ConstellationFieldStoreCase store;

  Future<void> advance(Duration by) async {
    var left = by;
    while (left > Duration.zero) {
      final step = left > const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : left;
      clock.advance(step);
      wakeUp.elapse(step);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      left -= step;
    }
  }

  Future<void> buildLoaded({
    int revision = 5,
    List<ConstellationAnchor> anchors = const [],
  }) async {
    account = BehaviorSubject<String>.seeded(_account);
    clock = FakeClockPort(DateTime.utc(2026, 10, 8));
    wakeUp = FakeWakeUpPort();
    sync = buildTestRealtimeSync();
    server = _ServerRepository()
      ..serverRevision = revision
      ..serverAnchors = List.of(anchors);
    store = ConstellationFieldStoreCase(
      server,
      _AccountPort(account.stream),
      clock,
      wakeUp,
      sync.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationStoreAckMergeTest'),
    );
    await advance(const Duration(milliseconds: 100));
    store.lease();
    unawaited(store.requestRefresh(ConstellationRefreshReason.load));
    await advance(const Duration(seconds: 3));
    expect(store.current.coveredRevision, _revision(revision));
    server.calls.clear();
  }

  void anchorHint(int revision) => sync.port.emitChange(
    RealtimeEntityChange(
      kind: RealtimeEntityKind.constellationAnchor,
      aggregateId: _account,
      operation: RealtimeOperation.update,
      source: RealtimeChangeSource.serverInvalidation,
      revision: BigInt.from(revision),
    ),
  );

  List<ConstellationAnchorTarget> heldTargets() => [
    for (final a in store.current.field!.resolvedAnchorProjection.anchors)
      a.target,
  ];

  tearDown(() async {
    await account.close();
    await sync.port.dispose();
  });

  group('acknowledgement that directly follows the covered revision', () {
    test('merges the row, advances coverage and ignores the echo with no '
        'read', () async {
      await buildLoaded();
      final row = _anchor('a', 6);

      store.settle(_ack(5, 6, [_okUpsert('op-a', row)]), () {});
      anchorHint(6);
      await advance(const Duration(seconds: 10));

      expect(store.current.coveredRevision, _revision(6));
      expect(heldTargets(), [_target('a')]);
      expect(server.calls, isEmpty);
    });

    test('the slots are already settled when the merged state is '
        'published', () async {
      await buildLoaded();
      var settled = false;
      final settledAtPublish = <bool>[];
      final sub = store.changes.listen((_) => settledAtPublish.add(settled));

      store.settle(
        _ack(5, 6, [_okUpsert('op-a', _anchor('a', 6))]),
        () => settled = true,
      );
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(settledAtPublish, isNotEmpty);
      expect(settledAtPublish, everyElement(isTrue));
    });
  });

  group('acknowledgement after a foreign write', () {
    test('merges the rows but keeps coverage, and the echo causes exactly '
        'one ANCHORS resync', () async {
      await buildLoaded();
      server
        ..serverRevision = 7
        ..serverAnchors = [_anchor('b', 6), _anchor('a', 7)];

      // Another tab wrote b at 6; our write of a landed at 7.
      store.settle(_ack(6, 7, [_okUpsert('op-a', _anchor('a', 7))]), () {});

      expect(store.current.coveredRevision, _revision(5));
      expect(heldTargets(), contains(_target('a')));
      expect(server.calls, isEmpty);

      anchorHint(6);
      anchorHint(7);
      await advance(const Duration(seconds: 10));

      expect(server.calls, [ConstellationProjection.anchors]);
      expect(store.current.coveredRevision, _revision(7));
      expect(heldTargets(), unorderedEquals([_target('a'), _target('b')]));
    });

    test('a row is not lost whichever side of our write the foreign write '
        'falls on', () async {
      await buildLoaded();
      store.settle(_ack(5, 6, [_okUpsert('op-a', _anchor('a', 6))]), () {});
      server
        ..serverRevision = 7
        ..serverAnchors = [_anchor('a', 6), _anchor('b', 7)];

      anchorHint(7);
      await advance(const Duration(seconds: 10));

      expect(server.calls, [ConstellationProjection.anchors]);
      expect(heldTargets(), unorderedEquals([_target('a'), _target('b')]));
      expect(store.current.coveredRevision, _revision(7));
    });
  });

  group('acknowledged unpin', () {
    ConstellationAnchorOpResult okDelete(String opId, String personId) =>
        ConstellationAnchorOpResult(
          clientOpId: opId,
          status: ConstellationAnchorOpStatus.ok,
          resultingTargetRevision: _revision(6),
          target: _target(personId),
        );

    List<String> heldPinnedPeers() => [
      for (final p in store.current.field!.resolvedAnchorProjection.pinnedPeers)
        p.id,
    ];

    test('directly after the covered revision removes the row and its '
        'pinned record and advances coverage with no read', () async {
      await buildLoaded(anchors: [_anchor('a', 5)]);
      expect(heldTargets(), [_target('a')]);
      expect(heldPinnedPeers(), ['a']);
      var settled = false;

      store.settle(_ack(5, 6, [okDelete('op-a', 'a')]), () => settled = true);

      expect(settled, isTrue);
      expect(heldTargets(), isEmpty);
      expect(heldPinnedPeers(), isEmpty);
      expect(store.current.coveredRevision, _revision(6));
      expect(server.calls, isEmpty);
    });

    test('after a foreign write removes the row but keeps coverage', () async {
      await buildLoaded(anchors: [_anchor('a', 5)]);

      store.settle(_ack(6, 7, [okDelete('op-a', 'a')]), () {});

      expect(heldTargets(), isEmpty);
      expect(heldPinnedPeers(), isEmpty);
      expect(store.current.coveredRevision, _revision(5));
      expect(server.calls, isEmpty);
    });
  });

  group('results that must not be merged', () {
    test('a replayed OK settles its slot but merges no row', () async {
      await buildLoaded();
      var settled = false;

      store.settle(
        _ack(5, 5, [
          ConstellationAnchorOpResult(
            clientOpId: 'op-a',
            status: ConstellationAnchorOpStatus.ok,
            resultingTargetRevision: _revision(4),
            anchor: _anchor('a', 4),
            replayed: true,
          ),
        ]),
        () => settled = true,
      );

      expect(settled, isTrue);
      expect(heldTargets(), isEmpty);
      expect(store.current.coveredRevision, _revision(5));
      expect(server.calls, isEmpty);
    });

    test(
      'an ack for obsolete params settles slots and merges nothing',
      () async {
        await buildLoaded();
        final obsolete = store.projectionParams;
        store.setMembershipFilters(
          const ConstellationFieldMembershipFilters(showClosed: true),
        );
        var settled = false;
        final coverageBefore = store.current.coveredRevision;
        final heldBefore = heldTargets();

        store.settle(
          _ack(5, 6, [_okUpsert('op-a', _anchor('a', 6))]),
          () => settled = true,
          params: obsolete,
        );

        expect(settled, isTrue);
        expect(heldTargets(), heldBefore);
        expect(heldTargets(), isNot(contains(_target('a'))));
        expect(store.current.coveredRevision, coverageBefore);
      },
    );

    test('a rejected result merges nothing and keeps coverage', () async {
      await buildLoaded();

      var settled = false;

      store.settle(
        _ack(5, 5, [
          const ConstellationAnchorOpResult(
            clientOpId: 'op-a',
            status: ConstellationAnchorOpStatus.rejected,
            reason: 'target_not_found',
          ),
        ]),
        () => settled = true,
      );

      expect(settled, isTrue);
      expect(heldTargets(), isEmpty);
      expect(store.current.coveredRevision, _revision(5));
    });
  });
}
