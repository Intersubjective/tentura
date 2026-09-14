import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_fetch_types.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import '../../support/test_realtime_sync.dart';
import 'my_work_test_support.dart';

Beacon _obligationBeacon(String id) => Beacon.empty.copyWith(
  id: id,
  updatedAt: DateTime(2025, 6, 1),
  status: BeaconStatus.open,
);

MyWorkInitResult _initWithObligation(Beacon beacon) => (
  authoredNonArchived: const <Beacon>[],
  helpOfferedNonArchived: const [],
  obligationBeacons: [(beacon: beacon, viewerArchived: false)],
  archivedCountHint: 0,
);

MyWorkInitResult _initWithoutObligation() => (
  authoredNonArchived: const <Beacon>[],
  helpOfferedNonArchived: const [],
  obligationBeacons: const [],
  archivedCountHint: 0,
);

class _TrackingAttentionRepository extends StubAttentionRepository {
  int settleCallCount = 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async {
    settleCallCount++;
    return 0;
  }
}

class _ControllableBlockCase implements BlockCase {
  final _controller =
      StreamController<RepositoryEvent<BlockIntent>>.broadcast();

  @override
  Stream<RepositoryEvent<BlockIntent>> get changes => _controller.stream;

  void emitBlock({String objectId = 'author-blocked'}) {
    _controller.add(
      RepositoryEventCreate(BlockIntent(blocked: Profile(id: objectId))),
    );
  }

  void emitUnblock({String objectId = 'author-blocked'}) {
    _controller.add(
      RepositoryEventDelete(BlockIntent(blocked: Profile(id: objectId))),
    );
  }

  Future<void> dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('My Work obligation refresh triggers', () {
    late TestRealtimeSyncPort sync;
    late _TrackingAttentionRepository attentionRepo;
    late FakeMyWorkRepository repo;
    late _ControllableBlockCase blockCase;

    late RealtimeSyncCase realtimeCase;

    setUp(() {
      final harness = buildTestRealtimeSync();
      sync = harness.port;
      realtimeCase = harness.case_;
      attentionRepo = _TrackingAttentionRepository()
        ..obligationBeaconIds = {'obl-1'};
      repo = FakeMyWorkRepository()
        ..initResult = _initWithObligation(_obligationBeacon('obl-1'));
      blockCase = _ControllableBlockCase();
    });

    tearDown(() async {
      await sync.dispose();
      await blockCase.dispose();
    });

    MyWorkCubit buildCubit() => MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(
        repo: repo,
        attentionRepository: attentionRepo,
        realtimeSyncCase: realtimeCase,
      ),
      realtimeSyncCase: realtimeCase,
      blockCase: blockCase,
    );

    test('notification settlement removes obligation card without reconnect', () async {
      final cubit = buildCubit();
      await cubit.stream.firstWhere((s) => s.isSuccess);
      expect(cubit.state.nonArchivedCards.single.beaconId, 'obl-1');

      attentionRepo.obligationBeaconIds = {};
      repo.initResult = _initWithoutObligation();
      sync.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.notification,
          aggregateId: 'receipt-settled',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await cubit.stream.firstWhere((s) => s.nonArchivedCards.isEmpty);
      expect(attentionRepo.settleCallCount, 0);

      await cubit.close();
    });

    test('block removes obligation card without notification', () async {
      final cubit = buildCubit();
      await cubit.stream.firstWhere((s) => s.isSuccess);
      expect(cubit.state.nonArchivedCards, isNotEmpty);

      attentionRepo.obligationBeaconIds = {};
      repo.initResult = _initWithoutObligation();
      blockCase.emitBlock();
      await cubit.stream.firstWhere((s) => s.nonArchivedCards.isEmpty);
      expect(attentionRepo.settleCallCount, 0);

      await cubit.close();
    });

    test('unblock restores obligation card without notification', () async {
      attentionRepo.obligationBeaconIds = {};
      repo.initResult = _initWithoutObligation();
      final cubit = buildCubit();
      await cubit.stream.firstWhere((s) => s.isSuccess);
      expect(cubit.state.nonArchivedCards, isEmpty);

      final beacon = _obligationBeacon('obl-1');
      attentionRepo.obligationBeaconIds = {'obl-1'};
      repo.initResult = _initWithObligation(beacon);
      blockCase.emitUnblock();
      await cubit.stream.firstWhere((s) => s.nonArchivedCards.isNotEmpty);
      expect(cubit.state.nonArchivedCards.single.role, MyWorkCardRole.obligation);
      expect(attentionRepo.settleCallCount, 0);

      await cubit.close();
    });

    test('block and unblock do not call attention settle', () async {
      final cubit = buildCubit();
      await cubit.stream.firstWhere((s) => s.isSuccess);

      attentionRepo.obligationBeaconIds = {};
      repo.initResult = _initWithoutObligation();
      blockCase.emitBlock();
      await cubit.stream.firstWhere((s) => s.nonArchivedCards.isEmpty);

      attentionRepo.obligationBeaconIds = {'obl-1'};
      repo.initResult = _initWithObligation(_obligationBeacon('obl-1'));
      blockCase.emitUnblock();
      await cubit.stream.firstWhere((s) => s.nonArchivedCards.isNotEmpty);

      expect(attentionRepo.settleCallCount, 0);

      await cubit.close();
    });
  });
}
