import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_room_message_paint.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/message/beacon_room_fact_messages.dart';
import 'package:tentura/features/beacon_room/ui/util/room_reply_excerpt.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

final _kBaseTime = DateTime.utc(2026, 1, 1, 12);

RoomMessage _roomMsg({
  required String id,
  required DateTime createdAt,
  String authorId = 'other',
  String body = 'body',
  Profile? author,
  String? replyToMessageId,
  String? replyToAuthorId,
  String? replyToAuthorTitle,
  String? replyToBodyExcerpt,
  bool replyToHasAttachments = false,
  List<RoomMessageAttachment> attachments = const [],
}) {
  final resolvedAuthor =
      author ?? Profile(id: authorId, displayName: 'Author $authorId');
  return RoomMessage(
    id: id,
    beaconId: kRoomCubitFakeBeaconId,
    authorId: authorId,
    body: body,
    createdAt: createdAt,
    author: resolvedAuthor,
    replyToMessageId: replyToMessageId,
    replyToAuthorId: replyToAuthorId,
    replyToAuthorTitle: replyToAuthorTitle,
    replyToBodyExcerpt: replyToBodyExcerpt,
    replyToHasAttachments: replyToHasAttachments,
    attachments: attachments,
  );
}

Future<void> _awaitCondition(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for room cubit condition.');
}

Future<void> _awaitFetchCount(FakeBeaconRoomRepository room, int expected) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (room.fetchMessagesCallCount >= expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Expected at least $expected message fetches, got ${room.fetchMessagesCallCount}.',
  );
}

RoomMessage? _latestLocalMessage(RoomCubit cubit) {
  for (final message in cubit.state.messages.reversed) {
    if (message.authorId == kRoomCubitFakeMyUserId) {
      return message;
    }
  }
  return null;
}

void main() {
  group('RoomCubit reply target', () {
    test('startReplyTo sets target and cancelReply clears it', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final target = _roomMsg(id: 'target', createdAt: _kBaseTime);
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [target];
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      expect(cubit.state.replyTarget, isNull);

      cubit.startReplyTo(target);
      expect(cubit.state.replyTarget, same(target));

      cubit.cancelReply();
      expect(cubit.state.replyTarget, isNull);
    });

    test('startReplyTo on local: id is a no-op', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final local = _roomMsg(id: 'local:pending', createdAt: _kBaseTime);
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId);
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      cubit.startReplyTo(local);

      expect(cubit.state.replyTarget, isNull);
      expect(RoomCubit.canReplyTo(local), isFalse);
    });
  });

  group('RoomCubit.sendMessage reply quote', () {
    test('passes replyToMessageId and optimistic five quote fields', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final target = _roomMsg(
        id: 'msg-target',
        createdAt: _kBaseTime,
        authorId: 'anna',
        body: 'bring the ladder tomorrow',
        author: const Profile(id: 'anna', displayName: 'Anna'),
        attachments: const [
          RoomMessageAttachment(
            id: 'att-1',
            kind: BeaconRoomMessageAttachmentKind.image,
            position: 0,
            mime: 'image/png',
            sizeBytes: 1024,
            fileName: 'photo.png',
          ),
        ],
      );
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [target];
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      cubit.startReplyTo(target);

      expect(await cubit.sendMessage(body: 'reply body'), isTrue);
      expect(fakeRoom.lastReplyToMessageId, target.id);

      final sent = _latestLocalMessage(cubit);
      expect(sent, isNotNull);
      expect(sent!.replyToMessageId, target.id);
      expect(sent.replyToAuthorId, target.authorId);
      expect(sent.replyToAuthorTitle, target.author.shownName);
      expect(sent.replyToBodyExcerpt, roomReplyExcerpt(target));
      expect(sent.replyToHasAttachments, isTrue);
    });

    test('reply-to-a-reply quotes the target, not the grandparent', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final grandparent = _roomMsg(
        id: 'grandparent',
        createdAt: _kBaseTime,
        authorId: 'bob',
        body: 'original thread',
        author: const Profile(id: 'bob', displayName: 'Bob'),
      );
      final parent = _roomMsg(
        id: 'parent-reply',
        createdAt: _kBaseTime.add(const Duration(minutes: 1)),
        authorId: 'carol',
        body: 'replying to Bob',
        author: const Profile(id: 'carol', displayName: 'Carol'),
        replyToMessageId: grandparent.id,
        replyToAuthorId: grandparent.authorId,
        replyToAuthorTitle: grandparent.author.shownName,
        replyToBodyExcerpt: roomReplyExcerpt(grandparent),
      );
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [grandparent, parent];
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      cubit.startReplyTo(parent);

      expect(await cubit.sendMessage(body: 'nested reply'), isTrue);
      expect(fakeRoom.lastReplyToMessageId, parent.id);

      final sent = _latestLocalMessage(cubit);
      expect(sent, isNotNull);
      expect(sent!.replyToMessageId, parent.id);
      expect(sent.replyToAuthorId, parent.authorId);
      expect(sent.replyToAuthorTitle, parent.author.shownName);
      expect(sent.replyToBodyExcerpt, roomReplyExcerpt(parent));
      expect(sent.replyToBodyExcerpt, isNot(roomReplyExcerpt(grandparent)));
    });

    test('successful send clears reply target', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final target = _roomMsg(id: 'target', createdAt: _kBaseTime);
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [target];
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      cubit.startReplyTo(target);

      expect(await cubit.sendMessage(body: 'done'), isTrue);
      expect(cubit.state.replyTarget, isNull);
    });

    test('failed send keeps reply target', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final target = _roomMsg(id: 'target', createdAt: _kBaseTime);
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [target]
        ..createMessageError = StateError('network');
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      cubit.startReplyTo(target);

      expect(await cubit.sendMessage(body: 'retry me'), isFalse);
      expect(cubit.state.replyTarget, same(target));
    });

    test('stale-clear race keeps newer reply target after in-flight send', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final targetA = _roomMsg(
        id: 'target-a',
        createdAt: _kBaseTime,
        body: 'first',
      );
      final targetB = _roomMsg(
        id: 'target-b',
        createdAt: _kBaseTime.add(const Duration(minutes: 1)),
        body: 'second',
      );
      final gate = Completer<void>();
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [targetA, targetB]
        ..createMessageGate = gate;
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      cubit.startReplyTo(targetA);

      final sendFuture = cubit.sendMessage(body: 'reply A');
      await _awaitCondition(() => fakeRoom.createMessageCalls == 1);

      cubit.startReplyTo(targetB);
      expect(cubit.state.replyTarget?.id, targetB.id);

      gate.complete();
      expect(await sendFuture, isTrue);
      expect(cubit.state.replyTarget?.id, targetB.id);
    });

    test(
      'own reply paint defers during send and replaces optimistic quote',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final target = _roomMsg(
          id: 'parent',
          createdAt: _kBaseTime,
          authorId: 'anna',
          body: 'optimistic parent body',
          author: const Profile(id: 'anna', displayName: 'Anna'),
        );
        final gate = Completer<void>();
        final fakeRoom =
            FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId)
              ..messages = [target]
              ..createMessageGate = gate;
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        addTearDown(fakeRoom.dispose);

        await awaitRoomCubitLoad(cubit);
        cubit.startReplyTo(target);
        final send = cubit.sendMessage(body: 'reply body');
        await _awaitCondition(() => fakeRoom.createMessageCalls == 1);

        final paint = RealtimeRoomMessagePaint(
          id: 'msg-created',
          beaconId: kRoomCubitFakeBeaconId,
          authorId: kRoomCubitFakeMyUserId,
          body: 'reply body',
          createdAt: _kBaseTime.add(const Duration(minutes: 1)),
          replyToMessageId: target.id,
          replyToAuthorId: 'anna-server',
          replyToAuthorTitle: 'Anna K.',
          replyToBodyExcerpt: 'server-resolved excerpt',
          replyToHasAttachments: true,
        );
        fakeRoom.emitInvalidation(
          BeaconRoomEntityType.roomMessage,
          operation: RealtimeOperation.insert,
          messageId: paint.id,
          paint: paint,
        );
        await _awaitCondition(
          () => cubit.state.messages.any((m) => m.id.startsWith('local:')),
        );

        final pending = cubit.state.messages
            .where((m) => m.authorId == kRoomCubitFakeMyUserId)
            .toList();
        expect(pending, hasLength(1));
        expect(pending.single.id, startsWith('local:'));
        expect(
          cubit.state.messages.where((m) => m.id == paint.id),
          isEmpty,
          reason: 'own insert paint must defer until its mutation resolves',
        );

        gate.complete();
        expect(await send, isTrue);

        final reconciled = cubit.state.messages
            .where((m) => m.authorId == kRoomCubitFakeMyUserId)
            .toList();
        expect(reconciled, hasLength(1));
        expect(reconciled.single.id, paint.id);
        expect(
          cubit.state.messages.where((m) => m.id.startsWith('local:')),
          isEmpty,
        );
        expect(reconciled.single.replyToMessageId, target.id);
        expect(reconciled.single.replyToAuthorId, 'anna-server');
        expect(reconciled.single.replyToAuthorTitle, 'Anna K.');
        expect(reconciled.single.replyToBodyExcerpt, 'server-resolved excerpt');
        expect(reconciled.single.replyToHasAttachments, isTrue);
      },
    );
  });

  group('RoomCubit.jumpToRepliedMessage', () {
    test('loaded id scrolls in-window and returns true', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final loaded = _roomMsg(id: 'loaded', createdAt: _kBaseTime);
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [loaded];
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);

      expect(await cubit.jumpToRepliedMessage('loaded'), isTrue);
      expect(cubit.state.scrollToMessageId, 'loaded');
      expect(cubit.state.pinnedJumpMessageIds, isEmpty);
    });

    test('off-window id fetches, pins, scrolls, and returns true', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final visible = _roomMsg(
        id: 'visible',
        createdAt: _kBaseTime.add(const Duration(minutes: 5)),
      );
      final offWindow = _roomMsg(
        id: 'off-window',
        createdAt: _kBaseTime,
        body: 'historical target',
      );
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [visible];
      fakeRoom.fetchMessageTargetsById['off-window'] = offWindow;
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);

      expect(await cubit.jumpToRepliedMessage('off-window'), isTrue);
      expect(cubit.state.scrollToMessageId, 'off-window');
      expect(cubit.state.pinnedJumpMessageIds, ['off-window']);
      expect(
        cubit.state.messages.any((message) => message.id == 'off-window'),
        isTrue,
      );
    });

    test('throwing fetch shows unavailable message and returns false', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final effects = FakeUiEffectPort();
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId)
        ..fetchMessageTargetError = StateError('not found');
      final cubit = roomCubitForTest(fakeRoom, effects: effects);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);

      expect(await cubit.jumpToRepliedMessage('missing'), isFalse);
      expect(cubit.state.scrollToMessageId, isNull);
      final showMessages = effects.emitted.whereType<ShowMessage>().toList();
      expect(showMessages, hasLength(1));
      expect(
        showMessages.single.message,
        isA<RoomReplyTargetUnavailableMessage>(),
      );
    });

    test('null fetch shows unavailable message and returns false', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final effects = FakeUiEffectPort();
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId);
      final cubit = roomCubitForTest(fakeRoom, effects: effects);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);

      expect(await cubit.jumpToRepliedMessage('missing'), isFalse);
      expect(cubit.state.scrollToMessageId, isNull);
      final showMessages = effects.emitted.whereType<ShowMessage>().toList();
      expect(showMessages, hasLength(1));
      expect(
        showMessages.single.message,
        isA<RoomReplyTargetUnavailableMessage>(),
      );
    });

    test('pinned off-window target survives messages-only refresh', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final visible = _roomMsg(
        id: 'visible',
        createdAt: _kBaseTime.add(const Duration(minutes: 5)),
      );
      final offWindow = _roomMsg(
        id: 'off-window',
        createdAt: _kBaseTime,
        body: 'pinned historical',
      );
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [visible];
      fakeRoom.fetchMessageTargetsById['off-window'] = offWindow;
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      expect(await cubit.jumpToRepliedMessage('off-window'), isTrue);

      fakeRoom.messages = [visible];
      fakeRoom.emitInvalidation(BeaconRoomEntityType.roomMessage);
      await _awaitFetchCount(fakeRoom, 2);

      expect(
        cubit.state.messages.any((message) => message.id == 'off-window'),
        isTrue,
      );
      expect(cubit.state.pinnedJumpMessageIds, contains('off-window'));
    });

    test('pinned off-window target survives full catch-up refresh', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);
      final visible = _roomMsg(
        id: 'visible',
        createdAt: _kBaseTime.add(const Duration(minutes: 5)),
      );
      final offWindow = _roomMsg(
        id: 'off-window',
        createdAt: _kBaseTime,
        body: 'pinned historical',
      );
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [visible];
      fakeRoom.fetchMessageTargetsById['off-window'] = offWindow;
      final cubit = roomCubitForTest(
        fakeRoom,
        realtimeSyncCase: realtime.case_,
      );
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      expect(await cubit.jumpToRepliedMessage('off-window'), isTrue);

      fakeRoom.messages = [visible];
      realtime.port.emitCatchUp(connectionEpoch: 2);
      await _awaitFetchCount(fakeRoom, 2);

      expect(
        cubit.state.messages.any((message) => message.id == 'off-window'),
        isTrue,
      );
      expect(cubit.state.pinnedJumpMessageIds, contains('off-window'));
    });

    test('refreshed server row replaces stale pin content', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final visible = _roomMsg(
        id: 'visible',
        createdAt: _kBaseTime.add(const Duration(minutes: 5)),
      );
      final pinned = _roomMsg(
        id: 'pin-me',
        createdAt: _kBaseTime,
        body: 'stale pin body',
      );
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [visible];
      fakeRoom.fetchMessageTargetsById['pin-me'] = pinned;
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      expect(await cubit.jumpToRepliedMessage('pin-me'), isTrue);

      final edited = pinned.copyWith(body: 'fresh server body');
      fakeRoom.messages = [visible, edited];
      fakeRoom.emitInvalidation(BeaconRoomEntityType.roomMessage);
      await _awaitFetchCount(fakeRoom, 2);

      final merged = cubit.state.messages.firstWhere((m) => m.id == 'pin-me');
      expect(merged.body, 'fresh server body');
    });

    test('LRU evicts oldest pin after 21 off-window jumps', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconRoomRepository(userId: kRoomCubitFakeMyUserId);
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);

      for (var i = 0; i < 21; i++) {
        final id = 'pin-$i';
        fakeRoom.fetchMessageTargetsById[id] = _roomMsg(
          id: id,
          createdAt: _kBaseTime.add(Duration(minutes: i)),
        );
        expect(await cubit.jumpToRepliedMessage(id), isTrue);
      }

      expect(cubit.state.pinnedJumpMessageIds, hasLength(20));
      expect(cubit.state.pinnedJumpMessageIds, isNot(contains('pin-0')));
      expect(cubit.state.pinnedJumpMessageIds, contains('pin-20'));
    });

    test(
      'pinned historical row does not pollute unread state when anchor is null',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconRoomRepository(userId: '')
          ..messages = [
            _roomMsg(
              id: 'm1',
              createdAt: _kBaseTime,
              authorId: 'peer-1',
            ),
            _roomMsg(
              id: 'm2',
              createdAt: _kBaseTime.add(const Duration(minutes: 1)),
              authorId: 'peer-2',
            ),
          ];
        final offWindow = _roomMsg(
          id: 'historical',
          createdAt: _kBaseTime.subtract(const Duration(hours: 1)),
          authorId: 'peer-old',
        );
        fakeRoom.fetchMessageTargetsById['historical'] = offWindow;
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);

        await awaitRoomCubitLoad(cubit);
        expect(cubit.state.unreadAnchorAt, isNull);
        expect(cubit.state.firstUnreadMessageId, 'm1');
        expect(cubit.state.firstUnreadIndex, 0);

        final beforeUnreadCount = cubit.state.unreadCount;
        final beforeFirstUnreadId = cubit.state.firstUnreadMessageId;
        final beforeFirstUnreadIndex = cubit.state.firstUnreadIndex;

        expect(await cubit.jumpToRepliedMessage('historical'), isTrue);

        expect(cubit.state.unreadCount, beforeUnreadCount);
        expect(cubit.state.firstUnreadMessageId, beforeFirstUnreadId);
        expect(cubit.state.firstUnreadIndex, beforeFirstUnreadIndex);
        expect(cubit.state.firstUnreadIndex, 0);
        expect(cubit.state.pinnedJumpMessageIds, contains('historical'));
        expect(cubit.state.messages.first.id, 'historical');
      },
    );
  });
}
