import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/message/discussion_read_only_message.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

class _TrackingRepository extends FakeBeaconThreadsRepository {
  _TrackingRepository() : super(userId: kRoomCubitFakeMyUserId);

  final deletedIds = <String>[];
  int editCalls = 0;
  int reactionCalls = 0;

  @override
  Future<void> deleteMessage({
    required String beaconId,
    required String messageId,
  }) async {
    deletedIds.add(messageId);
    await super.deleteMessage(beaconId: beaconId, messageId: messageId);
  }

  @override
  Future<void> editMessage({
    required String beaconId,
    required String messageId,
    required String body,
  }) async {
    editCalls++;
  }

  @override
  Future<bool> toggleReaction({
    required String beaconId,
    required String messageId,
    required String emoji,
  }) async {
    reactionCalls++;
    return true;
  }
}

RoomMessage _message(String id, String authorId) => RoomMessage(
  id: id,
  beaconId: kRoomCubitFakeBeaconId,
  authorId: authorId,
  body: 'message',
  createdAt: DateTime.utc(2026),
);

void main() {
  for (final expired in [false, true]) {
    final lifecycle = expired ? 'expired' : 'closed';
    group('$lifecycle Post discussion', () {
      late _TrackingRepository repository;
      late FakeUiEffectPort effects;
      late RoomCubit cubit;

      setUp(() async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        repository = _TrackingRepository()
          ..messages = [
            _message('own', kRoomCubitFakeMyUserId),
            _message('other', 'another-user'),
          ];
        effects = FakeUiEffectPort();
        cubit = RoomCubit(
          beaconId: kRoomCubitFakeBeaconId,
          beaconRoomCase: roomCubitMakeCase(repository),
          coordinationItemRoomSync: CoordinationItemRoomSync(),
          presenceRepository: roomCubitFakePresenceRepository(),
          effects: effects,
          capabilities: const RoomCapabilities.post(),
        );
        addTearDown(repository.dispose);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);
        cubit.syncBeaconStatus(
          expired ? BeaconStatus.open : BeaconStatus.closed,
        );
        if (expired) cubit.syncBeaconExpired(true);
      });

      test('allows a viewer to delete their own message', () async {
        await cubit.deleteMessage(messageId: 'own');

        expect(repository.deletedIds, ['own']);
        expect(
          cubit.state.messages.map((message) => message.id),
          isNot(contains('own')),
        );
        expect(
          effects.emitted.whereType<ShowMessage>().where(
            (effect) => effect.message is DiscussionReadOnlyMessage,
          ),
          isEmpty,
        );
      });

      test('refuses other discussion writes', () async {
        expect(await cubit.sendMessage(body: 'new message'), isFalse);
        await cubit.editMessage(messageId: 'own', newBody: 'edited');
        await cubit.toggleReaction(messageId: 'own', emoji: '👍');
        await cubit.deleteMessage(messageId: 'other');

        expect(repository.createMessageCalls, 0);
        expect(repository.editCalls, 0);
        expect(repository.reactionCalls, 0);
        expect(repository.deletedIds, isEmpty);
        expect(
          cubit.state.messages.map((message) => message.id),
          containsAll(['own', 'other']),
        );
        expect(
          effects.emitted.whereType<ShowMessage>().map(
            (effect) => effect.message,
          ),
          everyElement(isA<DiscussionReadOnlyMessage>()),
        );
        expect(effects.emitted.whereType<ShowMessage>(), hasLength(4));
      });
    });
  }

  test('closed Request refuses deletion of the viewer’s own message', () async {
    registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
    final repository = _TrackingRepository()
      ..messages = [_message('own', kRoomCubitFakeMyUserId)];
    final effects = FakeUiEffectPort();
    final cubit = roomCubitForTest(repository, effects: effects);
    addTearDown(repository.dispose);
    addTearDown(cubit.close);
    await awaitRoomCubitLoad(cubit);
    cubit.syncBeaconStatus(BeaconStatus.closed);

    await cubit.deleteMessage(messageId: 'own');

    expect(repository.deletedIds, isEmpty);
    expect(cubit.state.messages.map((message) => message.id), contains('own'));
    expect(
      effects.emitted.whereType<ShowMessage>().single.message,
      isA<DiscussionReadOnlyMessage>(),
    );
  });
}
