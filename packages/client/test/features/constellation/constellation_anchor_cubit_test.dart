import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
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

ConstellationField _field({
  BigInt? revision,
  List<ConstellationAnchor> anchors = const [],
  List<ConstellationPerson> peers = const [],
}) =>
    ConstellationField(
      loadedAt: _loadedAt,
      context: '',
      peers: peers,
      anchorProjection: ConstellationAnchorProjection(
        revision: ConstellationAnchorRevision(revision ?? BigInt.one),
        anchors: anchors,
        pinnedPeers: peers,
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
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
  int upsertCount = 0;
  Object? upsertError;

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    upsertCount++;
    await upsertGate.future;
    if (upsertError != null) {
      throw upsertError!;
    }
    return ConstellationAnchorUpsertResult(
      anchor: ConstellationAnchor(
        target: target,
        position: position,
        revision: ConstellationAnchorRevision(BigInt.two),
        placedAt: DateTime.utc(2026, 9, 11, 1),
      ),
      revision: ConstellationAnchorRevision(BigInt.two),
    );
  }

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) => throw UnimplementedError();
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

    test('provisional cancel restores idle without writes', () async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      final target = ConstellationAnchorTarget.person('p1');

      harness.cubit.beginDragNew(target: target);
      await harness.cubit.onNewNodeDrop(
        target: target,
        sceneCentre: const Offset(2100, 2100),
      );
      expect(
        harness.cubit.state.placementPhase,
        ConstellationPlacementPhase.provisionalNew,
      );

      harness.cubit.cancelPlacement();
      expect(harness.cubit.state.placementPhase, ConstellationPlacementPhase.idle);
      expect(harness.anchorRepo.upsertCount, 0);
    });

    test('remote refresh during drag defers active target presentation', () async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      final target = ConstellationAnchorTarget.person('p1');
      harness.cubit.beginDragExisting(target: target);

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

      expect(harness.cubit.state.deferredRefreshTarget, target);
      expect(
        harness.cubit.state.confirmedProjection!.revision.value,
        BigInt.two,
      );
    });

    test('failed write rolls back with one reconciliation bump', () async {
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
      expect(
        harness.cubit.layoutReconciliationCount,
        greaterThan(reconciliations),
      );
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

    test('double provisional confirmation only writes once when guarded', () async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      final target = ConstellationAnchorTarget.person('p2');
      await harness.cubit.onNewNodeDrop(
        target: target,
        sceneCentre: const Offset(2100, 2100),
      );
      final first = harness.cubit.confirmProvisionalPin(
        target: target,
        sceneCentre: const Offset(2100, 2100),
      );
      await harness.cubit.confirmProvisionalPin(
        target: target,
        sceneCentre: const Offset(2100, 2100),
      );
      await first;
      expect(harness.anchorRepo.upsertCount, 1);
    });
  });
}
