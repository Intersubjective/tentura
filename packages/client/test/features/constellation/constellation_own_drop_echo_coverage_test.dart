import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
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

/// Contract exercised here (a user's own drop and its realtime echo):
///
/// * The server announces a committed anchor write over realtime before the
///   apply response reaches the client. An announcement of exactly the revision
///   the apply acknowledgement carries is the user's own write: once the
///   acknowledgement settles it is covered, so it causes no ANCHORS read.
/// * An announcement from another device or tab, one with no readable revision,
///   and one above the acknowledged revision are not covered by the
///   acknowledgement and still cause an ANCHORS resync.

const _account = 'account-a';

const _position = ConstellationAnchorPosition(
  xUnits: 1,
  yUnits: 2,
  coordinateSpaceVersion: 1,
);

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

ConstellationAnchorTarget _target(String id) =>
    ConstellationAnchorTarget.person(id);

ConstellationAnchor _anchor(String personId, int revision) =>
    ConstellationAnchor(
      target: _target(personId),
      position: _position,
      revision: _revision(revision),
      placedAt: DateTime.utc(2026, 10, 8),
    );

/// Serves the anchors "the server" holds when a read starts.
final class _ServerRepository implements ConstellationRepositoryPort {
  int serverRevision = 0;
  List<ConstellationAnchor> serverAnchors = <ConstellationAnchor>[];

  final calls = <ConstellationProjection>[];

  int count(ConstellationProjection projection) =>
      calls.where((c) => c == projection).length;

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
        pinnedPeers: const [],
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );
  }
}

final class _ApplyCall {
  _ApplyCall(this.ops);

  final List<ConstellationAnchorApplyOp> ops;
  final reply = Completer<ConstellationAnchorApplyResult>();
}

/// Holds every apply open until the test acknowledges it.
final class _AnchorRepository implements ConstellationAnchorRepositoryPort {
  final calls = <_ApplyCall>[];

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) {
    final call = _ApplyCall(List.of(ops));
    calls.add(call);
    return call.reply.future;
  }

  /// Acknowledges call [index] as an executed upsert that moved the account's
  /// anchor revision from [before] to [after].
  void acknowledge(int index, {required int before, required int after}) {
    final call = calls[index];
    if (call.reply.isCompleted) return;
    call.reply.complete(
      ConstellationAnchorApplyResult(
        beforeRevision: _revision(before),
        afterRevision: _revision(after),
        results: [
          for (final op in call.ops)
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: ConstellationAnchorOpStatus.ok,
              resultingTargetRevision: _revision(after),
              target: op.target,
              anchor: ConstellationAnchor(
                target: op.target,
                position: op.position!,
                revision: _revision(after),
                placedAt: DateTime.utc(2026, 10, 8),
              ),
            ),
        ],
      ),
    );
  }
}

/// Drain async notifications without real-time waits.
Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _ServerRepository server;
  late _AnchorRepository anchors;
  late TestRealtimeSyncPort port;
  late ConstellationStoreFixture fixture;
  late ConstellationPlacementCase placement;

  /// The stored revision when the drop's batch was applied.
  const covered = 5;

  void drop(String personId) => placement.place(
    parent: _target(personId),
    position: _position,
    companions: const [],
  );

  void anchorHint(int? revision) => port.emitChange(
    RealtimeEntityChange(
      kind: RealtimeEntityKind.constellationAnchor,
      aggregateId: _account,
      operation: RealtimeOperation.update,
      source: RealtimeChangeSource.serverInvalidation,
      revision: revision == null ? null : BigInt.from(revision),
    ),
  );

  setUp(() async {
    server = _ServerRepository()..serverRevision = covered;
    anchors = _AnchorRepository();
    final sync = buildTestRealtimeSync();
    port = sync.port;
    final clock = FakeClockPort(DateTime.utc(2026, 10, 8));
    final wakeUp = FakeWakeUpPort();
    fixture = ConstellationStoreFixture(
      server,
      accountId: _account,
      clock: clock,
      wakeUp: wakeUp,
      realtime: sync.case_,
    );
    await fixture.ready();
    final lease = fixture.store.lease();
    addTearDown(lease.dispose);
    await fixture.store.requestRefresh(ConstellationRefreshReason.load);
    expect(fixture.store.current.coveredRevision, _revision(covered));
    server.calls.clear();
    placement = ConstellationPlacementCase(
      anchors,
      fixture.store,
      clock,
      wakeUp,
      realtime: sync.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationOwnDropEchoCoverageTest'),
    );
    addTearDown(() async {
      // Release gates even when an assertion fails so cleanup cannot hang.
      for (var i = 0; i < anchors.calls.length; i++) {
        anchors.acknowledge(i, before: covered, after: covered);
      }
      await _drain();
      await placement.dispose();
      await port.dispose();
    });
    await _drain();
  });

  group('own drop echo', () {
    test('an echo that arrives before the acknowledgement causes no '
        'ANCHORS read', () async {
      drop('dropped');
      await _drain();
      expect(anchors.calls, hasLength(1));

      anchorHint(6);
      await _drain();
      anchors.acknowledge(0, before: covered, after: 6);
      await _drain();

      expect(server.calls, isEmpty);
      expect(fixture.store.current.coveredRevision, _revision(6));
      expect(
        fixture.store.current.field!.resolvedAnchorProjection.anchors.map(
          (a) => a.target,
        ),
        [_target('dropped')],
      );
    });

    test('an echo that arrives after the acknowledgement causes no '
        'ANCHORS read', () async {
      drop('dropped');
      await _drain();

      anchors.acknowledge(0, before: covered, after: 6);
      await _drain();
      anchorHint(6);
      await _drain();

      expect(server.calls, isEmpty);
      expect(fixture.store.current.coveredRevision, _revision(6));
    });

    test('echoes of two drops in a row, each before its acknowledgement, '
        'cause no ANCHORS read', () async {
      drop('first');
      await _drain();
      anchorHint(6);
      await _drain();
      anchors.acknowledge(0, before: covered, after: 6);
      await _drain();

      drop('second');
      await _drain();
      expect(anchors.calls, hasLength(2));
      anchorHint(7);
      await _drain();
      anchors.acknowledge(1, before: 6, after: 7);
      await _drain();

      expect(server.calls, isEmpty);
      expect(fixture.store.current.coveredRevision, _revision(7));
    });
  });

  test('disposing while a drop is in flight, then acknowledging it, does '
      'not throw', () async {
    drop('dropped');
    await _drain();
    expect(anchors.calls, hasLength(1));

    await placement.dispose();
    anchors.acknowledge(0, before: covered, after: 6);
    await _drain();
  });

  group('hints the acknowledgement does not cover', () {
    test('a hint from another device while no drop is in flight causes one '
        'ANCHORS read', () async {
      server
        ..serverRevision = 6
        ..serverAnchors = [_anchor('elsewhere', 6)];

      anchorHint(6);
      await _drain();

      expect(server.calls, [ConstellationProjection.anchors]);
      expect(fixture.store.current.coveredRevision, _revision(6));
    });

    test('a hint above the acknowledged revision arriving mid-flight causes '
        'one ANCHORS read that brings the other write in', () async {
      drop('dropped');
      await _drain();
      server
        ..serverRevision = 7
        ..serverAnchors = [_anchor('dropped', 6), _anchor('elsewhere', 7)];

      anchorHint(6);
      anchorHint(7);
      await _drain();
      anchors.acknowledge(0, before: covered, after: 6);
      await _drain();

      expect(server.calls, [ConstellationProjection.anchors]);
      expect(fixture.store.current.coveredRevision, _revision(7));
      expect(
        fixture.store.current.field!.resolvedAnchorProjection.anchors.map(
          (a) => a.target,
        ),
        unorderedEquals([_target('dropped'), _target('elsewhere')]),
      );
    });

    test('a hint with no readable revision arriving mid-flight causes one '
        'ANCHORS read', () async {
      drop('dropped');
      await _drain();
      server
        ..serverRevision = 6
        ..serverAnchors = [_anchor('dropped', 6)];

      anchorHint(null);
      await _drain();
      anchors.acknowledge(0, before: covered, after: 6);
      await _drain();

      expect(server.count(ConstellationProjection.anchors), 1);
      expect(fixture.store.current.coveredRevision, _revision(6));
    });
  });
}
