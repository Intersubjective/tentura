import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_repository.dart';
import 'package:tentura/features/beacon_room/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_room/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'fake_coordination_item_case.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeBeaconRoomRepository extends Fake implements BeaconRoomRepository {
  _FakeBeaconRoomRepository({required this.userId});

  final String userId;

  DateTime? participantLastSeenRoomAt;
  bool markRoomSeenCalled = false;
  List<RoomMessage> messages = [];

  /// Set this to block fetchMessages until the completer resolves.
  Completer<void>? fetchMessagesCompleter;

  @override
  Stream<String> get beaconRoomRefresh => const Stream.empty();

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) async {
    final gate = fetchMessagesCompleter;
    if (gate != null) {
      fetchMessagesCompleter = null;
      await gate.future;
    }
    return messages;
  }

  @override
  Future<List<BeaconParticipant>> fetchParticipants(String beaconId) async {
    if (userId.isEmpty) return const [];
    return [
      BeaconParticipant(
        id: 'p1',
        beaconId: beaconId,
        userId: userId,
        role: 0,
        status: 0,
        roomAccess: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        lastSeenRoomAt: participantLastSeenRoomAt,
      ),
    ];
  }

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async =>
      BeaconRoomState(beaconId: beaconId, updatedAt: DateTime.utc(2026));

  @override
  Future<DateTime> markRoomSeen({
    required String beaconId,
    String? threadItemId,
    required DateTime readThroughAt,
  }) async {
    markRoomSeenCalled = true;
    participantLastSeenRoomAt = readThroughAt;
    return readThroughAt;
  }

  @override
  Future<String> createMessage({
    required String beaconId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    RoomPendingUpload? firstAttachment,
  }) async =>
      'msg-created';
}

class _FakeBeaconFactCardRepository extends Fake
    implements BeaconFactCardRepository {
  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async => [];
}

class _FakeBeaconRoomHintsRepository extends Fake
    implements BeaconRoomHintsRepository {}

class _FakePollingRepository extends Fake implements PollingRepository {}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(String userId) : _userId = userId;
  final String _userId;

  @override
  ProfileState get state =>
      ProfileState(profile: Profile(id: _userId, displayName: 'T'));

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _kBeaconId = 'b-test';
const _kMyUserId = 'me-test';

final _kAnchorTime = DateTime.utc(2026, 1, 1, 12);

RoomMessage _msg(String id, DateTime createdAt, {String authorId = 'other'}) =>
    RoomMessage(
      id: id,
      beaconId: _kBeaconId,
      authorId: authorId,
      body: '',
      createdAt: createdAt,
    );

final _testItemSync = CoordinationItemRoomSync();

RoomCubit _roomCubit(_FakeBeaconRoomRepository fakeRoom) => RoomCubit(
      beaconId: _kBeaconId,
      beaconRoomCase: _makeCase(fakeRoom),
      coordinationItemRoomSync: _testItemSync,
    );

/// Creates a [BeaconRoomCase] backed by [fakeRoom] and minimal stubs.
BeaconRoomCase _makeCase(_FakeBeaconRoomRepository fakeRoom) =>
    BeaconRoomCase(
      fakeRoom,
      _FakeBeaconFactCardRepository(),
      _FakePollingRepository(),
      _FakeBeaconRoomHintsRepository(),
      RoomReadWatermarkStore.testing(),
      const FakeCoordinationItemCaseForRoom(),
      env: const Env(),
      logger: Logger('test'),
    );

/// Registers a stub [ProfileCubit] returning [userId] and schedules cleanup.
void _registerProfileCubit(String userId) {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<ProfileCubit>()) {
    // ignore: discarded_futures -- GetIt.unregister returns FutureOr; unregister is best-effort before re-register.
    getIt.unregister<ProfileCubit>();
  }
  getIt.registerSingleton<ProfileCubit>(_MockProfileCubit(userId));
  addTearDown(() {
    if (getIt.isRegistered<ProfileCubit>()) {
      // ignore: discarded_futures -- GetIt.unregister returns FutureOr; teardown does not need to await dispose.
      getIt.unregister<ProfileCubit>();
    }
  });
}

/// Waits for the cubit to leave [StateIsLoading].
Future<RoomState> _awaitLoad(RoomCubit cubit) =>
    cubit.stream.firstWhere((s) => s.status is! StateIsLoading);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RoomCubit unread anchor', () {
    test('load() derives anchor from participant lastSeenRoomAt', () async {
      _registerProfileCubit(_kMyUserId);

      final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId)
        ..participantLastSeenRoomAt = _kAnchorTime
        ..messages = [
          _msg('old', _kAnchorTime.subtract(const Duration(hours: 1))),
          _msg('new', _kAnchorTime.add(const Duration(hours: 1))),
        ];

      final cubit = _roomCubit(fakeRoom);
      addTearDown(cubit.close);

      final s = await _awaitLoad(cubit);

      expect(s.unreadAnchorAt, equals(_kAnchorTime));
      expect(s.unreadCount, 1, reason: 'only message after anchor is unread');
      expect(s.firstUnreadMessageId, 'new');
    });

    test('load() leaves anchor null when user has no participant record', () async {
      // Regression: beacon author had no row in beacon_participants, so anchor
      // stayed null and all messages were counted as unread after the first
      // load — this is the intended behaviour until markRoomSeen upserts a row.
      _registerProfileCubit(_kMyUserId);

      final fakeRoom = _FakeBeaconRoomRepository(userId: '')
        ..messages = [
          _msg('m1', _kAnchorTime),
          _msg('m2', _kAnchorTime.add(const Duration(minutes: 1))),
        ];

      final cubit = _roomCubit(fakeRoom);
      addTearDown(cubit.close);

      final s = await _awaitLoad(cubit);

      expect(s.unreadAnchorAt, isNull);
      expect(s.unreadCount, 2, reason: 'all messages are unread with null anchor');
    });

    test('markSeenNowIfNeeded sets flag only on successful persist', () async {
      _registerProfileCubit(_kMyUserId);

      final newMsgTime = _kAnchorTime.add(const Duration(hours: 1));
      final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId)
        ..participantLastSeenRoomAt = _kAnchorTime
        ..messages = [
          _msg('new', newMsgTime),
        ];

      final case_ = _makeCase(fakeRoom);
      final cubit = RoomCubit(
        beaconId: _kBeaconId,
        beaconRoomCase: case_,
        coordinationItemRoomSync: _testItemSync,
      );
      addTearDown(cubit.close);

      await _awaitLoad(cubit);
      await cubit.markSeenNowIfNeeded();
      expect(cubit.state.pendingMarkSeen, isFalse);

      fakeRoom.markRoomSeenCalled = false;
      // Second call should be skipped (already emitted this visit).
      await cubit.markSeenNowIfNeeded();
      expect(fakeRoom.markRoomSeenCalled, isFalse);
    });

    test('local read-through clears unread before server confirms', () async {
      _registerProfileCubit(_kMyUserId);

      final newMsgTime = _kAnchorTime.add(const Duration(hours: 1));
      final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId)
        ..participantLastSeenRoomAt = _kAnchorTime
        ..messages = [
          _msg('new', newMsgTime),
        ];

      final cubit = _roomCubit(fakeRoom);
      addTearDown(cubit.close);

      await _awaitLoad(cubit);
      expect(cubit.state.unreadCount, 1);

      await cubit.markReadToBottom();

      expect(cubit.state.unreadCount, 0);
      expect(cubit.state.unreadAnchorAt, newMsgTime);
    });

    test('anchor never regresses below session watermark on reload', () async {
      _registerProfileCubit(_kMyUserId);

      final watermark = _kAnchorTime.add(const Duration(hours: 2));
      final newMsgTime = _kAnchorTime.add(const Duration(hours: 1));
      final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId)
        ..participantLastSeenRoomAt = _kAnchorTime
        ..messages = [
          _msg('new', newMsgTime),
        ];

      final case_ = _makeCase(fakeRoom);
      case_.observeReadThrough(_kBeaconId, watermark);

      final cubit = RoomCubit(
        beaconId: _kBeaconId,
        beaconRoomCase: case_,
        coordinationItemRoomSync: _testItemSync,
      );
      addTearDown(cubit.close);

      final s = await _awaitLoad(cubit);
      expect(s.unreadAnchorAt, watermark);
      expect(s.unreadCount, 0);
    });

    test('markSeenNowIfNeeded() advances anchor to latest loaded message', () async {
      _registerProfileCubit(_kMyUserId);

      final newMsgTime = _kAnchorTime.add(const Duration(hours: 1));
      final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId)
        ..participantLastSeenRoomAt = _kAnchorTime
        ..messages = [
          _msg('new', newMsgTime),
        ];

      final cubit = _roomCubit(fakeRoom);
      addTearDown(cubit.close);

      await _awaitLoad(cubit);
      expect(cubit.state.unreadAnchorAt, equals(_kAnchorTime));
      expect(cubit.state.unreadCount, 1);

      await cubit.markSeenNowIfNeeded();

      expect(cubit.state.unreadAnchorAt, equals(newMsgTime));
      expect(cubit.state.pendingMarkSeen, isFalse);
      expect(cubit.state.unreadCount, 0);
      expect(cubit.state.firstUnreadMessageId, isNull);
    });

    test('markSeenNowIfNeeded() is blocked until initial load completes', () async {
      // Regression: must not flush before the first load derives unreadAnchorAt.
      _registerProfileCubit(_kMyUserId);

      final gate = Completer<void>();
      final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId)
        ..participantLastSeenRoomAt = _kAnchorTime
        ..fetchMessagesCompleter = gate
        ..messages = [
          _msg('new', _kAnchorTime.add(const Duration(hours: 1))),
        ];

      final cubit = _roomCubit(fakeRoom);
      addTearDown(cubit.close);

      await cubit.markSeenNowIfNeeded();
      expect(
        fakeRoom.markRoomSeenCalled,
        isFalse,
        reason: 'markSeenNowIfNeeded must not fire before initial load',
      );

      gate.complete();
      await _awaitLoad(cubit);

      fakeRoom.markRoomSeenCalled = false;
      await cubit.markSeenNowIfNeeded();
      expect(fakeRoom.markRoomSeenCalled, isTrue);
    });

    test(
      'markSeenNowIfNeeded() fires during a later reload while fetch is in progress',
      () async {
        _registerProfileCubit(_kMyUserId);

        final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId)
          ..participantLastSeenRoomAt = _kAnchorTime
          ..messages = [
            _msg('new', _kAnchorTime.add(const Duration(hours: 1))),
          ];

        final cubit = _roomCubit(fakeRoom);
        addTearDown(cubit.close);

        await _awaitLoad(cubit);

        final gate = Completer<void>();
        fakeRoom
          ..fetchMessagesCompleter = gate
          ..markRoomSeenCalled = false;

        unawaited(cubit.reloadMessages(silent: true));

        await cubit.markSeenNowIfNeeded();
        expect(
          fakeRoom.markRoomSeenCalled,
          isTrue,
          reason: 'mark-seen must not be blocked by concurrent silent reload',
        );

        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(cubit.state.status, isA<StateIsSuccess>());
      },
    );

    test('markReadToBottom() advances anchor and clears unread', () async {
      _registerProfileCubit(_kMyUserId);

      final newMsgTime = _kAnchorTime.add(const Duration(hours: 1));
      final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId)
        ..participantLastSeenRoomAt = _kAnchorTime
        ..messages = [
          _msg('old', _kAnchorTime.subtract(const Duration(hours: 1))),
          _msg('new', newMsgTime),
        ];

      final cubit = _roomCubit(fakeRoom);
      addTearDown(cubit.close);

      await _awaitLoad(cubit);
      expect(cubit.state.unreadCount, 1);

      fakeRoom.markRoomSeenCalled = false;
      await cubit.markReadToBottom();

      expect(cubit.state.unreadCount, 0);
      expect(cubit.state.firstUnreadMessageId, isNull);
      expect(cubit.state.unreadAnchorAt, equals(newMsgTime));
      expect(fakeRoom.markRoomSeenCalled, isTrue);
    });

    test('silent reload after markSeen does not resurrect unread count', () async {
      _registerProfileCubit(_kMyUserId);

      final newMsgTime = _kAnchorTime.add(const Duration(hours: 1));
      final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId)
        ..participantLastSeenRoomAt = _kAnchorTime
        ..messages = [
          _msg('old', _kAnchorTime.subtract(const Duration(hours: 1))),
          _msg('new', newMsgTime),
        ];

      final cubit = _roomCubit(fakeRoom);
      addTearDown(cubit.close);

      await _awaitLoad(cubit);
      expect(cubit.state.unreadCount, 1);

      await cubit.markSeenNowIfNeeded();
      expect(cubit.state.unreadCount, 0);

      await cubit.reloadMessages(silent: true);

      expect(cubit.state.unreadCount, 0);
      expect(cubit.state.firstUnreadMessageId, isNull);
    });

    test('silent reload preserves an advanced anchor', () async {
      _registerProfileCubit(_kMyUserId);

      final newMsgTime = _kAnchorTime.add(const Duration(hours: 1));
      final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId)
        ..participantLastSeenRoomAt = _kAnchorTime
        ..messages = [
          _msg('old', _kAnchorTime.subtract(const Duration(hours: 1))),
          _msg('new', newMsgTime),
        ];

      final cubit = _roomCubit(fakeRoom);
      addTearDown(cubit.close);

      await _awaitLoad(cubit);
      await cubit.markReadToBottom();
      final anchorAfterRead = cubit.state.unreadAnchorAt;
      expect(cubit.state.unreadCount, 0);

      await cubit.reloadMessages(silent: true);

      expect(cubit.state.unreadCount, 0);
      expect(cubit.state.firstUnreadMessageId, isNull);
      // After mark-seen, reload may merge a newer server watermark than the
      // locally advanced anchor.
      expect(
        cubit.state.unreadAnchorAt!.compareTo(anchorAfterRead!) >= 0,
        isTrue,
      );
    });

    test('sendMessage() resets anchor so next load re-derives it from server', () async {
      // Regression: sendMessage() must emit unreadAnchorAt: null before calling
      // load() so that load() re-reads lastSeenRoomAt from the server after the
      // mark-seen upsert. Without this reset the stale anchor remained.
      _registerProfileCubit(_kMyUserId);

      final msgTime = _kAnchorTime.add(const Duration(hours: 1));
      final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId)
        ..participantLastSeenRoomAt = _kAnchorTime // old anchor, before the message
        ..messages = [
          _msg('m1', msgTime), // unread for the current anchor
        ];

      final cubit = _roomCubit(fakeRoom);
      addTearDown(cubit.close);

      await _awaitLoad(cubit);
      expect(cubit.state.unreadCount, 1, reason: 'message is unread before sending');

      await cubit.sendMessage(body: 'hello');

      // After sendMessage → markRoomSeen upserted a row (fake sets participantLastSeenRoomAt
      // to "now") → load() re-derived the anchor from the updated participant.
      // The new anchor must be after msgTime, so unread count is 0.
      expect(
        cubit.state.unreadCount,
        0,
        reason: 'after sending a message the room is fully seen',
      );
      expect(cubit.state.firstUnreadMessageId, isNull);
    });
  });
}
