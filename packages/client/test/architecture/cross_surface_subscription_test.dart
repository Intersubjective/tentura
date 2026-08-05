import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../features/beacon_view/beacon_view_case_test_support.dart';
import '../features/block/support/controllable_block_case.dart';
import '../features/my_work/my_work_test_support.dart';
import '../support/test_realtime_sync.dart';

/// U7 evidence guard: the four #102 surfaces expose the shared realtime /
/// attention boundaries documented in the plan journal.
void main() {
  group('Updates surface', () {
    test('AttentionCase listens to notification hints and catch-ups', () async {
      final accounts = _RecordingAccounts();
      final repository = _RecordingAttentionRepository();
      final sync = buildTestRealtimeSync();
      addTearDown(sync.port.dispose);
      final attention = AttentionCase(
        repository,
        accounts,
        sync.case_,
        noopBlockCase(),
        Logger('cross-surface-updates'),
      );
      addTearDown(attention.dispose);

      accounts.emit('author');
      await attention.refresh();
      expect(repository.fetchCalls, 1);

      sync.port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.notification,
          aggregateId: 'receipt-1',
          operation: RealtimeOperation.insert,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await _pump();
      expect(repository.fetchCalls, greaterThanOrEqualTo(2));

      sync.port.emitCatchUp();
      await _pump();
      expect(repository.fetchCalls, greaterThanOrEqualTo(3));
    });

    test('UpdatesFeedCubit projects AttentionCase.feedPages only', () async {
      final accounts = _RecordingAccounts();
      final repository = _RecordingAttentionRepository();
      final sync = buildTestRealtimeSync();
      addTearDown(sync.port.dispose);
      final attention = AttentionCase(
        repository,
        accounts,
        sync.case_,
        noopBlockCase(),
        Logger('cross-surface-feed'),
      );
      addTearDown(attention.dispose);
      final cubit = UpdatesFeedCubit(
        attention: attention,
        logger: Logger('cross-surface-feed'),
      );
      addTearDown(cubit.close);

      accounts.emit('author');
      await attention.refresh();
      await _pump();

      expect(cubit.state.items, isEmpty);
      expect(cubit.state.status, isA<StateIsSuccess>());
    });
  });

  group('My Work surface', () {
    test('deskRelevantInvalidations includes coordination_item', () async {
      final roomRepo = FakeBeaconRoomRepository();
      addTearDown(roomRepo.dispose);
      final case_ = buildTestMyWorkCase(roomRepo: roomRepo);
      final ids = <BeaconRoomInvalidation>[];
      final sub = case_.deskRelevantInvalidations.listen(ids.add);
      addTearDown(sub.cancel);

      roomRepo.emitRoomInvalidation(
        const BeaconRoomInvalidation(
          beaconId: 'B1',
          entityType: BeaconRoomEntityType.coordinationItem,
        ),
      );
      await _pump();

      expect(ids.single.entityType, BeaconRoomEntityType.coordinationItem);
    });

    test('catchUps is wired through RealtimeSyncCase', () async {
      final sync = buildTestRealtimeSync();
      addTearDown(sync.port.dispose);
      final case_ = buildTestMyWorkCase(realtimeSyncCase: sync.case_);
      var catchUps = 0;
      final sub = case_.catchUps.listen((_) => catchUps++);
      addTearDown(sub.cancel);

      sync.port.emitCatchUp();
      await _pump();

      expect(catchUps, 1);
    });
  });

  group('Request detail (beacon_view) surface', () {
    test('beaconRoomInvalidations and catchUps are exposed', () async {
      final room = FakeBeaconViewRoomRepository();
      addTearDown(room.dispose);
      final sync = buildTestRealtimeSync();
      addTearDown(sync.port.dispose);
      final case_ = buildTestBeaconViewCase(
        roomRepo: room,
        realtimeSyncCase: sync.case_,
      );

      final invalidations = <BeaconRoomInvalidation>[];
      final invSub = case_.beaconRoomInvalidations.listen(invalidations.add);
      addTearDown(invSub.cancel);
      var catchUps = 0;
      final catchSub = case_.catchUps.listen((_) => catchUps++);
      addTearDown(catchSub.cancel);

      const inv = BeaconRoomInvalidation(
        beaconId: 'B-detail',
        entityType: BeaconRoomEntityType.coordinationItem,
      );
      room.emitRoomInvalidation(inv);
      sync.port.emitCatchUp();
      await _pump();

      expect(invalidations, [inv]);
      expect(catchUps, 1);
    });

    test('peopleChanges listens to relationship and profile only', () async {
      final sync = buildTestRealtimeSync();
      addTearDown(sync.port.dispose);
      final case_ = buildTestBeaconViewCase(realtimeSyncCase: sync.case_);
      final kinds = <RealtimeEntityKind>[];
      final sub = case_.peopleChanges.listen((c) => kinds.add(c.kind));
      addTearDown(sub.cancel);

      for (final kind in RealtimeEntityKind.values) {
        sync.port.emitChange(
          RealtimeEntityChange(
            kind: kind,
            aggregateId: 'U1',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
      }
      await _pump();

      expect(
        kinds.toSet(),
        {RealtimeEntityKind.relationship, RealtimeEntityKind.profile},
      );
    });
  });

}

Future<void> _pump({int milliseconds = 8}) async {
  for (var i = 0; i < milliseconds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _RecordingAccounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);
}

final class _RecordingAttentionRepository implements AttentionRepositoryPort {
  int fetchCalls = 0;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
  }) async {
    fetchCalls++;
    return AttentionFeed(
      summary: const AttentionSummary(),
      page: const AttentionFeedPage(),
    );
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      const {};

  @override
  Future<int> markAllSeen() async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}
