import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/message/beacon_room_fact_messages.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';
import 'support/room_hint_wire_harness.dart';

const _targetId = 'Mpostreply001';
const _latestId = 'Mpostreply002';
const _latestBody = 'I am still available';
const _deadline = Duration(seconds: 5);

Map<String, dynamic> _reply(String id, String body, int minute) =>
    roomHintWireMessageRow(
      id: id,
      authorId: 'Umember000001',
      authorTitle: 'Member',
      createdAt: DateTime.utc(2026, 1, 1, 12, minute).toIso8601String(),
      body: body,
    );

void main() {
  late RoomHintWireServer server;
  late RoomOverRealHintWireRepository repository;
  late FakeUiEffectPort effects;

  setUp(() async {
    server = RoomHintWireServer()
      ..messageRows = [_reply(_latestId, _latestBody, 2)];
    final wire = await RoomHintWire.start(server).timeout(_deadline);
    addTearDown(wire.close);
    repository = RoomOverRealHintWireRepository(wire.repository);
    effects = FakeUiEffectPort();
    registerRoomCubitProfileCubit(roomHintWireViewerId);
  });

  RoomCubit openChat({String? messageId}) {
    final room = RoomCubit(
      beaconId: kRoomCubitFakeBeaconId,
      beaconRoomCase: roomCubitMakeCase(repository),
      coordinationItemRoomSync: CoordinationItemRoomSync(),
      presenceRepository: roomCubitFakePresenceRepository(),
      effects: effects,
      capabilities: const RoomCapabilities.post(),
    );
    addTearDown(room.close);
    room.prepareThreadScroll(messageId: messageId);
    return room;
  }

  void expectLoadedPage(RoomCubit room) {
    expect(room.state.status, isA<StateIsSuccess>());
    expect(room.state.loadError, isNull);
    expect(
      room.state.messages.map((message) => (message.id, message.body)),
      [(_latestId, _latestBody)],
    );
    expect(room.state.scrollToMessageId, isNull);
    expect(effects.emitted, isEmpty);
  }

  test(
    'a null reply target leaves Chat loaded and is looked up only once',
    () async {
      server.messageTargetResponses[_targetId] = const {
        'data': {'roomMessageTarget': null},
      };
      final room = openChat(messageId: _targetId);
      await awaitRoomCubitLoad(room).timeout(_deadline);
      expectLoadedPage(room);
      expect(server.requestedMessageTargetIds, [_targetId]);
      expect(repository.messageTargetResults, [null]);

      await room.reloadMessages(silent: true).timeout(_deadline);
      expectLoadedPage(room);
      expect(repository.fetchMessagesCallCount, 2);
      expect(server.requestedMessageTargetIds, [_targetId]);
    },
  );

  test(
    'a not-found reply error leaves the first Chat page loaded silently',
    () async {
      server.messageTargetResponses[_targetId] =
          roomMessageTargetNotFoundResponse;
      final room = openChat(messageId: _targetId);
      await awaitRoomCubitLoad(room).timeout(_deadline);
      expect(server.requestedMessageTargetIds, [_targetId]);
      expectLoadedPage(room);

      await room.reloadMessages(silent: true).timeout(_deadline);
      expectLoadedPage(room);
      expect(repository.fetchMessagesCallCount, 2);
      expect(server.requestedMessageTargetIds, [_targetId]);
    },
  );

  test('Chat selects an existing reply outside the latest page', () async {
    const olderBody = 'I can help';
    server.messageTargets[_targetId] = _reply(_targetId, olderBody, 1);
    final room = openChat(messageId: _targetId);
    await awaitRoomCubitLoad(room).timeout(_deadline);
    expect(server.requestedMessageTargetIds, [_targetId]);
    expect(room.state.scrollToMessageId, _targetId);
    expect(
      room.state.messages.map((message) => (message.id, message.body)),
      [(_targetId, olderBody), (_latestId, _latestBody)],
    );
  });

  test(
    'jumping to a deleted reply shows it is unavailable and preserves Chat',
    () async {
      server.messageTargetResponses[_targetId] =
          roomMessageTargetNotFoundResponse;
      final room = openChat();
      await awaitRoomCubitLoad(room).timeout(_deadline);
      expectLoadedPage(room);
      final messages = room.state.messages;

      expect(
        await room.jumpToRepliedMessage(_targetId).timeout(_deadline),
        isFalse,
      );
      expect(server.requestedMessageTargetIds, [_targetId]);
      expect(room.state.messages, messages);
      expect(room.state.scrollToMessageId, isNull);
      expect(effects.emitted, [
        isA<ShowMessage>().having(
          (effect) => effect.message,
          'message',
          isA<RoomReplyTargetUnavailableMessage>(),
        ),
      ]);
    },
  );
}
