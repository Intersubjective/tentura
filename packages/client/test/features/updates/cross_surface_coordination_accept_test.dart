import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import '../../support/attention_repository_fake_base.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import '../beacon_view/beacon_view_case_test_support.dart';
import '../beacon_view/beacon_view_initial_load_test.dart';
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
        FeedSessionRegistry(),
        Logger('cross-surface-accept'),
      );
      attention.attachFeedSession(AttentionFeedDestinationId.activity);
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
        obligationBeacons: const [],
          archivedCountHint: 0,
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
      final beaconViewCubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: beaconViewCase,
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
                surface: AttentionSurface.activity,
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

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(myWorkRepo.fetchInitCallCount, greaterThan(deskFetchesBefore));
      expect(beaconViewCubit.state.youResponsibility, isNull);
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

final class _Repository extends AttentionRepositoryFake {
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
    AttentionSurface? surface,
  }) async {
    fetchCalls++;
    return feed;
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      unread.intersection(beaconIds);

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}
