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

/// Contract exercised here (anchor coverage in the constellation store):
///
/// * `coveredRevision` is the revision of the newest complete anchor
///   projection held; a `constellation_anchor` hint whose `revision` is at or
///   below it is an echo and causes no read.
/// * Any other hint (including exactly `coveredRevision + 1`, or one with no
///   readable revision) causes one coalesced ANCHORS resync.
/// * Hints that arrive while a read is in flight are held and judged against
///   the coverage reached once that read settles.

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

ConstellationAnchorProjection _projection(
  int revision,
  List<ConstellationAnchor> anchors,
) => ConstellationAnchorProjection(
  revision: _revision(revision),
  anchors: anchors,
  pinnedPeers: const [],
  pinnedRequests: const [],
  supportPeers: const [],
  supportEdges: const [],
  serverFilteredBeaconIds: const [],
  serverFilteredBeaconCount: 0,
);

ConstellationField _field(ConstellationAnchorProjection projection) =>
    ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 8),
      context: '',
      anchorProjection: projection,
    );

ConstellationAnchorApplyResult _applyResult(
  int before,
  ConstellationAnchorProjection projection,
) => ConstellationAnchorApplyResult(
  beforeRevision: _revision(before),
  afterRevision: projection.revision,
  results: const [],
  anchorProjection: projection,
);

/// Serves whatever the "server" holds at the moment a read starts, and can
/// hold a read open until [release] so a hint can arrive mid-flight.
final class _ServerRepository implements ConstellationRepositoryPort {
  var serverRevision = 0;
  var serverAnchors = <ConstellationAnchor>[];

  /// Reads started while this is non-null wait for it.
  Completer<void>? gate;

  final calls = <ConstellationProjection>[];

  int count(ConstellationProjection projection) =>
      calls.where((c) => c == projection).length;

  ConstellationAnchorProjection get snapshot =>
      _projection(serverRevision, List.of(serverAnchors));

  void release() {
    gate?.complete();
    gate = null;
  }

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    calls.add(projection);
    final result = _field(snapshot);
    final wait = gate;
    if (wait != null) await wait.future;
    return result;
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

  /// Builds the store and loads a FULL at [revision] holding [anchors].
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
      logger: Logger('ConstellationFieldStoreCoverageTest'),
    );
    await advance(const Duration(milliseconds: 100));
    store.lease();
    unawaited(store.requestRefresh(ConstellationRefreshReason.load));
    await advance(const Duration(seconds: 3));
    expect(store.current.coveredRevision, _revision(revision));
    server.calls.clear();
  }

  void anchorHint(int? revision) => sync.port.emitChange(
    RealtimeEntityChange(
      kind: RealtimeEntityKind.constellationAnchor,
      aggregateId: _account,
      operation: RealtimeOperation.update,
      source: RealtimeChangeSource.serverInvalidation,
      revision: revision == null ? null : BigInt.from(revision),
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

  group('echo suppression', () {
    test('a hint at the covered revision causes no read', () async {
      await buildLoaded();

      anchorHint(5);
      await advance(const Duration(seconds: 10));

      expect(server.calls, isEmpty);
      expect(store.current.coveredRevision, _revision(5));
    });

    test('a hint below the covered revision causes no read', () async {
      await buildLoaded();

      anchorHint(3);
      await advance(const Duration(seconds: 10));

      expect(server.calls, isEmpty);
    });
  });

  group('uncovered hints', () {
    test('a hint at covered + 1 causes exactly one ANCHORS resync', () async {
      await buildLoaded();
      server
        ..serverRevision = 6
        ..serverAnchors = [_anchor('b', 6)];

      anchorHint(6);
      await advance(const Duration(seconds: 10));

      expect(server.calls, [ConstellationProjection.anchors]);
      expect(store.current.coveredRevision, _revision(6));
      expect(heldTargets(), [_target('b')]);
    });

    test('repeated uncovered hints share one resync', () async {
      await buildLoaded();
      server
        ..serverRevision = 8
        ..serverAnchors = [_anchor('b', 8)];

      anchorHint(6);
      anchorHint(7);
      anchorHint(8);
      await advance(const Duration(seconds: 10));

      expect(server.count(ConstellationProjection.anchors), 1);
      expect(store.current.coveredRevision, _revision(8));
    });

    test('a hint with no readable revision is treated as uncovered', () async {
      await buildLoaded();

      anchorHint(null);
      await advance(const Duration(seconds: 10));

      expect(server.count(ConstellationProjection.anchors), 1);
    });
  });

  group('writes from another session around our own write', () {
    test('the other write lands before ours: its echo is ignored and no '
        'row is lost', () async {
      await buildLoaded();
      // B is written by another tab at 6, then our write A commits at 7, so
      // our ack already carries both rows.
      final both = _projection(7, [_anchor('b', 6), _anchor('a', 7)]);

      store.settle(_applyResult(5, both), () {});
      anchorHint(6);
      anchorHint(7);
      await advance(const Duration(seconds: 10));

      expect(server.calls, isEmpty);
      expect(store.current.coveredRevision, _revision(7));
      expect(heldTargets(), [_target('b'), _target('a')]);
    });

    test('the other write lands after ours: one resync brings it in and '
        'keeps ours', () async {
      await buildLoaded();
      store.settle(_applyResult(5, _projection(6, [_anchor('a', 6)])), () {});
      server
        ..serverRevision = 7
        ..serverAnchors = [_anchor('a', 6), _anchor('b', 7)];

      anchorHint(6);
      anchorHint(7);
      await advance(const Duration(seconds: 10));

      expect(server.count(ConstellationProjection.anchors), 1);
      expect(store.current.coveredRevision, _revision(7));
      expect(heldTargets(), [_target('a'), _target('b')]);
    });

    test('a resync read started before our ack and finishing after it '
        'cannot drop our row', () async {
      await buildLoaded();
      server
        ..serverRevision = 6
        ..serverAnchors = [_anchor('b', 6)]
        ..gate = Completer<void>();

      anchorHint(6);
      await advance(const Duration(seconds: 1));
      expect(server.count(ConstellationProjection.anchors), 1);

      store.settle(
        _applyResult(6, _projection(7, [_anchor('b', 6), _anchor('a', 7)])),
        () {},
      );
      server.release();
      await advance(const Duration(seconds: 10));

      expect(store.current.coveredRevision, _revision(7));
      expect(heldTargets(), [_target('b'), _target('a')]);
      expect(server.count(ConstellationProjection.anchors), 1);
    });
  });

  group('hints that arrive while a read is in flight', () {
    test('one the settled read already covers causes no further read', () async {
      await buildLoaded();
      server
        ..serverRevision = 6
        ..serverAnchors = [_anchor('b', 6)]
        ..gate = Completer<void>();

      anchorHint(6);
      await advance(const Duration(seconds: 1));
      anchorHint(6);
      await advance(const Duration(seconds: 1));
      server.release();
      await advance(const Duration(seconds: 10));

      expect(server.count(ConstellationProjection.anchors), 1);
      expect(store.current.coveredRevision, _revision(6));
    });

    test('one the settled read does not cover causes exactly one more read',
        () async {
      await buildLoaded();
      server
        ..serverRevision = 6
        ..serverAnchors = [_anchor('b', 6)]
        ..gate = Completer<void>();

      anchorHint(6);
      await advance(const Duration(seconds: 1));
      // The read in flight snapshotted revision 6; this commit is newer.
      anchorHint(7);
      await advance(const Duration(seconds: 1));
      server
        ..serverRevision = 7
        ..serverAnchors = [_anchor('b', 6), _anchor('c', 7)];
      server.release();
      await advance(const Duration(seconds: 10));

      expect(server.count(ConstellationProjection.anchors), 2);
      expect(store.current.coveredRevision, _revision(7));
      expect(heldTargets(), [_target('b'), _target('c')]);
    });

    test('an echo of the write whose ack is settled meanwhile is ignored',
        () async {
      await buildLoaded();
      server
        ..serverRevision = 6
        ..serverAnchors = [_anchor('b', 6)]
        ..gate = Completer<void>();

      anchorHint(6);
      await advance(const Duration(seconds: 1));
      anchorHint(7);
      store.settle(
        _applyResult(6, _projection(7, [_anchor('b', 6), _anchor('a', 7)])),
        () {},
      );
      server.release();
      await advance(const Duration(seconds: 10));

      expect(server.count(ConstellationProjection.anchors), 1);
      expect(store.current.coveredRevision, _revision(7));
      expect(heldTargets(), [_target('b'), _target('a')]);
    });

    test('one covered by an in-flight FULL causes no ANCHORS read', () async {
      await buildLoaded();
      server
        ..serverRevision = 6
        ..serverAnchors = [_anchor('b', 6)]
        ..gate = Completer<void>();

      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      await advance(const Duration(seconds: 1));
      expect(server.count(ConstellationProjection.full), 1);
      anchorHint(6);
      await advance(const Duration(seconds: 1));
      server.release();
      await advance(const Duration(seconds: 10));

      expect(server.count(ConstellationProjection.anchors), 0);
      expect(store.current.coveredRevision, _revision(6));
    });
  });
}

final class _AccountPort implements ConstellationAccountPort {
  _AccountPort(this.currentAccountChanges);

  @override
  final Stream<String> currentAccountChanges;
}
