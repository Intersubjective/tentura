import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

import '../../support/test_realtime_sync.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 9, 11, 12);

ConstellationAnchor _anchor({
  required String personId,
  required BigInt revision,
  double x = 1,
  double y = 2,
}) =>
    ConstellationAnchor(
      target: ConstellationAnchorTarget.person(personId),
      position: ConstellationAnchorPosition(
        xUnits: x,
        yUnits: y,
        coordinateSpaceVersion: 1,
      ),
      revision: ConstellationAnchorRevision(revision),
      placedAt: DateTime.utc(2026, 9, 11),
    );

ConstellationAnchor _beaconAnchor({
  required String beaconId,
  required BigInt revision,
  double x = 1,
  double y = 2,
}) =>
    ConstellationAnchor(
      target: ConstellationAnchorTarget.beacon(beaconId),
      position: ConstellationAnchorPosition(
        xUnits: x,
        yUnits: y,
        coordinateSpaceVersion: 1,
      ),
      revision: ConstellationAnchorRevision(revision),
      placedAt: DateTime.utc(2026, 9, 11),
    );

ConstellationField _field({
  BigInt? revision,
  List<ConstellationAnchor> anchors = const [],
  List<ConstellationPerson> peers = const [],
  List<ConstellationPerson>? pinnedPeers,
  List<ConstellationRequest> pinnedRequests = const [],
  List<ConstellationPerson> supportPeers = const [],
  List<ConstellationTrustEdgeEntity> supportEdges = const [],
  List<ConstellationRequest> requests = const [],
}) =>
    ConstellationField(
      loadedAt: _loadedAt,
      context: '',
      peers: peers,
      requests: requests,
      anchorProjection: ConstellationAnchorProjection(
        revision: ConstellationAnchorRevision(revision ?? BigInt.one),
        anchors: anchors,
        pinnedPeers: pinnedPeers ?? peers,
        pinnedRequests: pinnedRequests,
        supportPeers: supportPeers,
        supportEdges: supportEdges,
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );

final class _HarnessFieldRepository implements ConstellationRepositoryPort {
  _HarnessFieldRepository(this.fields);

  final List<ConstellationField> fields;
  int fetchCount = 0;
  Completer<void> fullGate = Completer<void>()..complete();
  Completer<void> anchorsGate = Completer<void>()..complete();

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fetchCount++;
    if (projection == ConstellationProjection.full) {
      if (!fullGate.isCompleted) {
        await fullGate.future;
      }
    } else {
      if (!anchorsGate.isCompleted) {
        await anchorsGate.future;
      }
    }
    final index = (fetchCount - 1).clamp(0, fields.length - 1);
    return fields[index];
  }
}

final class _HarnessAnchorRepository implements ConstellationAnchorRepositoryPort {
  Completer<void> upsertGate = Completer<void>()..complete();
  Completer<void> deleteGate = Completer<void>()..complete();
  int upsertCount = 0;
  int deleteCount = 0;
  Object? upsertError;
  Object? deleteError;
  final List<ConstellationAnchorTarget> upsertTargets = [];
  /// When set, the Nth upsert (1-based) throws [upsertError] or a default error.
  int? failOnUpsertIndex;
  /// When set, upserts for these targets throw after awaiting the gate.
  Set<ConstellationAnchorTarget> failTargets = {};

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    upsertCount++;
    upsertTargets.add(target);
    await upsertGate.future;
    if (failOnUpsertIndex != null && upsertCount == failOnUpsertIndex) {
      throw upsertError ?? StateError('failed at index $upsertCount');
    }
    if (failTargets.contains(target)) {
      throw upsertError ?? StateError('failed for ${target.id}');
    }
    if (upsertError != null &&
        failOnUpsertIndex == null &&
        failTargets.isEmpty) {
      throw upsertError!;
    }
    return ConstellationAnchorUpsertResult(
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
    return ConstellationAnchorDeleteResult(
      target: target,
      revision: ConstellationAnchorRevision(BigInt.from(3)),
    );
  }
}

final class _FakeForwardRepository implements ForwardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<({
  ConstellationCubit cubit,
  _HarnessFieldRepository fieldRepo,
  _HarnessAnchorRepository anchorRepo,
  TestRealtimeSyncPort port,
  ConstellationAnchorCase anchorCase,
})> _harness({
  List<ConstellationField>? fields,
  bool loadOnCreate = true,
}) async {
  final fieldRepo = _HarnessFieldRepository(
    fields ??
        [
          _field(
            peers: const [ConstellationPerson(id: 'p1', displayName: 'Peer')],
            anchors: [_anchor(personId: 'p1', revision: BigInt.one)],
          ),
        ],
  );
  final anchorRepo = _HarnessAnchorRepository();
  final sync = buildTestRealtimeSync();
  final anchorCase = ConstellationAnchorCase(
    fieldRepo,
    anchorRepo,
    sync.case_,
    env: const Env.fromEnvironment(),
    logger: Logger('ConstellationAnchorCubitTest'),
  );
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      fieldRepo,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationAnchorCubitTest'),
    ),
    anchorCase: anchorCase,
    viewer: _ego,
    forwardRepository: _FakeForwardRepository(),
    loadOnCreate: false,
  );
  if (loadOnCreate) {
    await cubit.load();
  }
  return (
    cubit: cubit,
    fieldRepo: fieldRepo,
    anchorRepo: anchorRepo,
    port: sync.port,
    anchorCase: anchorCase,
  );
}

void main() {
  group('ConstellationAnchorCubit', () {
    test('load stores composition from field case', () async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);

      expect(harness.cubit.state.composition, isNotNull);
      expect(harness.cubit.state.composition!.anchorOverlay.anchors, hasLength(1));
    });

    test('cancel during drag restores idle without writes', () async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      final target = ConstellationAnchorTarget.person('p1');

      harness.cubit.beginDragNew(target: target);
      expect(
        harness.cubit.state.placementPhase,
        ConstellationPlacementPhase.draggingNew,
      );

      harness.cubit.cancelPlacement();
      expect(harness.cubit.state.placementPhase, ConstellationPlacementPhase.idle);
      expect(harness.anchorRepo.upsertCount, 0);
    });

    test('cancel after drop while write pending does not clear presentation', () async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      harness.anchorRepo.upsertGate = Completer<void>();
      final target = ConstellationAnchorTarget.person('p1');
      final drop = harness.cubit.onExistingNodeDrop(
        target: target,
        sceneCentre: const Offset(2100, 2100),
      );
      await Future<void>.delayed(Duration.zero);

      harness.cubit.cancelPlacement();
      expect(harness.anchorRepo.upsertCount, 1);

      harness.anchorRepo.upsertGate.complete();
      await drop;
      expect(harness.cubit.isAnchored(target), isTrue);
    });

    test('remote move during drag defers active target and skips layout', () async {
      const peer = ConstellationPerson(id: 'p1', displayName: 'Peer 1');
      const other = ConstellationPerson(id: 'p2', displayName: 'Peer 2');
      const request = ConstellationRequest(
        id: 'B1',
        authorId: 'p1',
        title: 'Need help',
        status: 0,
      );
      final harness = await _harness(
        fields: [
          _field(
            peers: const [peer, other],
            requests: const [request],
            pinnedRequests: const [request],
            anchors: [
              _anchor(personId: 'p1', revision: BigInt.one),
              _anchor(personId: 'p2', revision: BigInt.one, x: 2, y: 2),
              _beaconAnchor(beaconId: 'B1', revision: BigInt.one, x: 1.5, y: 1.5),
            ],
          ),
        ],
      );
      addTearDown(harness.cubit.close);
      final reconciliations = harness.cubit.layoutReconciliationCount;
      final target = ConstellationAnchorTarget.person('p1');
      final companion = ConstellationAnchorTarget.beacon('B1');
      harness.cubit.beginDragExisting(target: target);

      harness.fieldRepo.fields.add(
        _field(
          revision: BigInt.two,
          peers: const [peer, other],
          requests: const [request],
          pinnedRequests: const [request],
          anchors: [
            _anchor(personId: 'p1', revision: BigInt.two, x: 3, y: 4),
            _anchor(personId: 'p2', revision: BigInt.two, x: 5, y: 6),
            _beaconAnchor(beaconId: 'B1', revision: BigInt.two, x: 9, y: 9),
          ],
        ),
      );
      harness.port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: 'ego',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(harness.cubit.state.deferredRefreshTargets, {target, companion});
      expect(
        harness.cubit.state.confirmedProjection!.revision.value,
        BigInt.two,
      );
      expect(
        harness.cubit.state.composition!.anchorOverlay.anchors
            .singleWhere((anchor) => anchor.target.id == 'p1')
            .position
            .xUnits,
        1,
      );
      expect(
        harness.cubit.state.composition!.anchorOverlay.anchors
            .singleWhere((anchor) => anchor.target.id == 'p2')
            .position
            .xUnits,
        5,
      );
      expect(
        harness.cubit.state.composition!.anchorOverlay.anchors
            .singleWhere((anchor) => anchor.target == companion)
            .position
            .xUnits,
        1.5,
      );
      expect(harness.cubit.layoutReconciliationCount, reconciliations);
    });

    test('draggingNew incoming refresh defers active target', () async {
      const peer = ConstellationPerson(id: 'p1', displayName: 'Peer 1');
      const other = ConstellationPerson(id: 'p2', displayName: 'Peer 2');
      const request = ConstellationRequest(
        id: 'B2',
        authorId: 'p2',
        title: 'Open ask',
        status: 0,
      );
      final harness = await _harness(
        fields: [
          _field(
            peers: const [peer, other],
            requests: const [request],
            pinnedRequests: const [request],
            anchors: [
              _anchor(personId: 'p1', revision: BigInt.one),
              _beaconAnchor(beaconId: 'B2', revision: BigInt.one, x: 2, y: 2),
            ],
          ),
        ],
      );
      addTearDown(harness.cubit.close);
      final target = ConstellationAnchorTarget.person('p2');
      final companion = ConstellationAnchorTarget.beacon('B2');
      harness.cubit.beginDragNew(target: target);

      harness.fieldRepo.fields.add(
        _field(
          revision: BigInt.two,
          peers: const [peer, other],
          requests: const [request],
          pinnedRequests: const [request],
          anchors: [
            _anchor(personId: 'p1', revision: BigInt.two, x: 3, y: 4),
            _beaconAnchor(beaconId: 'B2', revision: BigInt.two, x: 7, y: 7),
          ],
        ),
      );
      harness.port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: 'ego',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(harness.cubit.state.deferredRefreshTargets, {target, companion});
      expect(
        harness.cubit.state.confirmedProjection!.revision.value,
        BigInt.two,
      );
    });

    test('remote delete then drop still upserts once', () async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      final target = ConstellationAnchorTarget.person('p1');
      harness.cubit.beginDragExisting(target: target);

      harness.fieldRepo.fields.add(
        _field(
          revision: BigInt.two,
          peers: const [ConstellationPerson(id: 'p1', displayName: 'Peer')],
          anchors: const [],
        ),
      );
      harness.port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: 'ego',
          operation: RealtimeOperation.delete,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await harness.cubit.onExistingNodeDrop(
        target: target,
        sceneCentre: const Offset(2100, 2100),
      );

      expect(harness.anchorRepo.upsertCount, 1);
    });

    test('failed write rolls back with exactly one reconciliation bump', () async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      final reconciliations = harness.cubit.layoutReconciliationCount;
      harness.anchorRepo.upsertError = StateError('failed');

      await harness.cubit.onExistingNodeDrop(
        target: ConstellationAnchorTarget.person('p1'),
        sceneCentre: const Offset(2100, 2100),
      );

      expect(harness.cubit.state.placementFailureMessage, isNotNull);
      expect(harness.cubit.state.syncPending, isTrue);
      expect(harness.cubit.writeCount, 1);
      expect(harness.anchorCase.anchorsFetchCount, 1);
      expect(
        harness.cubit.layoutReconciliationCount,
        reconciliations + 1,
      );
    });

    test('offline recovery clears sync pending after reconnect catch-up', () async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      harness.anchorRepo.upsertError = StateError('offline');

      await harness.cubit.onExistingNodeDrop(
        target: ConstellationAnchorTarget.person('p1'),
        sceneCentre: const Offset(2100, 2100),
      );
      expect(harness.cubit.state.syncPending, isTrue);

      harness.fieldRepo.fields.add(
        _field(
          revision: BigInt.from(4),
          peers: const [ConstellationPerson(id: 'p1', displayName: 'Peer')],
          anchors: [_anchor(personId: 'p1', revision: BigInt.from(4), x: 2, y: 2)],
        ),
      );
      harness.port.emitCatchUp(accountId: 'ego');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(harness.cubit.state.syncPending, isFalse);
      expect(
        harness.cubit.state.confirmedProjection!.revision.value,
        BigInt.from(4),
      );
    });

    test('stale FULL after ANCHORS does not revert confirmed anchors', () async {
      final harness = await _harness(loadOnCreate: false);
      addTearDown(harness.cubit.close);
      harness.fieldRepo.fields
        ..clear()
        ..add(
          _field(
            revision: BigInt.one,
            peers: const [ConstellationPerson(id: 'p1', displayName: 'Peer')],
            anchors: [_anchor(personId: 'p1', revision: BigInt.one)],
          ),
        );
      await harness.cubit.load();
      expect(
        harness.cubit.state.confirmedProjection!.revision.value,
        BigInt.one,
      );

      harness.fieldRepo.fields.add(
        _field(
          revision: BigInt.two,
          peers: const [ConstellationPerson(id: 'p1', displayName: 'Peer')],
          anchors: [_anchor(personId: 'p1', revision: BigInt.two, x: 3, y: 4)],
        ),
      );
      harness.port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: 'ego',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        harness.cubit.state.confirmedProjection!.revision.value,
        BigInt.two,
      );

      harness.fieldRepo.fields.add(
        _field(
          revision: BigInt.one,
          peers: const [ConstellationPerson(id: 'p1', displayName: 'Peer')],
          anchors: [_anchor(personId: 'p1', revision: BigInt.one, x: 9, y: 9)],
        ),
      );
      harness.fieldRepo.fullGate = Completer<void>();
      final staleLoad = harness.cubit.load();
      harness.fieldRepo.fullGate.complete();
      await staleLoad;

      expect(
        harness.cubit.state.confirmedProjection!.revision.value,
        BigInt.two,
      );
      expect(
        harness.cubit.state.composition!.anchorOverlay.anchors.single.position.xUnits,
        3,
      );
    });

    test('unpin issues one delete and one reconciliation', () async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      final reconciliations = harness.cubit.layoutReconciliationCount;

      await harness.cubit.unpinAnchor(
        target: ConstellationAnchorTarget.person('p1'),
      );

      expect(harness.anchorRepo.deleteCount, 1);
      expect(harness.cubit.layoutReconciliationCount, reconciliations + 1);
    });

    test('pinFromText uses computeConstellationPinPosition and upserts once', () async {
      final harness = await _harness(
        fields: [
          _field(
            peers: const [ConstellationPerson(id: 'p2', displayName: 'Peer 2')],
            anchors: const [],
          ),
        ],
      );
      addTearDown(harness.cubit.close);

      await harness.cubit.pinFromText(
        target: ConstellationAnchorTarget.person('p2'),
      );

      expect(harness.anchorRepo.upsertCount, 1);
    });

    test('selection clears when target leaves composed result', () async {
      final harness = await _harness(
        fields: [
          _field(
            peers: const [ConstellationPerson(id: 'p1', displayName: 'Peer')],
            anchors: [_anchor(personId: 'p1', revision: BigInt.one)],
          ),
        ],
      );
      addTearDown(harness.cubit.close);
      harness.cubit.selectPerson('p1');
      expect(harness.cubit.state.selectedPersonId, 'p1');

      harness.fieldRepo.fields.add(
        _field(
          revision: BigInt.two,
          peers: const [],
          anchors: const [],
        ),
      );
      harness.port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: 'ego',
          operation: RealtimeOperation.delete,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(harness.cubit.state.selectedPersonId, isNull);
    });

    test('account change clears field and bumps generation', () async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      final generation = harness.cubit.state.loadGeneration;

      await harness.cubit.onAccountChanged();

      expect(harness.cubit.state.field, isNull);
      expect(harness.cubit.state.loadGeneration, greaterThan(generation));
    });

    test('route disposal does not emit after close while write continues in case', () async {
      final harness = await _harness();
      harness.anchorRepo.upsertGate = Completer<void>();
      final drop = harness.cubit.onExistingNodeDrop(
        target: ConstellationAnchorTarget.person('p1'),
        sceneCentre: const Offset(2100, 2100),
      );
      await harness.cubit.close();
      harness.anchorRepo.upsertGate.complete();
      await drop;
      expect(harness.anchorCase.writeCount, 1);
    });

    test('stale FULL load does not overwrite newer generation', () async {
      final harness = await _harness(loadOnCreate: false);
      addTearDown(harness.cubit.close);
      harness.fieldRepo.fullGate = Completer<void>();
      final first = harness.cubit.load();
      harness.cubit.onAccountChanged();
      harness.fieldRepo.fullGate.complete();
      await first;

      expect(harness.cubit.state.field, isNull);
    });

    test('overlapping drops while write pending discard the second write', () async {
      final harness = await _harness(
        fields: [
          _field(
            peers: const [
              ConstellationPerson(id: 'p1', displayName: 'Peer 1'),
              ConstellationPerson(id: 'p2', displayName: 'Peer 2'),
            ],
            anchors: const [],
          ),
        ],
      );
      addTearDown(harness.cubit.close);
      harness.anchorRepo.upsertGate = Completer<void>();
      final target = ConstellationAnchorTarget.person('p2');
      final first = harness.cubit.onNewNodeDrop(
        target: target,
        sceneCentre: const Offset(2100, 2100),
      );
      await Future<void>.delayed(Duration.zero);
      await harness.cubit.onNewNodeDrop(
        target: target,
        sceneCentre: const Offset(2200, 2200),
      );
      harness.anchorRepo.upsertGate.complete();
      await first;
      expect(harness.anchorRepo.upsertCount, 1);
    });

    test('Map builds overlay-only pinned Request author and attachment', () async {
      const author = ConstellationPerson(id: 'author-capped', displayName: 'Author');
      const request = ConstellationRequest(
        id: 'B-pin',
        authorId: 'author-capped',
        title: 'Pinned',
        status: 0,
      );
      final harness = await _harness(
        fields: [
          _field(
            peers: const [],
            pinnedPeers: const [],
            requests: const [],
            anchors: [_beaconAnchor(beaconId: 'B-pin', revision: BigInt.one)],
            pinnedRequests: const [request],
            supportPeers: const [author],
            supportEdges: const [
              ConstellationTrustEdgeEntity(src: 'ego', dst: 'author-capped', tier: 1),
            ],
          ),
        ],
      );
      addTearDown(harness.cubit.close);

      expect(harness.cubit.state.field!.peers, isEmpty);
      expect(harness.cubit.state.field!.requests, isEmpty);
      expect(
        harness.cubit.graphController.nodes.whereType<FieldRequestNode>().map((n) => n.id),
        contains('B-pin'),
      );
      expect(
        harness.cubit.graphController.nodes.whereType<FieldPersonNode>().map((n) => n.id),
        containsAll(['ego', 'author-capped']),
      );
      expect(
        harness.cubit.graphController.edges.map((e) => (e.source.id, e.destination.id)),
        contains(('author-capped', 'B-pin')),
      );
    });

    test('orderedNodeIdsForPaint uses scene graph ids with beacon topmost', () async {
      const peer = ConstellationPerson(id: 'p-overlap', displayName: 'Peer');
      const request = ConstellationRequest(
        id: 'B-overlap',
        authorId: 'p-overlap',
        title: 'Overlap',
        status: 0,
      );
      final placedAt = DateTime.utc(2026, 9, 11);
      final harness = await _harness(
        fields: [
          _field(
            peers: [peer],
            requests: [request],
            anchors: [
              ConstellationAnchor(
                target: ConstellationAnchorTarget.person('p-overlap'),
                position: const ConstellationAnchorPosition(
                  xUnits: 2.5,
                  yUnits: 2.5,
                  coordinateSpaceVersion: 1,
                ),
                revision: ConstellationAnchorRevision(BigInt.one),
                placedAt: placedAt,
              ),
              ConstellationAnchor(
                target: ConstellationAnchorTarget.beacon('B-overlap'),
                position: const ConstellationAnchorPosition(
                  xUnits: 2.5,
                  yUnits: 2.5,
                  coordinateSpaceVersion: 1,
                ),
                revision: ConstellationAnchorRevision(BigInt.two),
                placedAt: placedAt.add(const Duration(seconds: 1)),
              ),
            ],
          ),
        ],
      );
      addTearDown(harness.cubit.close);

      final paintIds = harness.cubit.orderedNodeIdsForPaint();
      final controller = harness.cubit.graphController;
      for (final id in paintIds) {
        expect(controller.nodePayloadForId(id), isNotNull, reason: id);
      }
      expect(
        paintIds.last,
        '${TenturaGraphNodeKind.fieldRequest}:B-overlap',
      );
      expect(
        paintIds,
        contains('${TenturaGraphNodeKind.fieldPerson}:p-overlap'),
      );
      expect(
        paintIds.where((id) => id.startsWith('${TenturaGraphNodeKind.fieldPerson}:')),
        isNot(contains('${TenturaGraphNodeKind.fieldPerson}:B-overlap')),
      );
    });

    test('requestById resolves overlay-only pinned requests', () async {
      const request = ConstellationRequest(
        id: 'B-pin',
        authorId: 'author-capped',
        title: 'Pinned',
        status: 0,
      );
      final harness = await _harness(
        fields: [
          _field(
            peers: const [],
            pinnedPeers: const [],
            requests: const [],
            anchors: [_beaconAnchor(beaconId: 'B-pin', revision: BigInt.one)],
            pinnedRequests: const [request],
            supportPeers: const [
              ConstellationPerson(id: 'author-capped', displayName: 'Author'),
            ],
            supportEdges: const [
              ConstellationTrustEdgeEntity(src: 'ego', dst: 'author-capped', tier: 1),
            ],
          ),
        ],
      );
      addTearDown(harness.cubit.close);

      expect(harness.cubit.requestById('B-pin'), request);
    });

    test('ANCHORS overlay-only person appears without changing automatic snapshot', () async {
      final loadedAt = _loadedAt;
      final harness = await _harness(
        fields: [
          _field(peers: const [], anchors: const []),
        ],
      );
      addTearDown(harness.cubit.close);
      expect(harness.cubit.state.loadedAt, loadedAt);
      expect(
        harness.cubit.graphController.nodes.whereType<FieldPersonNode>().map((n) => n.id),
        ['ego'],
      );

      harness.fieldRepo.fields.add(
        _field(
          revision: BigInt.two,
          peers: const [],
          pinnedPeers: const [ConstellationPerson(id: 'p-remote', displayName: 'Remote')],
          anchors: [_anchor(personId: 'p-remote', revision: BigInt.two)],
        ),
      );
      harness.port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: 'ego',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(harness.cubit.state.field!.peers, isEmpty);
      expect(harness.cubit.state.loadedAt, loadedAt);
      expect(
        harness.cubit.graphController.nodes.whereType<FieldPersonNode>().map((n) => n.id),
        contains('p-remote'),
      );

      harness.fieldRepo.fields.add(
        _field(revision: BigInt.from(3), peers: const [], anchors: const []),
      );
      harness.port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: 'ego',
          operation: RealtimeOperation.delete,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        harness.cubit.graphController.nodes.whereType<FieldPersonNode>().map((n) => n.id),
        ['ego'],
      );
    });

    test('pinned companion tracks parent delta; unpinned stays', () async {
      const peer = ConstellationPerson(id: 'p1', displayName: 'Peer');
      const pinned = ConstellationRequest(
        id: 'B-pin',
        authorId: 'p1',
        title: 'Pinned',
        status: 0,
      );
      const floating = ConstellationRequest(
        id: 'B-free',
        authorId: 'p1',
        title: 'Free',
        status: 0,
      );
      final harness = await _harness(
        fields: [
          _field(
            peers: const [peer],
            requests: const [pinned, floating],
            pinnedRequests: const [pinned],
            anchors: [
              _anchor(personId: 'p1', revision: BigInt.one, x: 1, y: 1),
              _beaconAnchor(beaconId: 'B-pin', revision: BigInt.one, x: 2, y: 2),
            ],
          ),
        ],
      );
      addTearDown(harness.cubit.close);
      final target = ConstellationAnchorTarget.person('p1');
      final companionGraphId =
          '${TenturaGraphNodeKind.fieldRequest}:B-pin';
      final freeGraphId = '${TenturaGraphNodeKind.fieldRequest}:B-free';
      harness.cubit.beginDragExisting(target: target);

      final companionBefore = harness.cubit.graphController
          .getPositionOrNullForId(companionGraphId);
      expect(companionBefore, isNotNull);
      expect(
        harness.cubit.graphController.activePresentationTokenForNode(
          companionGraphId,
        ),
        isNotNull,
      );
      expect(
        companionGraphId.startsWith('${TenturaGraphNodeKind.fieldRequest}:'),
        isTrue,
      );

      final freeBefore = harness.cubit.graphController
          .getPositionOrNullForId(freeGraphId);

      harness.cubit.updateDragPresentation(
        nodeId: 'p1',
        sceneCentre: companionBefore! + const Offset(170, 0),
      );
      // Parent start is at (1,1) units → scene; delta applied to companion.
      final companionAfter = harness.cubit.graphController
          .getPositionOrNullForId(companionGraphId);
      expect(companionAfter, isNotNull);
      expect(companionAfter!.dx, greaterThan(companionBefore.dx + 100));

      if (freeBefore != null) {
        expect(
          harness.cubit.graphController.getPositionOrNullForId(freeGraphId),
          freeBefore,
        );
      }
    });

    test('cluster drop writes parent then companion in one writeCount', () async {
      const peer = ConstellationPerson(id: 'p1', displayName: 'Peer');
      const request = ConstellationRequest(
        id: 'B1',
        authorId: 'p1',
        title: 'Need help',
        status: 0,
      );
      final harness = await _harness(
        fields: [
          _field(
            peers: const [peer],
            requests: const [request],
            pinnedRequests: const [request],
            anchors: [
              _anchor(personId: 'p1', revision: BigInt.one),
              _beaconAnchor(beaconId: 'B1', revision: BigInt.one, x: 2, y: 2),
            ],
          ),
          _field(
            revision: BigInt.from(3),
            peers: const [peer],
            requests: const [request],
            pinnedRequests: const [request],
            anchors: [
              _anchor(personId: 'p1', revision: BigInt.from(3), x: 3, y: 3),
              _beaconAnchor(beaconId: 'B1', revision: BigInt.from(3), x: 4, y: 4),
            ],
          ),
        ],
      );
      addTearDown(harness.cubit.close);
      final target = ConstellationAnchorTarget.person('p1');
      harness.cubit.beginDragExisting(target: target);
      await harness.cubit.onExistingNodeDrop(
        target: target,
        sceneCentre: const Offset(2048 + 510, 2048 + 510),
      );

      expect(harness.cubit.writeCount, 1);
      expect(harness.anchorRepo.upsertCount, 2);
      expect(
        harness.anchorRepo.upsertTargets.map((t) => t.id).toList(),
        ['p1', 'B1'],
      );
    });

    test('parent fail aborts companions after one HTTP', () async {
      const peer = ConstellationPerson(id: 'p1', displayName: 'Peer');
      const request = ConstellationRequest(
        id: 'B1',
        authorId: 'p1',
        title: 'Need help',
        status: 0,
      );
      final harness = await _harness(
        fields: [
          _field(
            peers: const [peer],
            requests: const [request],
            pinnedRequests: const [request],
            anchors: [
              _anchor(personId: 'p1', revision: BigInt.one),
              _beaconAnchor(beaconId: 'B1', revision: BigInt.one, x: 2, y: 2),
            ],
          ),
        ],
      );
      addTearDown(harness.cubit.close);
      harness.anchorRepo.failOnUpsertIndex = 1;
      harness.anchorRepo.upsertError = StateError('parent failed');
      final reconciliations = harness.cubit.layoutReconciliationCount;
      final target = ConstellationAnchorTarget.person('p1');
      harness.cubit.beginDragExisting(target: target);
      await harness.cubit.onExistingNodeDrop(
        target: target,
        sceneCentre: const Offset(2100, 2100),
      );

      expect(harness.anchorRepo.upsertCount, 1);
      expect(harness.cubit.writeCount, 1);
      expect(harness.cubit.state.placementFailureMessage, isNotNull);
      expect(
        harness.cubit.layoutReconciliationCount,
        reconciliations + 1,
      );
    });

    test('mixed fail reconciles once and names missed Requests', () async {
      const peer = ConstellationPerson(id: 'p1', displayName: 'Peer');
      const request = ConstellationRequest(
        id: 'B1',
        authorId: 'p1',
        title: 'Need help',
        status: 0,
      );
      final harness = await _harness(
        fields: [
          _field(
            peers: const [peer],
            requests: const [request],
            pinnedRequests: const [request],
            anchors: [
              _anchor(personId: 'p1', revision: BigInt.one, x: 1, y: 1),
              _beaconAnchor(beaconId: 'B1', revision: BigInt.one, x: 2, y: 2),
            ],
          ),
          // Recovery keeps companion at old pin while parent moved.
          _field(
            revision: BigInt.from(3),
            peers: const [peer],
            requests: const [request],
            pinnedRequests: const [request],
            anchors: [
              _anchor(personId: 'p1', revision: BigInt.from(3), x: 3, y: 3),
              _beaconAnchor(beaconId: 'B1', revision: BigInt.from(3), x: 2, y: 2),
            ],
          ),
        ],
      );
      addTearDown(harness.cubit.close);
      harness.anchorRepo.failTargets = {ConstellationAnchorTarget.beacon('B1')};
      final reconciliations = harness.cubit.layoutReconciliationCount;
      final target = ConstellationAnchorTarget.person('p1');
      harness.cubit.beginDragExisting(target: target);
      await harness.cubit.onExistingNodeDrop(
        target: target,
        sceneCentre: const Offset(2048 + 510, 2048 + 510),
      );

      expect(harness.cubit.writeCount, 1);
      expect(harness.anchorRepo.upsertCount, 2);
      expect(
        harness.cubit.state.placementFailureMessage,
        contains('Need help'),
      );
      expect(
        harness.cubit.layoutReconciliationCount,
        reconciliations + 1,
      );
      expect(
        harness.cubit.state.composition!.anchorOverlay.anchors
            .singleWhere((a) => a.target.id == 'B1')
            .position
            .xUnits,
        2,
      );
    });

    test('drop skips remotely unpinned companion from write', () async {
      const peer = ConstellationPerson(id: 'p1', displayName: 'Peer');
      const request = ConstellationRequest(
        id: 'B1',
        authorId: 'p1',
        title: 'Need help',
        status: 0,
      );
      final harness = await _harness(
        fields: [
          _field(
            peers: const [peer],
            requests: const [request],
            pinnedRequests: const [request],
            anchors: [
              _anchor(personId: 'p1', revision: BigInt.one),
              _beaconAnchor(beaconId: 'B1', revision: BigInt.one, x: 2, y: 2),
            ],
          ),
        ],
      );
      addTearDown(harness.cubit.close);
      final target = ConstellationAnchorTarget.person('p1');
      harness.cubit.beginDragExisting(target: target);

      // Simulate remote unpin arriving into confirmed cache mid-drag.
      harness.anchorCase.adoptConfirmedProjection(
        ConstellationAnchorProjection(
          revision: ConstellationAnchorRevision(BigInt.two),
          anchors: [_anchor(personId: 'p1', revision: BigInt.two)],
          pinnedPeers: const [peer],
          pinnedRequests: const [],
          supportPeers: const [],
          supportEdges: const [],
          serverFilteredBeaconIds: const [],
          serverFilteredBeaconCount: 0,
        ),
      );

      await harness.cubit.onExistingNodeDrop(
        target: target,
        sceneCentre: const Offset(2100, 2100),
      );

      expect(harness.anchorRepo.upsertCount, 1);
      expect(harness.anchorRepo.upsertTargets.single.id, 'p1');
    });

    test('paint lift includes companions while write pending', () async {
      const peer = ConstellationPerson(id: 'p1', displayName: 'Peer');
      const request = ConstellationRequest(
        id: 'B1',
        authorId: 'p1',
        title: 'Need help',
        status: 0,
      );
      final harness = await _harness(
        fields: [
          _field(
            peers: const [peer],
            requests: const [request],
            pinnedRequests: const [request],
            anchors: [
              _anchor(personId: 'p1', revision: BigInt.one),
              _beaconAnchor(beaconId: 'B1', revision: BigInt.one, x: 2, y: 2),
            ],
          ),
        ],
      );
      addTearDown(harness.cubit.close);
      harness.anchorRepo.upsertGate = Completer<void>();
      final target = ConstellationAnchorTarget.person('p1');
      harness.cubit.beginDragExisting(target: target);
      final drop = harness.cubit.onExistingNodeDrop(
        target: target,
        sceneCentre: const Offset(2100, 2100),
      );
      await Future<void>.delayed(Duration.zero);

      final paintIds = harness.cubit.orderedNodeIdsForPaint();
      expect(
        paintIds,
        containsAll([
          '${TenturaGraphNodeKind.fieldPerson}:p1',
          '${TenturaGraphNodeKind.fieldRequest}:B1',
        ]),
      );
      expect(paintIds.last, '${TenturaGraphNodeKind.fieldPerson}:p1');

      harness.anchorRepo.upsertGate.complete();
      await drop;
    });
  });
}
