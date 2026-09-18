import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';

import '../../support/test_realtime_sync.dart';

const _viewer = 'ego';

ConstellationAnchor _anchor({
  required String personId,
  required BigInt revision,
  double x = 1,
  double y = 2,
}) =>
    ConstellationAnchor(
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
}) =>
    ConstellationAnchorProjection(
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

final class _FakeAnchorRepository implements ConstellationAnchorRepositoryPort {
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
  required RealtimeSyncCase realtime,
}) =>
    ConstellationAnchorCase(
      fieldRepo,
      anchorRepo,
      realtime,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationAnchorCaseTest'),
    );

void main() {
  group('ConstellationAnchorCase', () {
    late _FakeFieldRepository fieldRepo;
    late _FakeAnchorRepository anchorRepo;
    late TestRealtimeSyncPort port;
    late RealtimeSyncCase realtime;
    late ConstellationAnchorCase case_;

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
      case_ = _case(fieldRepo: fieldRepo, anchorRepo: anchorRepo, realtime: realtime);
      case_.activate(viewerAccountId: _viewer);
      case_.adoptConfirmedProjection(_projection(revision: BigInt.one));
    });

    tearDown(() async {
      case_.deactivate();
      await case_.dispose();
      await port.dispose();
    });

    test('subscribes only to constellation_anchor for viewer account', () async {
      var hints = 0;
      final sub = case_.refreshSignals.listen((_) => hints++);
      port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: 'other-viewer',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(hints, 0);

      port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: _viewer,
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(hints, 1);
      await sub.cancel();
    });

    test('coalesces in-flight ANCHORS to one fetch plus one queued rerun', () async {
      fieldRepo.fetchGate = Completer<void>();
      port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: _viewer,
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fieldRepo.fetchCount, 1);

      port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: _viewer,
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      fieldRepo.fetchGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(fieldRepo.fetchCount, 2);
    });

    test('reconnect catch-up requests ANCHORS once', () async {
      port.emitCatchUp(accountId: _viewer);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fieldRepo.fetchCount, 1);
    });

    test('equal revision still refreshes membership payload', () {
      final incoming = _projection(
        revision: BigInt.one,
        anchors: [_anchor(personId: 'p1', revision: BigInt.one)],
      );
      expect(case_.applyIncomingProjection(incoming, generation: 1), isTrue);
      expect(case_.confirmedProjection.anchors, hasLength(1));
    });

    test('discards older projection revisions', () {
      final incoming = _projection(revision: BigInt.zero);
      expect(case_.applyIncomingProjection(incoming, generation: 1), isFalse);
    });

    test('echo-before-response settles with ANCHORS fetch after upsert', () async {
      anchorRepo.upsertGate = Completer<void>();
      final target = ConstellationAnchorTarget.person('p1');
      const position = ConstellationAnchorPosition(
        xUnits: 0,
        yUnits: 0,
        coordinateSpaceVersion: 1,
      );
      final write = case_.upsert(
        target: target,
        position: position,
        generation: 1,
      );
      port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: _viewer,
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fieldRepo.fetchCount, 1);

      anchorRepo.upsertGate.complete();
      final outcome = await write;
      expect(outcome.kind, ConstellationAnchorWriteOutcomeKind.succeeded);
      expect(anchorRepo.upsertCount, 1);
      expect(fieldRepo.fetchCount, greaterThanOrEqualTo(2));
    });

    test('failed write fetches ANCHORS once and marks sync pending', () async {
      anchorRepo.upsertError = StateError('network');
      final outcome = await case_.upsert(
        target: ConstellationAnchorTarget.person('p1'),
        position: const ConstellationAnchorPosition(
          xUnits: 0,
          yUnits: 0,
          coordinateSpaceVersion: 1,
        ),
        generation: 1,
      );
      expect(outcome.kind, ConstellationAnchorWriteOutcomeKind.failed);
      expect(case_.syncPending, isTrue);
      expect(anchorRepo.upsertCount, 1);
      expect(fieldRepo.fetchCount, 1);
    });

    test('mutation and recovery failures still complete with sync pending', () async {
      anchorRepo.upsertError = StateError('network');
      fieldRepo.fetchError = StateError('offline');
      final outcome = await case_.upsert(
        target: ConstellationAnchorTarget.person('p1'),
        position: const ConstellationAnchorPosition(
          xUnits: 0,
          yUnits: 0,
          coordinateSpaceVersion: 1,
        ),
        generation: 1,
      );
      expect(outcome.kind, ConstellationAnchorWriteOutcomeKind.failed);
      expect(outcome.projection, isNotNull);
      expect(case_.syncPending, isTrue);
      expect(case_.hasPendingWrite, isFalse);
      expect(anchorRepo.upsertCount, 1);
      expect(fieldRepo.fetchCount, 1);
    });

    test('successful mutation keeps confirmation when recovery read fails', () async {
      fieldRepo.fetchError = StateError('offline');
      final outcome = await case_.upsert(
        target: ConstellationAnchorTarget.person('p1'),
        position: const ConstellationAnchorPosition(
          xUnits: 2,
          yUnits: 3,
          coordinateSpaceVersion: 1,
        ),
        generation: 1,
      );
      expect(outcome.kind, ConstellationAnchorWriteOutcomeKind.succeeded);
      expect(case_.syncPending, isTrue);
      expect(case_.hasPendingWrite, isFalse);
      expect(case_.confirmedProjection.anchors, isNotEmpty);
      expect(case_.confirmedProjection.anchors.single.position.xUnits, 2);
    });

    test('stale generation discards refresh and write results', () async {
      case_.bindLoadGeneration(2);
      final result = await case_.refreshAnchors(generation: 1);
      expect(result, isNull);

      final outcome = await case_.upsert(
        target: ConstellationAnchorTarget.person('p1'),
        position: const ConstellationAnchorPosition(
          xUnits: 0,
          yUnits: 0,
          coordinateSpaceVersion: 1,
        ),
        generation: 1,
      );
      expect(outcome.kind, ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded);
      expect(anchorRepo.upsertCount, 0);
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

    test('websocket refresh uses synced membership filters', () async {
      const filters = ConstellationFieldMembershipFilters(
        showClosed: true,
        participatedOnly: true,
      );
      case_.syncMembershipFilters(filters);
      port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: _viewer,
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fieldRepo.lastMembershipFilters, filters);
    });

    test('offline failure clears sync pending after reconnect catch-up', () async {
      anchorRepo.upsertError = StateError('network');
      await case_.upsert(
        target: ConstellationAnchorTarget.person('p1'),
        position: const ConstellationAnchorPosition(
          xUnits: 0,
          yUnits: 0,
          coordinateSpaceVersion: 1,
        ),
        generation: 1,
      );
      expect(case_.syncPending, isTrue);

      fieldRepo.projections[1] = _projection(
        revision: BigInt.from(3),
        anchors: [_anchor(personId: 'p1', revision: BigInt.from(3))],
      );
      port.emitCatchUp(accountId: _viewer);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(case_.syncPending, isFalse);
      expect(case_.confirmedProjection.revision.value, BigInt.from(3));
    });

    test('counts writes accurately', () async {
      await case_.upsert(
        target: ConstellationAnchorTarget.person('p1'),
        position: const ConstellationAnchorPosition(
          xUnits: 1,
          yUnits: 1,
          coordinateSpaceVersion: 1,
        ),
        generation: 1,
      );
      await case_.deleteAnchor(
        target: ConstellationAnchorTarget.person('p1'),
        generation: 1,
      );
      expect(case_.writeCount, 2);
    });

    test('queued refresh uses latest filters after an in-flight read', () async {
      fieldRepo.fetchGate = Completer<void>();
      port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: _viewer,
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fieldRepo.fetchCount, 1);
      const nextFilters = ConstellationFieldMembershipFilters(showClosed: true);
      case_.syncMembershipFilters(nextFilters);
      port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: _viewer,
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      fieldRepo.fetchGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(fieldRepo.fetchCount, 2);
      expect(fieldRepo.lastMembershipFilters, nextFilters);
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

    test('stale deactivate does not detach the current screen', () async {
      case_.deactivate(token: 0);
      port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: _viewer,
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fieldRepo.fetchCount, 1);
    });

    test('deactivate does not drop an in-flight same-account write', () async {
      anchorRepo.upsertGate = Completer<void>();
      final write = case_.upsert(
        target: ConstellationAnchorTarget.person('p1'),
        position: const ConstellationAnchorPosition(
          xUnits: 0,
          yUnits: 0,
          coordinateSpaceVersion: 1,
        ),
        generation: case_.lifecycleToken,
      );
      await Future<void>.delayed(Duration.zero);
      expect(case_.hasPendingWrite, isTrue);
      case_.deactivate(token: case_.lifecycleToken);
      expect(case_.hasPendingWrite, isTrue);
      anchorRepo.upsertGate.complete();
      final outcome = await write;
      expect(outcome.kind, ConstellationAnchorWriteOutcomeKind.succeeded);
      expect(anchorRepo.upsertCount, 1);
    });

    test('second write is refused while one command is pending', () async {
      anchorRepo.upsertGate = Completer<void>();
      final first = case_.upsert(
        target: ConstellationAnchorTarget.person('p1'),
        position: const ConstellationAnchorPosition(
          xUnits: 0,
          yUnits: 0,
          coordinateSpaceVersion: 1,
        ),
        generation: case_.lifecycleToken,
      );
      await Future<void>.delayed(Duration.zero);
      final second = await case_.upsert(
        target: ConstellationAnchorTarget.person('p2'),
        position: const ConstellationAnchorPosition(
          xUnits: 1,
          yUnits: 1,
          coordinateSpaceVersion: 1,
        ),
        generation: case_.lifecycleToken,
      );
      expect(second.kind, ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded);
      anchorRepo.upsertGate.complete();
      await first;
      expect(anchorRepo.upsertCount, 1);
    });

    test('upsertAll aborts companions when parent mutation fails', () async {
      anchorRepo.failOnUpsertIndex = 1;
      anchorRepo.upsertError = StateError('parent failed');
      fieldRepo.projections.add(
        _projection(
          revision: BigInt.two,
          anchors: [_anchor(personId: 'p1', revision: BigInt.two)],
        ),
      );
      final outcome = await case_.upsertAll(
        parentTarget: ConstellationAnchorTarget.person('p1'),
        parentPosition: const ConstellationAnchorPosition(
          xUnits: 3,
          yUnits: 3,
          coordinateSpaceVersion: 1,
        ),
        companions: [
          (
            target: ConstellationAnchorTarget.beacon('B1'),
            position: const ConstellationAnchorPosition(
              xUnits: 4,
              yUnits: 4,
              coordinateSpaceVersion: 1,
            ),
          ),
        ],
        generation: case_.lifecycleToken,
      );
      expect(outcome.kind, ConstellationAnchorWriteOutcomeKind.failed);
      expect(anchorRepo.upsertCount, 1);
      expect(case_.writeCount, 1);
      expect(case_.pendingWriteTargets, isEmpty);
    });

    test('upsertAll mixed fail names missed companions after recovery', () async {
      anchorRepo.failTargets = {ConstellationAnchorTarget.beacon('B1')};
      fieldRepo.projections
        ..clear()
        ..add(
          _projection(
            revision: BigInt.from(3),
            anchors: [
              ConstellationAnchor(
                target: ConstellationAnchorTarget.person('p1'),
                position: const ConstellationAnchorPosition(
                  xUnits: 3,
                  yUnits: 3,
                  coordinateSpaceVersion: 1,
                ),
                revision: ConstellationAnchorRevision(BigInt.from(3)),
                placedAt: DateTime.utc(2026, 9, 11),
              ),
              ConstellationAnchor(
                target: ConstellationAnchorTarget.beacon('B1'),
                position: const ConstellationAnchorPosition(
                  xUnits: 1,
                  yUnits: 1,
                  coordinateSpaceVersion: 1,
                ),
                revision: ConstellationAnchorRevision(BigInt.from(3)),
                placedAt: DateTime.utc(2026, 9, 11),
              ),
            ],
          ),
        );
      final outcome = await case_.upsertAll(
        parentTarget: ConstellationAnchorTarget.person('p1'),
        parentPosition: const ConstellationAnchorPosition(
          xUnits: 3,
          yUnits: 3,
          coordinateSpaceVersion: 1,
        ),
        companions: [
          (
            target: ConstellationAnchorTarget.beacon('B1'),
            position: const ConstellationAnchorPosition(
              xUnits: 4,
              yUnits: 4,
              coordinateSpaceVersion: 1,
            ),
          ),
        ],
        companionTitles: const {'B1': 'Need help'},
        generation: case_.lifecycleToken,
      );
      expect(outcome.kind, ConstellationAnchorWriteOutcomeKind.failed);
      expect(outcome.failureMessage, contains('Need help'));
      expect(anchorRepo.upsertCount, 2);
      expect(case_.writeCount, 1);
    });
  });
}
