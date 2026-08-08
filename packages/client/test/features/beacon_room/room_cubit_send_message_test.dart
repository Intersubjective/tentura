import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/data/service/user_presence_service.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_repository.dart';
import 'package:tentura/features/beacon_room/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_room/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../../support/test_realtime_sync.dart';
import 'fake_coordination_item_case.dart';

const _kBeaconId = 'b-send-test';
const _kMyUserId = 'me-send';

class _FakeBeaconRoomRepository extends Fake implements BeaconRoomRepository {
  _FakeBeaconRoomRepository({required this.userId});

  final String userId;

  List<RoomMessage> messages = [];
  Object? createMessageError;
  Object? addAttachmentError;
  int createMessageCalls = 0;
  int addAttachmentCalls = 0;

  final _roomInvalidations =
      StreamController<BeaconRoomInvalidation>.broadcast();

  @override
  Stream<String> get beaconRoomRefresh => const Stream.empty();

  @override
  Stream<BeaconRoomInvalidation> get beaconRoomInvalidations =>
      _roomInvalidations.stream;

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) async => messages;

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
      ),
    ];
  }

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async =>
      BeaconRoomState(beaconId: beaconId, updatedAt: DateTime.utc(2026));

  @override
  Future<DateTime> markRoomSeen({
    required String beaconId,
    required DateTime readThroughAt,
    String? threadItemId,
  }) async => readThroughAt;

  @override
  Future<String> createMessage({
    required String beaconId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    RoomPendingUpload? firstAttachment,
  }) async {
    createMessageCalls++;
    final error = createMessageError;
    if (error != null) throw error;
    return 'msg-created';
  }

  @override
  Future<void> addMessageAttachment({
    required String beaconId,
    required String messageId,
    required RoomPendingUpload upload,
  }) async {
    addAttachmentCalls++;
    final error = addAttachmentError;
    if (error != null) throw error;
  }

  @override
  Future<void> dispose() => _roomInvalidations.close();
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
  ProfileState get state => ProfileState(
    profile: Profile(id: _userId, displayName: 'T'),
  );

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

RoomPendingUpload _upload(String fileName) => RoomPendingUpload(
  bytes: Uint8List.fromList([1, 2, 3]),
  fileName: fileName,
  mimeType: 'application/octet-stream',
);

PresenceRepository _fakePresenceRepository() => PresenceRepository(
  UserPresenceService.forTesting(
    messages: const Stream.empty(),
    connectionState: const Stream.empty(),
    send: (_) {},
  ),
);

BeaconRoomCase _makeCase(_FakeBeaconRoomRepository fakeRoom) =>
    BeaconRoomCase(
      fakeRoom,
      _FakeBeaconFactCardRepository(),
      _FakePollingRepository(),
      _FakeBeaconRoomHintsRepository(),
      RoomReadWatermarkStore.testing(),
      const FakeCoordinationItemCaseForRoom(),
      buildTestRealtimeSync().case_,
      env: const Env(),
      logger: Logger('test'),
    );

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

Future<RoomState> _awaitLoad(RoomCubit cubit) =>
    cubit.stream.firstWhere((s) => s.status is! StateIsLoading);

RoomCubit _roomCubit(
  _FakeBeaconRoomRepository fakeRoom, {
  UiEffectPort? effects,
}) => RoomCubit(
  beaconId: _kBeaconId,
  beaconRoomCase: _makeCase(fakeRoom),
  coordinationItemRoomSync: CoordinationItemRoomSync(),
  presenceRepository: _fakePresenceRepository(),
  effects: effects ?? FakeUiEffectPort(),
);

void main() {
  group('RoomCubit.sendMessage', () {
    test('returns false for blank input with no uploads', () async {
      _registerProfileCubit(_kMyUserId);
      final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId);
      final cubit = _roomCubit(fakeRoom);
      addTearDown(cubit.close);

      await _awaitLoad(cubit);

      expect(await cubit.sendMessage(body: '   '), isFalse);
      expect(fakeRoom.createMessageCalls, 0);
    });

    test('returns true on success', () async {
      _registerProfileCubit(_kMyUserId);
      final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId);
      final cubit = _roomCubit(fakeRoom);
      addTearDown(cubit.close);

      await _awaitLoad(cubit);

      expect(await cubit.sendMessage(body: 'hello'), isTrue);
      expect(fakeRoom.createMessageCalls, 1);
    });

    test('returns false when use case throws before message is created', () async {
      _registerProfileCubit(_kMyUserId);
      final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId)
        ..createMessageError = StateError('network');
      final effects = FakeUiEffectPort();
      final cubit = _roomCubit(fakeRoom, effects: effects);
      addTearDown(cubit.close);

      await _awaitLoad(cubit);
      final beforeCount = cubit.state.messages.length;

      expect(await cubit.sendMessage(body: 'hello'), isFalse);
      expect(fakeRoom.createMessageCalls, 1);
      expect(fakeRoom.addAttachmentCalls, 0);
      expect(cubit.state.messages.length, beforeCount);
      expect(effects.emitted, isNotEmpty);
    });

    test(
      'returns false when extra attachment fails after create succeeds',
      () async {
        _registerProfileCubit(_kMyUserId);
        final fakeRoom = _FakeBeaconRoomRepository(userId: _kMyUserId)
          ..addAttachmentError = StateError('upload failed');
        final effects = FakeUiEffectPort();
        final cubit = _roomCubit(fakeRoom, effects: effects);
        addTearDown(cubit.close);

        await _awaitLoad(cubit);
        final beforeCount = cubit.state.messages.length;

        expect(
          await cubit.sendMessage(
            body: 'two files',
            uploads: [_upload('a.png'), _upload('b.png')],
          ),
          isFalse,
        );
        expect(fakeRoom.createMessageCalls, 1);
        expect(fakeRoom.addAttachmentCalls, 1);
        expect(cubit.state.messages.length, beforeCount);
        expect(effects.emitted, isNotEmpty);
      },
    );
  });
}
