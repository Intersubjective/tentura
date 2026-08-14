import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/coordination_item/data/repository/coordination_item_repository.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../block/support/controllable_block_case.dart';

void main() {
  late FakeInboxRepository repo;
  late BeaconThreadsCase beaconRoom;
  late _FakeBeaconThreadsRepository roomRepo;
  late _FakeForwardRepository forwardRepo;
  late _TestRealtimeSyncPort realtimePort;
  late RealtimeSyncCase realtimeSyncCase;
  late InboxCase case_;

  setUp(() {
    repo = FakeInboxRepository();
    roomRepo = _FakeBeaconThreadsRepository();
    forwardRepo = _FakeForwardRepository();
    realtimePort = _TestRealtimeSyncPort();
    realtimeSyncCase = RealtimeSyncCase(realtimePort);
    beaconRoom = _buildTestBeaconThreadsCase(roomRepo: roomRepo);
    case_ = buildTestInboxCase(
      repo,
      beaconRoom,
      forwardRepository: forwardRepo,
      realtimeSyncCase: realtimeSyncCase,
    );
  });

  tearDown(() async {
    await repo.dispose();
    await roomRepo.dispose();
    await forwardRepo.dispose();
    await realtimePort.dispose();
  });

  group('InboxCase.fetch', () {
    test('delegates to repository with userId', () async {
      final items = [
        InboxItem(
          beaconId: 'b1',
          latestForwardAt: DateTime.utc(2026),
        ),
      ];
      repo.fetchResult = items;

      final result = await case_.fetch(userId: 'u1');

      expect(repo.lastFetchUserId, 'u1');
      expect(result, same(items));
    });
  });

  group('InboxCase.setStatus', () {
    test('delegates beaconId, status, and rejectionMessage', () async {
      await case_.setStatus(
        beaconId: 'b1',
        status: InboxItemStatus.rejected,
        rejectionMessage: 'no thanks',
      );

      expect(repo.lastSetStatus, (
        beaconId: 'b1',
        status: InboxItemStatus.rejected,
        rejectionMessage: 'no thanks',
      ));
    });
  });

  group('InboxCase.dismissTombstone', () {
    test('delegates beaconId and dismissedAt', () async {
      final dismissedAt = DateTime.utc(2026, 3, 15);

      await case_.dismissTombstone(
        beaconId: 'b1',
        dismissedAt: dismissedAt,
      );

      expect(repo.lastDismissTombstone, (
        beaconId: 'b1',
        dismissedAt: dismissedAt,
      ));
    });
  });

  group('InboxCase.resolveRoomUnread', () {
    test('delegates to BeaconThreadsCase watermark resolution', () {
      final serverSeenAt = DateTime.utc(2026);
      beaconRoom.observeReadThrough('b1', DateTime.utc(2026, 1, 5));

      expect(
        case_.resolveRoomUnread(
          beaconId: 'b1',
          serverCount: 3,
          serverSeenAt: serverSeenAt,
        ),
        0,
      );
    });
  });

  group('InboxCase.localMutations', () {
    test('emits on repository local mutations', () async {
      final events = <void>[];
      final sub = case_.localMutations.listen(events.add);

      repo.emitLocalMutation();
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      await sub.cancel();
    });

    test('emits on read watermark changes', () async {
      final events = <void>[];
      final sub = case_.localMutations.listen(events.add);

      beaconRoom.observeReadThrough('b1', DateTime.utc(2026));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      await sub.cancel();
    });
  });

  group('InboxCase.deskRelevantChanges', () {
    test('forwards room invalidation beacon ids', () async {
      final ids = <String>[];
      final sub = case_.deskRelevantChanges.listen(ids.add);

      roomRepo.emitRoomInvalidation(
        const BeaconRoomInvalidation(
          beaconId: 'b-room',
          entityType: BeaconRoomEntityType.roomMessage,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(ids, ['b-room']);
      await sub.cancel();
    });
  });

  group('InboxCubit desk-relevant invalidation', () {
    test('debounces duplicate room changes before refetch', () async {
      final cubit = InboxCubit(
        userId: 'u1',
        inboxCase: case_,
        effects: FakeUiEffectPort(),
      );
      await cubit.stream.firstWhere((s) => s.isSuccess);
      expect(repo.fetchCallCount, 1);

      roomRepo
        ..emitRoomInvalidation(
          const BeaconRoomInvalidation(
            beaconId: 'b-room',
            entityType: BeaconRoomEntityType.roomMessage,
          ),
        )
        ..emitRoomInvalidation(
          const BeaconRoomInvalidation(
            beaconId: 'b-room',
            entityType: BeaconRoomEntityType.coordinationItem,
          ),
        );

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(repo.fetchCallCount, 2);

      await cubit.close();
    });

    test('room-seen invalidation refetches and clears room unread', () async {
      repo.fetchResult = [
        _item(status: InboxItemStatus.watching, roomUnreadCount: 1),
      ];
      final effects = FakeUiEffectPort();
      final cubit = InboxCubit(
        userId: 'u1',
        inboxCase: case_,
        effects: effects,
      );
      await cubit.stream.firstWhere((state) => state.isSuccess);
      expect(cubit.state.items.single.roomHints?.roomUnreadCount, 1);
      repo.fetchResult = [
        _item(status: InboxItemStatus.watching, roomUnreadCount: 0),
      ];

      roomRepo.emitRoomInvalidation(
        const BeaconRoomInvalidation(
          beaconId: 'b-forward',
          entityType: BeaconRoomEntityType.roomSeen,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(cubit.state.items.single.roomHints?.roomUnreadCount, 0);
      expect(effects.emitted, isEmpty);
      await cubit.close();
    });

    test(
      'remote forward echo refreshes silently without movement nudge',
      () async {
        repo.fetchResult = [_item(status: InboxItemStatus.needsMe)];
        final effects = FakeUiEffectPort();
        final cubit = InboxCubit(
          userId: 'u1',
          inboxCase: case_,
          effects: effects,
        );
        await cubit.stream.firstWhere((state) => state.isSuccess);
        repo.fetchResult = [_item(status: InboxItemStatus.watching)];

        forwardRepo.emitForwardChange('b-forward');
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(cubit.state.items.single.status, InboxItemStatus.watching);
        expect(cubit.state.pendingMovedNudge, isNull);
        expect(effects.emitted, isEmpty);
        await cubit.close();
      },
    );

    test('local forward command alone may create movement nudge', () async {
      repo.fetchResult = [_item(status: InboxItemStatus.needsMe)];
      final cubit = InboxCubit(
        userId: 'u1',
        inboxCase: case_,
        effects: FakeUiEffectPort(),
      );
      await cubit.stream.firstWhere((state) => state.isSuccess);
      repo.fetchResult = [_item(status: InboxItemStatus.watching)];

      forwardRepo.emitForwardCommandCompleted('b-forward');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(cubit.state.pendingMovedNudge?.beaconId, 'b-forward');
      expect(
        cubit.state.pendingMovedNudge?.toStatus,
        InboxItemStatus.watching,
      );
      await cubit.close();
    });

    test('catch-up silently refreshes the authoritative list', () async {
      repo.fetchResult = [_item(status: InboxItemStatus.needsMe)];
      final cubit = InboxCubit(
        userId: 'u1',
        inboxCase: case_,
        effects: FakeUiEffectPort(),
      );
      await cubit.stream.firstWhere((state) => state.isSuccess);
      repo.fetchResult = [_item(status: InboxItemStatus.rejected)];

      realtimePort.emitCatchUp();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.items.single.status, InboxItemStatus.rejected);
      expect(cubit.state.pendingMovedNudge, isNull);
      await cubit.close();
    });

    test('block change silently refreshes the authoritative list', () async {
      final blockCase = ControllableBlockCase();
      final blockInboxCase = buildTestInboxCase(
        repo,
        beaconRoom,
        forwardRepository: forwardRepo,
        realtimeSyncCase: realtimeSyncCase,
        blockCase: blockCase,
      );
      repo.fetchResult = [_item(status: InboxItemStatus.needsMe)];
      final cubit = InboxCubit(
        userId: 'u1',
        inboxCase: blockInboxCase,
        effects: FakeUiEffectPort(),
      );
      await cubit.stream.firstWhere((state) => state.isSuccess);
      expect(repo.fetchCallCount, 1);
      repo.fetchResult = [_item(status: InboxItemStatus.rejected)];

      blockCase.emitBlock();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.items.single.status, InboxItemStatus.rejected);
      expect(cubit.state.pendingMovedNudge, isNull);
      await cubit.close();
      await blockCase.dispose();
    });

    test('overlapping fetches coalesce; latest snapshot wins', () async {
      repo.fetchResult = [_item(status: InboxItemStatus.needsMe)];
      final cubit = InboxCubit(
        userId: 'u1',
        inboxCase: case_,
        effects: FakeUiEffectPort(),
      );
      await cubit.stream.firstWhere((state) => state.isSuccess);

      final first = Completer<List<InboxItem>>();
      final second = Completer<List<InboxItem>>();
      repo.pendingFetches.addAll([first, second]);

      final a = cubit.fetch(showLoading: false, showError: false);
      final b = cubit.fetch(showLoading: false, showError: false);

      first.complete([_item(status: InboxItemStatus.watching)]);
      await Future<void>.delayed(Duration.zero);
      second.complete([_item(status: InboxItemStatus.rejected)]);

      expect(await a, isTrue);
      expect(await b, isTrue);
      expect(cubit.state.items.single.status, InboxItemStatus.rejected);
      await cubit.close();
    });

    test(
      'empty initial load is not stuck when a silent refresh fails',
      () async {
        final initial = Completer<List<InboxItem>>();
        final silent = Completer<List<InboxItem>>();
        repo.pendingFetches.addAll([initial, silent]);

        final cubit = InboxCubit(
          userId: 'u1',
          inboxCase: case_,
          effects: FakeUiEffectPort(),
        );
        expect(cubit.state.isLoading, isTrue);

        realtimePort.emitCatchUp();
        await Future<void>.delayed(Duration.zero);

        initial.complete(const []);
        await Future<void>.delayed(Duration.zero);
        silent.completeError(Exception('silent refresh failed'));
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.isSuccess, isTrue);
        expect(cubit.state.projectionLoaded, isTrue);
        expect(cubit.state.isLoading, isFalse);
        expect(cubit.state.items, isEmpty);
        await cubit.close();
      },
    );
  });
}

InboxItem _item({
  required InboxItemStatus status,
  int? roomUnreadCount,
}) => InboxItem(
  beaconId: 'b-forward',
  latestForwardAt: DateTime.utc(2026),
  status: status,
  roomHints: roomUnreadCount == null
      ? null
      : InboxRoomCardHints(
          isRoomMember: true,
          roomUnreadCount: roomUnreadCount,
        ),
);

InboxCase buildTestInboxCase(
  FakeInboxRepository repo,
  BeaconThreadsCase beaconRoom, {
  ForwardRepository? forwardRepository,
  RealtimeSyncCase? realtimeSyncCase,
  BookkeepingRefreshSignal? bookkeepingRefreshSignal,
  BlockCase? blockCase,
}) => InboxCase(
  repo,
  beaconRoom,
  forwardRepository ?? _FakeForwardRepository(),
  realtimeSyncCase ?? RealtimeSyncCase(_TestRealtimeSyncPort()),
  bookkeepingRefreshSignal ?? BookkeepingRefreshSignal(),
  blockCase ?? noopBlockCase(),
  env: const Env(),
  logger: Logger('test'),
);

BeaconThreadsCase _buildTestBeaconThreadsCase({
  _FakeBeaconThreadsRepository? roomRepo,
}) => BeaconThreadsCase(
  roomRepo ?? _FakeBeaconThreadsRepository(),
  _FakeFactCardRepository(),
  _FakePollingRepository(),
  _FakeRoomHints(),
  RoomReadWatermarkStore.testing(),
  CoordinationItemCase(_FakeCoordinationItemRepository()),
  RealtimeSyncCase(_TestRealtimeSyncPort()),
  env: const Env(),
  logger: Logger('test'),
);

class _FakeRoomHints implements BeaconRoomHintsRepository {
  @override
  Future<Map<String, InboxRoomCardHints>> fetchByBeaconIds(
    Iterable<String> beaconIds,
  ) async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconThreadsRepository implements BeaconThreadsRepository {
  final _roomInvalidations =
      StreamController<BeaconRoomInvalidation>.broadcast();

  @override
  Stream<String> get beaconRoomRefresh =>
      _roomInvalidations.stream.map((e) => e.beaconId);

  @override
  Stream<BeaconRoomInvalidation> get beaconRoomInvalidations =>
      _roomInvalidations.stream;

  void emitRoomInvalidation(BeaconRoomInvalidation invalidation) {
    _roomInvalidations.add(invalidation);
  }

  @override
  Future<void> dispose() => _roomInvalidations.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePollingRepository implements PollingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoordinationItemRepository implements CoordinationItemRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInboxRepository implements InboxRepository {
  final _localMutationsController = StreamController<void>.broadcast();

  List<InboxItem> fetchResult = const [];
  String? lastFetchUserId;
  int fetchCallCount = 0;
  final pendingFetches = <Completer<List<InboxItem>>>[];

  ({
    String beaconId,
    InboxItemStatus status,
    String rejectionMessage,
  })?
  lastSetStatus;

  ({
    String beaconId,
    DateTime? dismissedAt,
  })?
  lastDismissTombstone;

  @override
  Stream<void> get localMutations => _localMutationsController.stream;

  void emitLocalMutation() {
    if (!_localMutationsController.isClosed) {
      _localMutationsController.add(null);
    }
  }

  @override
  Future<List<InboxItem>> fetch({required String userId}) async {
    fetchCallCount++;
    lastFetchUserId = userId;
    if (pendingFetches.isNotEmpty) {
      return pendingFetches.removeAt(0).future;
    }
    return fetchResult;
  }

  @override
  Future<
    ({
      InboxItemStatus? status,
      InboxProvenance provenance,
      String latestNotePreview,
    })
  >
  fetchInboxContextForBeacon(String beaconId) {
    throw UnimplementedError();
  }

  @override
  Future<void> setStatus({
    required String beaconId,
    required InboxItemStatus status,
    String rejectionMessage = '',
  }) async {
    lastSetStatus = (
      beaconId: beaconId,
      status: status,
      rejectionMessage: rejectionMessage,
    );
  }

  @override
  Future<void> dismissTombstone({
    required String beaconId,
    DateTime? dismissedAt,
  }) async {
    lastDismissTombstone = (
      beaconId: beaconId,
      dismissedAt: dismissedAt,
    );
  }

  @override
  Future<void> dispose() async {
    await _localMutationsController.close();
  }
}

class _FakeForwardRepository implements ForwardRepository {
  final _helpOfferChanges = StreamController<HelpOfferEvent>.broadcast();
  final _forwardChanges = StreamController<String>.broadcast();
  final _forwardCommandCompleted = StreamController<String>.broadcast();

  @override
  Stream<HelpOfferEvent> get helpOfferChanges => _helpOfferChanges.stream;

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Stream<String> get forwardCommandCompleted => _forwardCommandCompleted.stream;

  void emitForwardChange(String beaconId) => _forwardChanges.add(beaconId);

  void emitForwardCommandCompleted(String beaconId) {
    _forwardChanges.add(beaconId);
    _forwardCommandCompleted.add(beaconId);
  }

  @override
  Future<void> dispose() async {
    await _helpOfferChanges.close();
    await _forwardChanges.close();
    await _forwardCommandCompleted.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _TestRealtimeSyncPort implements RealtimeSyncPort {
  final _catchUps = StreamController<RealtimeCatchUp>.broadcast();

  void emitCatchUp() {
    _catchUps.add(
      const RealtimeCatchUp(
        accountId: 'u1',
        connectionEpoch: 2,
        reason: RealtimeCatchUpReason.webSocketReconnected,
      ),
    );
  }

  @override
  Stream<RealtimeCatchUp> get catchUps => _catchUps.stream;

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      const Stream.empty();

  @override
  Stream<RealtimeEntityChange> get entityChanges => const Stream.empty();

  @override
  void requestCatchUp(RealtimeCatchUpReason reason) {}

  @override
  Future<void> dispose() => _catchUps.close();
}
