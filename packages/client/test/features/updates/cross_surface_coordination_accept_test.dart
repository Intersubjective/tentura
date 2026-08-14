import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import '../beacon_threads/fake_coordination_item_case.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import '../beacon_view/beacon_view_initial_load_test.dart';
import '../beacon_view/beacon_view_you_responsibility_test.dart';
import '../block/support/controllable_block_case.dart';
import '../my_work/my_work_test_support.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

/// U7 guard: a single coordination-item acceptance fans out through the wire
/// kinds that declare impacts on My Work, request detail, and Updates.
void main() {
  const beaconId = 'B-accept-102';
  const authorId = 'author';
  const myProfile = Profile(id: authorId, displayName: 'Author');

  Beacon readableBeacon() => Beacon(
    id: beaconId,
    title: 'Accept proof',
    createdAt: DateTime.utc(2026, 8, 5),
    updatedAt: DateTime.utc(2026, 8, 5),
    status: BeaconStatus.open,
    canReadContent: true,
    author: myProfile,
  );

  test(
    'commitmentAccepted notification and coordination_item invalidation refresh all surfaces',
    () async {
      final accounts = _Accounts();
      final repository = _Repository();
      final sync = buildTestRealtimeSync();
      final attention = AttentionCase(
        repository,
        accounts,
        sync.case_,
        noopBlockCase(),
        Logger('cross-surface-accept'),
      );
      addTearDown(() async {
        await attention.dispose();
        await sync.port.dispose();
        await accounts.close();
      });

      final roomRepo = FakeBeaconThreadsRepository();
      addTearDown(roomRepo.dispose);
      final myWorkRepo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: [readableBeacon()],
          helpOfferedNonArchived: const [],
          archivedCountHint: 0,
          lastItemDiscussionMessageAtByBeaconId: const {},
        );
      final myWorkCase = buildTestMyWorkCase(
        repo: myWorkRepo,
        roomRepo: roomRepo,
        realtimeSyncCase: sync.case_,
      );
      final myWorkCubit = MyWorkCubit(userId: authorId, myWorkCase: myWorkCase);
      addTearDown(myWorkCubit.close);

      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon();
      final beaconViewRoom = FakeBeaconViewRoomRepository();
      addTearDown(beaconViewRoom.dispose);
      final beaconViewCase = buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        roomRepo: beaconViewRoom,
        realtimeSyncCase: sync.case_,
      );
      final coordination = TrackingCoordinationItemCase(
        responsibility: CoordinationResponsibility(beaconId: beaconId),
      );
      final beaconViewCubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: beaconViewCase,
        coordinationItemCase: coordination,
        effects: FakeUiEffectPort(),
      );
      addTearDown(beaconViewCubit.close);

      accounts.emit(authorId);
      await attention.refresh();
      await myWorkCubit.stream.firstWhere((s) => s.isSuccess);
      await pumpUntil(
        beaconViewCubit.stream,
        () => beaconViewCubit.state.beaconContextLoaded,
      );

      final fetchesBefore = repository.fetchCalls;
      final deskFetchesBefore = myWorkRepo.fetchInitCallCount;
      final responsibilityBefore = coordination.fetchResponsibilityCalls;

      sync.port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.notification,
          aggregateId: 'receipt-accept',
          operation: RealtimeOperation.insert,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await _settle();

      expect(repository.fetchCalls, greaterThan(fetchesBefore));

      repository
        ..feed = AttentionFeed(
          summary: const AttentionSummary(unreadTotal: 1),
          page: AttentionFeedPage(
            items: [
              AttentionReceipt(
                id: 'receipt-accept',
                category: 'requestProgress',
                kind: 'commitmentAccepted',
                priority: 'normal',
                title: 'Helper accepted your ask',
                body: 'Accept proof',
                actionUrl: '/#/',
                createdAt: DateTime.utc(2026, 8, 5, 12),
                collapsedCount: 1,
                presentationPayloadJson: '{}',
                beaconId: beaconId,
              ),
            ],
          ),
        )
        ..unread = {beaconId};
      await attention.refresh();
      await _settle();
      expect(attention.snapshot.summary.unreadTotal, 1);

      roomRepo.emitRoomInvalidation(
        const BeaconRoomInvalidation(
          beaconId: beaconId,
          entityType: BeaconRoomEntityType.coordinationItem,
        ),
      );
      beaconViewRoom.emitRoomInvalidation(
        const BeaconRoomInvalidation(
          beaconId: beaconId,
          entityType: BeaconRoomEntityType.coordinationItem,
        ),
      );

      coordination.responsibility = CoordinationResponsibility(
        beaconId: beaconId,
        askOpen: 1,
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));
      await pumpUntil(
        beaconViewCubit.stream,
        () => coordination.fetchResponsibilityCalls > responsibilityBefore,
      );

      expect(myWorkRepo.fetchInitCallCount, greaterThan(deskFetchesBefore));
      expect(
        coordination.fetchResponsibilityCalls,
        greaterThan(responsibilityBefore),
      );
      expect(beaconViewCubit.state.youResponsibility?.askOpen, 1);
    },
  );
}

Future<void> _settle([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _Repository implements AttentionRepositoryPort {
  AttentionFeed feed = const AttentionFeed(
    summary: AttentionSummary(),
    page: AttentionFeedPage(),
  );
  Set<String> unread = const {};
  int fetchCalls = 0;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
  }) async {
    fetchCalls++;
    return feed;
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      unread.intersection(beaconIds);

  @override
  Future<int> markAllSeen() async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}
