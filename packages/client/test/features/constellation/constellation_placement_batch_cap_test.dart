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

/// One placement batch holds up to 400 operations (the server's anchor batch
/// cap): a cluster or a queue of clusters that fits goes out as one batch, and
/// only a queue above 400 is split.

const _cap = 400;
const _position = ConstellationAnchorPosition(
  xUnits: 1,
  yUnits: 2,
  coordinateSpaceVersion: 1,
);

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

List<ConstellationAnchorTarget> _people(int count, {String prefix = 'U'}) => [
  for (var i = 0; i < count; i++) ConstellationAnchorTarget.person('$prefix$i'),
];

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
      anchors: const [],
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

  void acknowledge(int index, {required int after}) {
    _replies[index].complete(
      ConstellationAnchorApplyResult(
        beforeRevision: _revision(after - applies[index].length),
        afterRevision: _revision(after),
        results: [
          for (final op in applies[index])
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: ConstellationAnchorOpStatus.ok,
              resultingTargetRevision: _revision(after),
              target: op.target,
              anchor: ConstellationAnchor(
                target: op.target,
                position: _position,
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

  void place(List<ConstellationAnchorTarget> cluster) => placement.place(
    parent: cluster.first,
    position: _position,
    companions: [
      for (final target in cluster.skip(1))
        (target: target, position: _position),
    ],
  );

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
      logger: Logger('ConstellationPlacementBatchCapTest'),
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

  group('placement batch size', () {
    test('one batch takes as many operations as the server accepts', () {
      expect(kConstellationPlacementBatchCap, _cap);
    });

    test('a cluster of exactly 400 targets is sent as one batch', () async {
      place(_people(_cap));
      await _drain();

      expect(anchors.applies, hasLength(1));
      expect(anchors.applies.single, hasLength(_cap));
    });

    test('clusters that together fit in 400 share one batch', () async {
      place(_people(_cap ~/ 2, prefix: 'A'));
      place(_people(_cap ~/ 2, prefix: 'B'));
      await _drain();

      expect(anchors.applies, hasLength(1));
      expect(anchors.applies.single, hasLength(_cap));
    });

    test(
      'queued clusters are split only when they exceed 400 together',
      () async {
        place(_people(_cap, prefix: 'A'));
        place(_people(1, prefix: 'B'));
        await _drain();
        expect(anchors.applies, hasLength(1));
        expect(anchors.applies.first, hasLength(_cap));

        anchors.acknowledge(0, after: _cap + 1);
        await _drain();

        expect(anchors.applies, hasLength(2));
        expect(anchors.applies.last, hasLength(1));
      },
    );

    test('queued clusters totalling 401 never share one batch', () async {
      place(_people(_cap ~/ 2, prefix: 'A'));
      place(_people(_cap ~/ 2 + 1, prefix: 'B'));
      await _drain();
      expect(anchors.applies, isNotEmpty);
      expect(anchors.applies.first.length, lessThanOrEqualTo(_cap));

      anchors.acknowledge(0, after: anchors.applies.first.length + 1);
      await _drain();

      expect(anchors.applies, hasLength(2));
      expect(
        anchors.applies.map((batch) => batch.length),
        everyElement(lessThanOrEqualTo(_cap)),
      );
      expect(
        anchors.applies.expand((batch) => batch).map((op) => op.target).toSet(),
        hasLength(_cap + 1),
      );
    });
  });
}
