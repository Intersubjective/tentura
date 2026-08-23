import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../support/test_realtime_sync.dart';
import 'fake_coordination_item_case.dart';

const _kBeaconId = 'b-threads-test';
const _kMyUserId = 'me-threads';
const _kOtherUserId = 'other-user';
final _kSeenAt = DateTime.utc(2026, 8, 14, 10);
final _kReadThrough = DateTime.utc(2026, 8, 14, 12);

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(String userId) : _userId = userId;
  final String _userId;

  @override
  ProfileState get state => ProfileState(
    profile: Profile(id: _userId, displayName: 'T'),
  );

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

class _FakeBeaconFactCardRepository extends Fake
    implements BeaconFactCardRepository {
  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async => [];
}

class _FakeBeaconRoomHintsRepository extends Fake
    implements BeaconRoomHintsRepository {}

class _FakePollingRepository extends Fake implements PollingRepository {}

class _FakeBeaconThreadsRepository extends Fake
    implements BeaconThreadsRepository {
  List<RequestThread> threads = const [];
  int listThreadsCallCount = 0;
  Object? listThreadsError;
  Completer<void>? listThreadsGate;

  final _invalidations = StreamController<BeaconRoomInvalidation>.broadcast();

  @override
  Stream<String> get beaconRoomRefresh => const Stream.empty();

  @override
  Stream<BeaconRoomInvalidation> get beaconRoomInvalidations =>
      _invalidations.stream;

  void emitInvalidation(BeaconRoomEntityType entityType) {
    _invalidations.add(
      BeaconRoomInvalidation(
        beaconId: _kBeaconId,
        entityType: entityType,
      ),
    );
  }

  @override
  Future<List<RequestThread>> fetchThreads(String beaconId) async {
    listThreadsCallCount++;
    final gate = listThreadsGate;
    if (gate != null) {
      listThreadsGate = null;
      await gate.future;
    }
    final error = listThreadsError;
    if (error != null) {
      if (error is Exception) throw error;
      if (error is Error) throw error;
      throw StateError(error.toString());
    }
    return threads;
  }

  @override
  Future<void> dispose() => _invalidations.close();

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) async => const [];

  @override
  Future<List<BeaconParticipant>> fetchParticipants(String beaconId) async =>
      const [];

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async =>
      BeaconRoomState(beaconId: beaconId, updatedAt: DateTime.utc(2026));

  @override
  Future<String> createMessage({
    required String beaconId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    RoomPendingUpload? firstAttachment,
    List<String> explicitMentionUserIds = const [],
    List<int> explicitMentionOffsets = const [],
    List<int> explicitMentionLengths = const [],
  }) async => 'msg-created';
}

class _TrackingCoordinationItemCase extends FakeCoordinationItemCaseForRoom {
  int fetchCurrentRootPlanCallCount = 0;
  int acceptAskCallCount = 0;

  @override
  Future<CoordinationItem?> fetchCurrentRootPlan(String beaconId) async {
    fetchCurrentRootPlanCallCount++;
    return null;
  }

  @override
  Future<CoordinationItem> acceptAsk({required String itemId}) async {
    acceptAskCallCount++;
    return _item(id: itemId);
  }
}

CoordinationItem _item({
  required String id,
  CoordinationItemKind kind = CoordinationItemKind.ask,
  CoordinationItemStatus status = CoordinationItemStatus.open,
  bool published = true,
  String creatorId = _kMyUserId,
  String? targetPersonId = _kOtherUserId,
  int unreadCount = 0,
}) => CoordinationItem(
  id: id,
  beaconId: _kBeaconId,
  kind: kind,
  status: status,
  creatorId: creatorId,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 2),
  published: published,
  targetPersonId: targetPersonId,
  unreadCount: unreadCount,
);

RequestThreadKind _threadKindFor(CoordinationItemKind kind) => switch (kind) {
  CoordinationItemKind.ask => RequestThreadKind.ask,
  CoordinationItemKind.promise => RequestThreadKind.promise,
  CoordinationItemKind.blocker => RequestThreadKind.blocker,
  CoordinationItemKind.plan => RequestThreadKind.ask,
};

RequestThread _generalThread({
  int unreadCount = 0,
  DateTime? lastSeenAt,
}) => RequestThread(
  threadId: RequestThread.generalId,
  kind: RequestThreadKind.general,
  unreadCount: unreadCount,
  lastSeenAt: lastSeenAt ?? _kSeenAt,
);

RequestThread _semanticThread({
  required CoordinationItem item,
  int unreadCount = 0,
  DateTime? lastSeenAt,
}) => RequestThread(
  threadId: item.id,
  kind: _threadKindFor(item.kind),
  unreadCount: unreadCount,
  lastSeenAt: lastSeenAt ?? _kSeenAt,
  item: item,
);

BeaconThreadsCase _makeCase(
  _FakeBeaconThreadsRepository repo, {
  CoordinationItemCase? coordinationCase,
  RoomReadWatermarkStore? watermark,
}) => BeaconThreadsCase(
  repo,
  _FakeBeaconFactCardRepository(),
  _FakePollingRepository(),
  _FakeBeaconRoomHintsRepository(),
  watermark ?? RoomReadWatermarkStore.testing(),
  coordinationCase ?? const FakeCoordinationItemCaseForRoom(),
  buildTestRealtimeSync().case_,
  env: const Env(),
  logger: Logger('threads_cubit_test'),
);

void _registerProfileCubit(String userId) {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<ProfileCubit>()) {
    // ignore: discarded_futures
    getIt.unregister<ProfileCubit>();
  }
  getIt.registerSingleton<ProfileCubit>(_MockProfileCubit(userId));
  addTearDown(() {
    if (getIt.isRegistered<ProfileCubit>()) {
      // ignore: discarded_futures
      getIt.unregister<ProfileCubit>();
    }
  });
}

ThreadsCubit _cubit({
  required _FakeBeaconThreadsRepository repo,
  CoordinationItemCase? coordinationCase,
  RoomReadWatermarkStore? watermark,
}) => ThreadsCubit(
  beaconId: _kBeaconId,
  coordinationItemCase:
      coordinationCase ?? const FakeCoordinationItemCaseForRoom(),
  beaconThreadsCase: _makeCase(
    repo,
    coordinationCase: coordinationCase,
    watermark: watermark,
  ),
);

Future<void> _awaitListThreadsCount(
  _FakeBeaconThreadsRepository repo,
  int expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (repo.listThreadsCallCount >= expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail(
    'Expected at least $expected listThreads calls, got ${repo.listThreadsCallCount}.',
  );
}

void main() {
  setUp(() => _registerProfileCubit(_kMyUserId));

  group('ThreadsCubit fetch', () {
    test('loads threads and resolves unread counts', () async {
      final repo = _FakeBeaconThreadsRepository()
        ..threads = [
          _generalThread(unreadCount: 2),
          _semanticThread(
            item: _item(id: 'ask-1', unreadCount: 3),
            unreadCount: 3,
          ),
        ];
      final cubit = _cubit(repo: repo);
      addTearDown(cubit.close);

      await cubit.fetch();
      final state = cubit.state;

      expect(state.threads, hasLength(2));
      expect(state.resolvedUnreadFor(state.general!), 2);
      expect(state.threadsTabUnreadCount, 5);
      expect(repo.listThreadsCallCount, 1);
    });

    test('never calls fetchCurrentRootPlan', () async {
      final tracking = _TrackingCoordinationItemCase();
      final repo = _FakeBeaconThreadsRepository()..threads = [_generalThread()];
      final cubit = _cubit(repo: repo, coordinationCase: tracking);
      addTearDown(cubit.close);

      await cubit.fetch();
      await cubit.acceptAsk('ask-1');

      expect(tracking.fetchCurrentRootPlanCallCount, 0);
      expect(tracking.acceptAskCallCount, 1);
    });
  });

  group('ThreadsCubit grouping getters', () {
    test(
      'preserves zero-message draft rows and groups active/closed',
      () async {
        final activeItem = _item(id: 'active-ask');
        final closedItem = _item(
          id: 'closed-ask',
          status: CoordinationItemStatus.resolved,
        );
        final draftItem = _item(
          id: 'draft-ask',
          published: false,
          creatorId: _kMyUserId,
        );
        final repo = _FakeBeaconThreadsRepository()
          ..threads = [
            _generalThread(),
            _semanticThread(item: activeItem),
            _semanticThread(item: closedItem),
            _semanticThread(item: draftItem, unreadCount: 0),
          ];
        final cubit = _cubit(repo: repo);
        addTearDown(cubit.close);

        await cubit.fetch();

        expect(cubit.state.general, isNotNull);
        expect(cubit.state.active, hasLength(1));
        expect(cubit.state.active.single.item!.id, 'active-ask');
        expect(cubit.state.closed, hasLength(1));
        expect(cubit.state.closed.single.item!.id, 'closed-ask');
        expect(cubit.state.drafts, hasLength(1));
        expect(cubit.state.drafts.single.item!.id, 'draft-ask');
        expect(cubit.state.drafts.single.messageCount, 0);
        expect(cubit.state.firstAccessible, cubit.state.general);
      },
    );

    test(
      'firstAccessible falls back to first row when General absent',
      () async {
        final item = _item(id: 'only-item', creatorId: _kMyUserId);
        final repo = _FakeBeaconThreadsRepository()
          ..threads = [_semanticThread(item: item)];
        final cubit = _cubit(repo: repo);
        addTearDown(cubit.close);

        await cubit.fetch();

        expect(cubit.state.general, isNull);
        expect(cubit.state.firstAccessible?.threadId, 'only-item');
      },
    );

    test('activeForMeOnly filters active semantic rows', () async {
      final mine = _item(id: 'mine', creatorId: _kMyUserId);
      final other = _item(
        id: 'other',
        creatorId: _kOtherUserId,
        targetPersonId: 'someone-else',
      );
      final repo = _FakeBeaconThreadsRepository()
        ..threads = [
          _generalThread(),
          _semanticThread(item: mine),
          _semanticThread(item: other),
        ];
      final cubit = _cubit(repo: repo);
      addTearDown(cubit.close);

      await cubit.fetch();
      expect(cubit.state.active, hasLength(2));

      cubit.setActiveForMeOnly(true);
      expect(cubit.state.active, hasLength(1));
      expect(cubit.state.active.single.item!.id, 'mine');
    });
  });

  group('ThreadsCubit badge math', () {
    test('tab total is General plus active only; closed excluded', () async {
      final activeItem = _item(id: 'active', unreadCount: 4);
      final closedItem = _item(
        id: 'closed',
        status: CoordinationItemStatus.resolved,
        unreadCount: 7,
      );
      final repo = _FakeBeaconThreadsRepository()
        ..threads = [
          _generalThread(unreadCount: 1),
          _semanticThread(item: activeItem, unreadCount: 4),
          _semanticThread(item: closedItem, unreadCount: 7),
        ];
      final cubit = _cubit(repo: repo);
      addTearDown(cubit.close);

      await cubit.fetch();

      expect(cubit.state.threadsTabUnreadCount, 5);
      expect(cubit.state.resolvedUnreadFor(cubit.state.closed.single), 7);
    });
  });

  group('ThreadsCubit latest-wins fetch', () {
    test(
      'discards stale success when a newer generation completes first',
      () async {
        final repo = _FakeBeaconThreadsRepository();
        final cubit = _cubit(repo: repo);
        addTearDown(cubit.close);

        final slowGate = Completer<void>();
        repo.listThreadsGate = slowGate;
        repo.threads = [_generalThread(unreadCount: 99)];

        final slow = cubit.fetch();
        await Future<void>.delayed(const Duration(milliseconds: 5));

        repo.listThreadsGate = null;
        repo.threads = [_generalThread(unreadCount: 1)];
        await cubit.fetch();
        expect(cubit.state.resolvedUnreadFor(cubit.state.general!), 1);

        slowGate.complete();
        await slow;
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(cubit.state.resolvedUnreadFor(cubit.state.general!), 1);
        expect(repo.listThreadsCallCount, 2);
      },
    );

    test(
      'discards stale error when a newer generation already succeeded',
      () async {
        final repo = _FakeBeaconThreadsRepository();
        final cubit = _cubit(repo: repo);
        addTearDown(cubit.close);

        final slowGate = Completer<void>();
        repo.listThreadsGate = slowGate;
        repo.listThreadsError = StateError('stale failure');
        repo.threads = [_generalThread()];

        final slow = cubit.fetch();
        await Future<void>.delayed(const Duration(milliseconds: 5));

        repo.listThreadsError = null;
        repo.listThreadsGate = null;
        repo.threads = [_generalThread(unreadCount: 2)];
        await cubit.fetch();
        expect(cubit.state.loadError, isNull);
        expect(cubit.state.resolvedUnreadFor(cubit.state.general!), 2);

        slowGate.complete();
        await slow;
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(cubit.state.loadError, isNull);
        expect(cubit.state.resolvedUnreadFor(cubit.state.general!), 2);
      },
    );
  });

  group('ThreadsCubit invalidation', () {
    test('coalesces bursty non-seen invalidations into one fetch', () async {
      final repo = _FakeBeaconThreadsRepository()..threads = [_generalThread()];
      final cubit = _cubit(repo: repo);
      addTearDown(cubit.close);

      await cubit.fetch();
      expect(repo.listThreadsCallCount, 1);

      repo.emitInvalidation(BeaconRoomEntityType.roomMessage);
      repo.emitInvalidation(BeaconRoomEntityType.coordinationItem);
      repo.emitInvalidation(BeaconRoomEntityType.participant);

      await _awaitListThreadsCount(repo, 2);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(repo.listThreadsCallCount, 2);
    });

    test('roomSeen bypasses debounce and fetches immediately', () async {
      final repo = _FakeBeaconThreadsRepository()
        ..threads = [_generalThread(unreadCount: 1)];
      final cubit = _cubit(repo: repo);
      addTearDown(cubit.close);

      await cubit.fetch();
      expect(repo.listThreadsCallCount, 1);

      repo.emitInvalidation(BeaconRoomEntityType.roomMessage);
      repo.emitInvalidation(BeaconRoomEntityType.roomSeen);

      await _awaitListThreadsCount(repo, 2);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        repo.listThreadsCallCount,
        2,
        reason: 'cancelled debounce must not schedule a second fetch',
      );
    });
  });

  group('ThreadsCubit watermark changes', () {
    test(
      'optimistically suppresses unread without a network refetch',
      () async {
        final watermark = RoomReadWatermarkStore.testing();
        final repo = _FakeBeaconThreadsRepository()
          ..threads = [
            _generalThread(unreadCount: 3, lastSeenAt: _kSeenAt),
            _semanticThread(
              item: _item(id: 'ask-1'),
              unreadCount: 2,
              lastSeenAt: _kSeenAt,
            ),
          ];
        final case_ = _makeCase(repo, watermark: watermark);
        final cubit = ThreadsCubit(
          beaconId: _kBeaconId,
          coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
          beaconThreadsCase: case_,
        );
        addTearDown(cubit.close);

        await cubit.fetch();
        expect(cubit.state.threadsTabUnreadCount, 5);

        case_.observeReadThrough(
          _kBeaconId,
          _kReadThrough,
          threadId: 'ask-1',
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(repo.listThreadsCallCount, 1);
        expect(cubit.state.resolvedUnreadFor(cubit.state.active.single), 0);
        expect(cubit.state.threadsTabUnreadCount, 3);
      },
    );
  });

  group('ThreadsCubit lifecycle actions', () {
    test('successful mutation triggers a silent refetch', () async {
      final tracking = _TrackingCoordinationItemCase();
      final repo = _FakeBeaconThreadsRepository()..threads = [_generalThread()];
      final cubit = _cubit(repo: repo, coordinationCase: tracking);
      addTearDown(cubit.close);

      await cubit.fetch();
      expect(repo.listThreadsCallCount, 1);

      await cubit.acceptAsk('ask-1');

      expect(tracking.acceptAskCallCount, 1);
      expect(repo.listThreadsCallCount, 2);
    });
  });
}
