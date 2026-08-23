import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/data/service/user_presence_service.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_room_message_paint.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_coordination_item_case.dart';

const kRoomCubitFakeBeaconId = 'b-send-test';
const kRoomCubitFakeMyUserId = 'me-send';

class FakeBeaconThreadsRepository extends Fake
    implements BeaconThreadsRepository {
  FakeBeaconThreadsRepository({required this.userId});

  final String userId;

  List<RoomMessage> messages = [];
  Object? createMessageError;
  Object? addAttachmentError;
  int createMessageCalls = 0;
  int addAttachmentCalls = 0;
  int fetchMessagesCallCount = 0;
  String? lastReplyToMessageId;

  /// Blocks [createMessage] until completed (stale reply-target race tests).
  Completer<void>? createMessageGate;

  final Map<String, RoomMessage> fetchMessageTargetsById = {};
  Object? fetchMessageTargetError;

  final _roomInvalidations =
      StreamController<BeaconRoomInvalidation>.broadcast();

  void emitInvalidation(
    BeaconRoomEntityType entityType, {
    RealtimeOperation? operation,
    String? messageId,
    RealtimeRoomMessagePaint? paint,
  }) {
    _roomInvalidations.add(
      BeaconRoomInvalidation(
        beaconId: kRoomCubitFakeBeaconId,
        entityType: entityType,
        operation: operation,
        messageId: messageId,
        paint: paint,
      ),
    );
  }

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
  }) async {
    fetchMessagesCallCount++;
    return messages;
  }

  @override
  Future<RoomMessage?> fetchMessageTarget({
    required String beaconId,
    required String messageId,
  }) async {
    final error = fetchMessageTargetError;
    if (error != null) {
      if (error is Exception) throw error;
      if (error is Error) throw error;
      throw StateError(error.toString());
    }
    return fetchMessageTargetsById[messageId];
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
      ),
    ];
  }

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async =>
      BeaconRoomState(beaconId: beaconId, updatedAt: DateTime.utc(2026));

  @override
  Future<DateTime> markThreadSeen({
    required String beaconId,
    required String threadId,
    required DateTime readThroughAt,
  }) async => readThroughAt;

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
  }) async {
    createMessageCalls++;
    lastReplyToMessageId = replyToMessageId;
    final gate = createMessageGate;
    if (gate != null) {
      await gate.future;
    }
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

class FakeBeaconFactCardRepository extends Fake
    implements BeaconFactCardRepository {
  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async => [];
}

class FakeBeaconRoomHintsRepository extends Fake
    implements BeaconRoomHintsRepository {}

class FakePollingRepository extends Fake implements PollingRepository {}

class MockProfileCubitForRoom extends Mock implements ProfileCubit {
  MockProfileCubitForRoom(String userId) : _userId = userId;
  final String _userId;

  @override
  ProfileState get state => ProfileState(
    profile: Profile(id: _userId, displayName: 'T'),
  );

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

RoomPendingUpload roomCubitFakeUpload(String fileName) => RoomPendingUpload(
  bytes: Uint8List.fromList([1, 2, 3]),
  fileName: fileName,
  mimeType: 'application/octet-stream',
);

PresenceRepository roomCubitFakePresenceRepository() => PresenceRepository(
  UserPresenceService.forTesting(
    messages: const Stream.empty(),
    connectionState: const Stream.empty(),
    send: (_) {},
  ),
);

BeaconThreadsCase roomCubitMakeCase(
  FakeBeaconThreadsRepository fakeRoom, {
  RealtimeSyncCase? realtimeSyncCase,
}) => BeaconThreadsCase(
  fakeRoom,
  FakeBeaconFactCardRepository(),
  FakePollingRepository(),
  FakeBeaconRoomHintsRepository(),
  RoomReadWatermarkStore.testing(),
  const FakeCoordinationItemCaseForRoom(),
  realtimeSyncCase ?? buildTestRealtimeSync().case_,
  env: const Env(),
  logger: Logger('test'),
);

void registerRoomCubitProfileCubit(String userId) {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<ProfileCubit>()) {
    // ignore: discarded_futures -- GetIt.unregister returns FutureOr; unregister is best-effort before re-register.
    getIt.unregister<ProfileCubit>();
  }
  getIt.registerSingleton<ProfileCubit>(MockProfileCubitForRoom(userId));
  addTearDown(() {
    if (getIt.isRegistered<ProfileCubit>()) {
      // ignore: discarded_futures -- GetIt.unregister returns FutureOr; teardown does not need to await dispose.
      getIt.unregister<ProfileCubit>();
    }
  });
}

Future<RoomState> awaitRoomCubitLoad(RoomCubit cubit) =>
    cubit.stream.firstWhere((s) => s.status is! StateIsLoading);

RoomCubit roomCubitForTest(
  FakeBeaconThreadsRepository fakeRoom, {
  UiEffectPort? effects,
  RealtimeSyncCase? realtimeSyncCase,
}) => RoomCubit(
  beaconId: kRoomCubitFakeBeaconId,
  beaconRoomCase: roomCubitMakeCase(
    fakeRoom,
    realtimeSyncCase: realtimeSyncCase,
  ),
  coordinationItemRoomSync: CoordinationItemRoomSync(),
  presenceRepository: roomCubitFakePresenceRepository(),
  effects: effects ?? FakeUiEffectPort(),
);
