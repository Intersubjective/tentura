import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/test_realtime_sync.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';

import '../../support/constellation_store_fixture.dart';

const _viewer = 'ego';

ConstellationAnchor _anchor({
  required String personId,
  required BigInt revision,
  double x = 1,
}) => ConstellationAnchor(
  target: ConstellationAnchorTarget.person(personId),
  position: const ConstellationAnchorPosition(
    xUnits: 1,
    yUnits: 2,
    coordinateSpaceVersion: 1,
  ),
  revision: ConstellationAnchorRevision(revision),
  placedAt: DateTime.utc(2026, 9, 11),
);

ConstellationAnchorProjection _projection({
  required BigInt revision,
  List<ConstellationAnchor> anchors = const [],
}) => ConstellationAnchorProjection(
  revision: ConstellationAnchorRevision(revision),
  anchors: anchors,
  pinnedPeers: const [],
  pinnedRequests: const [],
  supportPeers: const [],
  supportEdges: const [],
  serverFilteredBeaconIds: const [],
  serverFilteredBeaconCount: 0,
);

final class _FakeFieldRepository implements ConstellationRepositoryPort {
  _FakeFieldRepository(this.projections);

  final List<ConstellationAnchorProjection> projections;
  int fetchCount = 0;
  final List<ConstellationProjection> fetchProjections = [];
  Completer<void> fetchGate = Completer<void>()..complete();
  ConstellationFieldMembershipFilters? lastMembershipFilters;
  Object? fetchError;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fetchCount++;
    fetchProjections.add(projection);
    lastMembershipFilters = membershipFilters;
    if (fetchError != null) {
      throw fetchError!;
    }
    if (!fetchGate.isCompleted) {
      await fetchGate.future;
    }
    final index = (fetchCount - 1).clamp(0, projections.length - 1);
    return ConstellationField(
      loadedAt: DateTime.utc(2026, 9, 11),
      context: '',
      anchorProjection: projections[index],
    );
  }
}

final class _FakeAnchorRepository implements ConstellationWriteFake {
  @override
  Future<ConstellationAnchorResetResult> reset({required String clientOpId}) =>
      throw UnimplementedError('reset is not used by this test');

  Completer<void> upsertGate = Completer<void>()..complete();
  Completer<void> deleteGate = Completer<void>()..complete();
  int upsertCount = 0;
  int deleteCount = 0;
  Object? upsertError;
  Object? deleteError;
  ConstellationAnchorUpsertResult? upsertResult;
  ConstellationAnchorDeleteResult? deleteResult;
  int? failOnUpsertIndex;
  Set<ConstellationAnchorTarget> failTargets = {};
  final List<ConstellationAnchorTarget> upsertTargets = [];

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) => throw UnimplementedError();

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    upsertCount++;
    upsertTargets.add(target);
    await upsertGate.future;
    if (failOnUpsertIndex != null && upsertCount == failOnUpsertIndex) {
      throw upsertError ?? StateError('failed at $upsertCount');
    }
    if (failTargets.contains(target)) {
      throw upsertError ?? StateError('failed for ${target.id}');
    }
    if (upsertError != null &&
        failOnUpsertIndex == null &&
        failTargets.isEmpty) {
      throw upsertError!;
    }
    return upsertResult ??
        ConstellationAnchorUpsertResult(
          anchor: ConstellationAnchor(
            target: target,
            position: position,
            revision: ConstellationAnchorRevision(BigInt.from(upsertCount + 1)),
            placedAt: DateTime.utc(2026, 9, 11, 1),
          ),
          revision: ConstellationAnchorRevision(BigInt.from(upsertCount + 1)),
        );
  }

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) async {
    deleteCount++;
    await deleteGate.future;
    if (deleteError != null) {
      throw deleteError!;
    }
    return deleteResult ??
        ConstellationAnchorDeleteResult(
          target: target,
          revision: ConstellationAnchorRevision(BigInt.from(3)),
        );
  }
}

ConstellationAnchorCase _case({
  required _FakeFieldRepository fieldRepo,
  required _FakeAnchorRepository anchorRepo,
}) => ConstellationAnchorCase(
  env: const Env.fromEnvironment(),
  logger: Logger('ConstellationAnchorCaseTest'),
);

void main() {
  group('constellation anchor reads', () {
    late _FakeFieldRepository fieldRepo;
    late _FakeAnchorRepository anchorRepo;
    late TestRealtimeSyncPort port;
    late RealtimeSyncCase realtime;
    late ConstellationAnchorCase case_;
    late ConstellationStoreFixture readFixture;
    late StoreLease readLease;

    Future<ConstellationFieldStoreCase> readStore() async {
      readFixture = ConstellationStoreFixture(
        fieldRepo,
        accountId: _viewer,
        realtime: realtime,
      );
      readLease = readFixture.store.lease();
      addTearDown(readLease.dispose);
      await readFixture.ready();
      return readFixture.store;
    }

    void anchorHint() => port.emitChange(
      const RealtimeEntityChange(
        kind: RealtimeEntityKind.constellationAnchor,
        aggregateId: _viewer,
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
      ),
    );

    setUp(() {
      fieldRepo = _FakeFieldRepository([
        _projection(revision: BigInt.one),
        _projection(
          revision: BigInt.two,
          anchors: [_anchor(personId: 'p1', revision: BigInt.two)],
        ),
      ]);
      anchorRepo = _FakeAnchorRepository();
      final sync = buildTestRealtimeSync();
      port = sync.port;
      realtime = sync.case_;
      case_ = _case(
        fieldRepo: fieldRepo,
        anchorRepo: anchorRepo,
      );
      case_.activate(viewerAccountId: _viewer);
      case_.adoptConfirmedProjection(_projection(revision: BigInt.one));
    });

    tearDown(() async {
      case_.deactivate();
      await case_.dispose();
      await port.dispose();
    });

    test(
      'the store alone reads anchor hints for the current account',
      () async {
        final store = await readStore();
        var emissions = 0;
        final sub = store.changes.listen((_) => emissions++);
        addTearDown(sub.cancel);
        port.emitChange(
          const RealtimeEntityChange(
            kind: RealtimeEntityKind.constellationAnchor,
            aggregateId: 'other-viewer',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(emissions, 0);
        expect(fieldRepo.fetchCount, 0);
        anchorHint();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(emissions, 1);
        expect(fieldRepo.fetchProjections, [ConstellationProjection.anchors]);
      },
    );

    test(
      'the store coalesces in-flight ANCHORS with one queued rerun',
      () async {
        await readStore();
        fieldRepo.fetchGate = Completer<void>();
        anchorHint();
        await Future<void>.delayed(Duration.zero);
        expect(fieldRepo.fetchCount, 1);
        anchorHint();
        fieldRepo.fetchGate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(fieldRepo.fetchProjections, [
          ConstellationProjection.anchors,
          ConstellationProjection.anchors,
        ]);
      },
    );

    test(
      'the store reconnect catch-up requests one FULL without ANCHORS',
      () async {
        await readStore();
        port.emitCatchUp(accountId: _viewer);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(fieldRepo.fetchProjections, [ConstellationProjection.full]);
      },
    );

    test(
      'the store refreshes membership payload at equal anchor revision',
      () async {
        fieldRepo.projections
          ..clear()
          ..add(
            _projection(
              revision: BigInt.one,
              anchors: [_anchor(personId: 'p1', revision: BigInt.one)],
            ),
          )
          ..add(
            _projection(
              revision: BigInt.one,
              anchors: [_anchor(personId: 'p2', revision: BigInt.one)],
            ),
          );
        final store = await readStore();
        await store.requestRefresh(ConstellationRefreshReason.load);
        await store.requestRefresh(ConstellationRefreshReason.load);
        expect(store.current.coveredRevision.value, BigInt.one);
        expect(
          store
              .current
              .field!
              .resolvedAnchorProjection
              .anchors
              .single
              .target
              .id,
          'p2',
        );
      },
    );

    test('the store discards older ANCHORS projection revisions', () async {
      fieldRepo.projections
        ..clear()
        ..add(
          _projection(
            revision: BigInt.two,
            anchors: [_anchor(personId: 'p1', revision: BigInt.two)],
          ),
        )
        ..add(
          _projection(
            revision: BigInt.one,
            anchors: [_anchor(personId: 'p2', revision: BigInt.one)],
          ),
        );
      final store = await readStore();
      await store.requestRefresh(ConstellationRefreshReason.load);
      anchorHint();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.current.coveredRevision.value, BigInt.two);
      expect(
        store.current.field!.resolvedAnchorProjection.anchors.single.target.id,
        'p1',
      );
    });

    // The case keeps only the confirmed cache; its revision rules stay covered
    // directly on the case, beside the store-level read tests.
    test('confirmed cache: equal revision still refreshes membership', () {
      final incoming = _projection(
        revision: BigInt.one,
        anchors: [_anchor(personId: 'p1', revision: BigInt.one)],
      );
      expect(case_.applyIncomingProjection(incoming, generation: 1), isTrue);
      expect(case_.confirmedProjection.anchors, hasLength(1));
    });

    test('confirmed cache: discards older projection revisions', () {
      final incoming = _projection(revision: BigInt.zero);
      expect(case_.applyIncomingProjection(incoming, generation: 1), isFalse);
    });

    test('adoptConfirmedProjection rejects stale FULL revision', () {
      case_.adoptConfirmedProjection(
        _projection(
          revision: BigInt.two,
          anchors: [_anchor(personId: 'p1', revision: BigInt.two)],
        ),
      );
      final adopted = case_.adoptConfirmedProjection(
        _projection(
          revision: BigInt.one,
          anchors: [_anchor(personId: 'p1', revision: BigInt.one, x: 9)],
        ),
      );
      expect(adopted, isFalse);
      expect(case_.confirmedProjection.revision.value, BigInt.two);
      expect(case_.confirmedProjection.anchors.single.position.xUnits, 1);
    });

    test('activate for a new account accepts a lower revision', () {
      case_.adoptConfirmedProjection(
        _projection(
          revision: BigInt.from(20),
          anchors: [_anchor(personId: 'p1', revision: BigInt.from(20))],
        ),
      );
      expect(case_.confirmedProjection.revision.value, BigInt.from(20));
      case_.activate(viewerAccountId: 'other-account');
      expect(case_.confirmedProjection.anchors, isEmpty);
      expect(
        case_.adoptConfirmedProjection(_projection(revision: BigInt.one)),
        isTrue,
      );
      expect(case_.confirmedProjection.revision.value, BigInt.one);
    });
  });
}
