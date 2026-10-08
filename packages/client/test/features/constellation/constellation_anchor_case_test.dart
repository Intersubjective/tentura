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
  fieldRepo,
  anchorRepo,
  env: const Env.fromEnvironment(),
  logger: Logger('ConstellationAnchorCaseTest'),
);

void main() {
  group('constellation anchor reads and writes', () {
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

    test(
      'echo-before-response settles with ANCHORS fetch after upsert',
      () async {
        await readStore();
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
      },
    );

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

    test(
      'mutation and recovery failures still complete with sync pending',
      () async {
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
      },
    );

    test(
      'write slot frees once the mutation lands, before the recovery read',
      () async {
        fieldRepo.fetchGate = Completer<void>();
        final write = case_.upsert(
          target: ConstellationAnchorTarget.person('p1'),
          position: const ConstellationAnchorPosition(
            xUnits: 2,
            yUnits: 3,
            coordinateSpaceVersion: 1,
          ),
          generation: 1,
        );
        await Future<void>.delayed(Duration.zero);
        expect(case_.hasPendingWrite, isFalse);
        expect(case_.confirmedProjection.anchors.single.position.xUnits, 2);

        fieldRepo.fetchGate.complete();
        final outcome = await write;
        expect(outcome.kind, ConstellationAnchorWriteOutcomeKind.succeeded);
      },
    );

    test(
      'successful mutation keeps confirmation when recovery read fails',
      () async {
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
      },
    );

    test(
      'the store discards a read from the previous account generation',
      () async {
        final store = await readStore();
        fieldRepo.fetchGate = Completer<void>();
        final oldRead = store.requestRefresh(ConstellationRefreshReason.load);
        await Future<void>.delayed(Duration.zero);
        readFixture.account.add('other-account');
        await readFixture.ready();
        fieldRepo.fetchGate.complete();
        await oldRead;
        expect(store.current.field, isNull);
        await store.requestRefresh(ConstellationRefreshReason.load);
        expect(store.current.coveredRevision.value, BigInt.two);
      },
    );

    test(
      'a stale write generation does not issue an anchor mutation',
      () async {
        case_.bindLoadGeneration(2);

        final outcome = await case_.upsert(
          target: ConstellationAnchorTarget.person('p1'),
          position: const ConstellationAnchorPosition(
            xUnits: 0,
            yUnits: 0,
            coordinateSpaceVersion: 1,
          ),
          generation: 1,
        );
        expect(
          outcome.kind,
          ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
        );
        expect(anchorRepo.upsertCount, 0);
      },
    );

    test(
      'the store preserves newer anchors when a FULL has a stale anchor revision',
      () async {
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
              anchors: [_anchor(personId: 'p2', revision: BigInt.one, x: 9)],
            ),
          );
        final store = await readStore();
        await store.requestRefresh(ConstellationRefreshReason.load);
        await store.requestRefresh(ConstellationRefreshReason.load);
        expect(store.current.coveredRevision.value, BigInt.two);
        expect(
          store
              .current
              .field!
              .resolvedAnchorProjection
              .anchors
              .single
              .target
              .id,
          'p1',
        );
        expect(
          store
              .current
              .field!
              .resolvedAnchorProjection
              .anchors
              .single
              .position
              .xUnits,
          1,
        );
      },
    );

    test(
      'the store websocket refresh uses the current membership filters',
      () async {
        final store = await readStore();
        const filters = ConstellationFieldMembershipFilters(
          showClosed: true,
          participatedOnly: true,
        );
        store.setMembershipFilters(filters);
        await store.requestRefresh(ConstellationRefreshReason.load);
        anchorHint();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(fieldRepo.lastMembershipFilters, filters);
        expect(fieldRepo.fetchProjections, [
          ConstellationProjection.full,
          ConstellationProjection.anchors,
        ]);
      },
    );

    test(
      'offline failure clears sync pending after reconnect catch-up',
      () async {
        final store = await readStore();
        final subscription = store.changes.listen((snapshot) {
          final projection = snapshot.field?.resolvedAnchorProjection;
          if (projection != null) case_.adoptConfirmedProjection(projection);
        });
        addTearDown(subscription.cancel);
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
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(case_.syncPending, isFalse);
        expect(case_.confirmedProjection.revision.value, BigInt.from(3));
      },
    );

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

    test(
      'the store queued refresh uses latest filters after an in-flight read',
      () async {
        final store = await readStore();
        fieldRepo.fetchGate = Completer<void>();
        anchorHint();
        await Future<void>.delayed(Duration.zero);
        expect(fieldRepo.fetchCount, 1);
        const nextFilters = ConstellationFieldMembershipFilters(
          showClosed: true,
        );
        store.setMembershipFilters(nextFilters);
        anchorHint();
        fieldRepo.fetchGate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(fieldRepo.fetchCount, 2);
        expect(fieldRepo.lastMembershipFilters, nextFilters);
      },
    );

    test(
      'the store account replacement accepts a lower anchor revision',
      () async {
        fieldRepo.projections
          ..clear()
          ..add(
            _projection(
              revision: BigInt.from(20),
              anchors: [_anchor(personId: 'p1', revision: BigInt.from(20))],
            ),
          )
          ..add(_projection(revision: BigInt.one));
        final store = await readStore();
        await store.requestRefresh(ConstellationRefreshReason.load);
        expect(store.current.coveredRevision.value, BigInt.from(20));
        readFixture.account.add('other-account');
        await readFixture.ready();
        expect(store.current.field, isNull);
        await store.requestRefresh(ConstellationRefreshReason.load);
        expect(store.current.coveredRevision.value, BigInt.one);
      },
    );

    test(
      'the store ignores an old disposed lease while another screen stays visible',
      () async {
        await readStore();
        final current = readFixture.store.lease();
        addTearDown(current.dispose);
        readLease.dispose();
        readLease.dispose();
        anchorHint();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(fieldRepo.fetchProjections, [ConstellationProjection.anchors]);
      },
    );

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
      expect(
        second.kind,
        ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
      );
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

    test(
      'upsertAll mixed fail names missed companions after recovery',
      () async {
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
      },
    );
    // The write half keeps its confirmed cache until U21; its revision rules
    // stay covered directly on the case, beside the store-level read tests.
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
