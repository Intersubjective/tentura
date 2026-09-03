import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_room_message_paint.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';

import '../../support/test_realtime_sync.dart';
import 'room_cubit_fakes.dart';

final _kBaseTime = DateTime.utc(2026, 1, 1, 12);

RoomMessage _msg(
  String id, {
  String authorId = 'peer-a',
  String body = 'hello from A',
  DateTime? createdAt,
}) => RoomMessage(
  id: id,
  beaconId: kRoomCubitFakeBeaconId,
  authorId: authorId,
  body: body,
  createdAt: createdAt ?? _kBaseTime,
  author: Profile(id: authorId, displayName: 'Author $authorId'),
);

RealtimeRoomMessagePaint _paint(
  String id, {
  String authorId = 'peer-a',
  String body = 'hello from A',
  String? threadItemId,
}) => RealtimeRoomMessagePaint(
  id: id,
  beaconId: kRoomCubitFakeBeaconId,
  authorId: authorId,
  body: body,
  createdAt: _kBaseTime,
  threadItemId: threadItemId,
);

Future<void> _pump() => Future<void>.delayed(Duration.zero);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  group('RoomCubit peer paint vs stale refresh', () {
    test(
      'painted remote insert survives an in-flight snapshot that omits it',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final existing = _msg(
          'm0',
          body: 'already here',
          createdAt: _kBaseTime.subtract(const Duration(minutes: 1)),
        );
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..messages = [existing];
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        final gate = Completer<void>();
        fakeRoom.fetchMessagesCompleter = gate;
        fakeRoom.emitInvalidation(BeaconRoomEntityType.roomReaction);
        await _pump();
        expect(fakeRoom.fetchMessagesCallCount, greaterThan(1));

        final paint = _paint('m-paint');
        fakeRoom.emitInvalidation(
          BeaconRoomEntityType.roomMessage,
          operation: RealtimeOperation.insert,
          messageId: paint.id,
          paint: paint,
        );
        await _pump();
        expect(
          cubit.state.messages.any((m) => m.id == paint.id),
          isTrue,
          reason: 'peer should see the painted insert immediately',
        );

        gate.complete();
        await _settle();

        expect(
          cubit.state.messages.any((m) => m.id == paint.id),
          isTrue,
          reason:
              'painted remote message must not be wiped by a stale snapshot',
        );
      },
    );

    test(
      'full snapshot retains paint that arrives after messages resolve',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final existing = _msg('m0', body: 'seed');
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..messages = [existing];
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        final messagesGate = Completer<void>();
        final participantsGate = Completer<void>();
        fakeRoom
          ..fetchMessagesCompleter = messagesGate
          ..fetchParticipantsCompleter = participantsGate;
        fakeRoom.emitInvalidation(BeaconRoomEntityType.participant);
        await _pump();
        expect(fakeRoom.fetchMessagesCallCount, greaterThan(1));

        messagesGate.complete();
        await _pump();

        final paint = _paint('m-full-gap');
        fakeRoom.emitInvalidation(
          BeaconRoomEntityType.roomMessage,
          operation: RealtimeOperation.insert,
          messageId: paint.id,
          paint: paint,
        );
        await _pump();
        expect(cubit.state.messages.any((m) => m.id == paint.id), isTrue);

        participantsGate.complete();
        await _settle();

        expect(
          cubit.state.messages.any((m) => m.id == paint.id),
          isTrue,
          reason: 'paint during full-snapshot tail must survive terminal emit',
        );
      },
    );

    test(
      'later snapshot hydrates painted id with server fields',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final existing = _msg('m0', body: 'seed');
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..messages = [existing];
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        final gate = Completer<void>();
        fakeRoom.fetchMessagesCompleter = gate;
        fakeRoom.emitInvalidation(BeaconRoomEntityType.roomReaction);
        await _pump();

        final paint = _paint('m-hydrate', body: 'paint body');
        fakeRoom.emitInvalidation(
          BeaconRoomEntityType.roomMessage,
          operation: RealtimeOperation.insert,
          messageId: paint.id,
          paint: paint,
        );
        await _pump();
        gate.complete();
        await _settle();

        fakeRoom.messages = [
          existing,
          _msg('m-hydrate', body: 'server body'),
        ];
        fakeRoom.emitInvalidation(BeaconRoomEntityType.roomReaction);
        await _settle();

        final hydrated = cubit.state.messages.where((m) => m.id == 'm-hydrate');
        expect(hydrated, hasLength(1));
        expect(hydrated.single.body, 'server body');
      },
    );

    test(
      'post-paint snapshot that omits the id drops the message',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final existing = _msg('m0', body: 'seed');
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..messages = [existing];
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        final paint = _paint('m-omit');
        fakeRoom.emitInvalidation(
          BeaconRoomEntityType.roomMessage,
          operation: RealtimeOperation.insert,
          messageId: paint.id,
          paint: paint,
        );
        await _pump();
        expect(cubit.state.messages.any((m) => m.id == paint.id), isTrue);

        // Idle paint has no overlay; a later refresh is authoritative.
        fakeRoom.messages = [existing];
        fakeRoom.emitInvalidation(BeaconRoomEntityType.roomReaction);
        await _settle();

        expect(
          cubit.state.messages.any((m) => m.id == paint.id),
          isFalse,
          reason: 'must not fight the latest-50 / delete window forever',
        );
      },
    );

    test(
      'peer delete during stale refresh does not resurrect',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final existing = _msg('m0', body: 'seed');
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..messages = [existing];
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        final gate = Completer<void>();
        fakeRoom.fetchMessagesCompleter = gate;
        fakeRoom.emitInvalidation(BeaconRoomEntityType.roomReaction);
        await _pump();

        final paint = _paint('m-del');
        fakeRoom.emitInvalidation(
          BeaconRoomEntityType.roomMessage,
          operation: RealtimeOperation.insert,
          messageId: paint.id,
          paint: paint,
        );
        await _pump();
        expect(cubit.state.messages.any((m) => m.id == paint.id), isTrue);

        // Authoritative store no longer has the row; the in-flight fetch
        // already captured the pre-paint list at gate entry.
        fakeRoom.messages = [existing];
        fakeRoom.emitInvalidation(
          BeaconRoomEntityType.roomMessage,
          operation: RealtimeOperation.delete,
          messageId: paint.id,
        );
        await _pump();
        expect(cubit.state.messages.any((m) => m.id == paint.id), isFalse);

        gate.complete();
        await _settle();

        expect(
          cubit.state.messages.any((m) => m.id == paint.id),
          isFalse,
          reason: 'delete tombstone must beat stale carried paint',
        );
      },
    );

    test(
      'local delete stays hidden while a stale fetch completes',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final victim = _msg('m-local-del');
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..messages = [victim];
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        final fetchGate = Completer<void>();
        final deleteGate = Completer<void>();
        fakeRoom
          ..fetchMessagesCompleter = fetchGate
          ..deleteMessageGate = deleteGate;
        fakeRoom.emitInvalidation(BeaconRoomEntityType.roomReaction);
        await _pump();

        final deleteFuture = cubit.deleteMessage(messageId: victim.id);
        await _pump();
        expect(cubit.state.messages.any((m) => m.id == victim.id), isFalse);

        fetchGate.complete();
        await _settle();
        expect(
          cubit.state.messages.any((m) => m.id == victim.id),
          isFalse,
          reason: 'pending local delete must filter stale resurrect',
        );

        deleteGate.complete();
        await deleteFuture;
        expect(cubit.state.messages.any((m) => m.id == victim.id), isFalse);
      },
    );

    test(
      'local delete failure restores the message',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final victim = _msg('m-local-fail');
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..messages = [victim]
          ..deleteMessageError = StateError('nope');
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        await cubit.deleteMessage(messageId: victim.id);
        expect(cubit.state.messages.any((m) => m.id == victim.id), isTrue);
      },
    );

    test(
      'own send server id survives a refresh that began before commit',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final existing = _msg('m0', body: 'seed');
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..messages = [existing];
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        final fetchGate = Completer<void>();
        final createGate = Completer<void>();
        fakeRoom
          ..fetchMessagesCompleter = fetchGate
          ..createMessageGate = createGate;
        fakeRoom.emitInvalidation(BeaconRoomEntityType.roomReaction);
        await _pump();

        final sendFuture = cubit.sendMessage(body: 'from me');
        await _pump();
        expect(
          cubit.state.messages.any((m) => m.id.startsWith('local:')),
          isTrue,
        );

        createGate.complete();
        expect(await sendFuture, isTrue);
        expect(
          cubit.state.messages.any((m) => m.id == 'msg-created'),
          isTrue,
        );

        // Stale snapshot still lacks the server id.
        fetchGate.complete();
        await _settle();

        expect(
          cubit.state.messages.any((m) => m.id == 'msg-created'),
          isTrue,
          reason: 'reconciled server id must ride the active overlay',
        );
      },
    );

    test(
      'paint for another threadItemId is ignored',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        );
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        final paint = _paint('m-other-thread', threadItemId: 'item-x');
        fakeRoom.emitInvalidation(
          BeaconRoomEntityType.roomMessage,
          operation: RealtimeOperation.insert,
          messageId: paint.id,
          paint: paint,
        );
        await _pump();

        expect(cubit.state.messages.any((m) => m.id == paint.id), isFalse);
      },
    );

    test(
      'insert without paint schedules a messages refresh',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        );
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);
        final afterLoad = fakeRoom.fetchMessagesCallCount;

        fakeRoom.emitInvalidation(
          BeaconRoomEntityType.roomMessage,
          operation: RealtimeOperation.insert,
          messageId: 'thin-1',
        );
        await _settle();

        expect(fakeRoom.fetchMessagesCallCount, greaterThan(afterLoad));
      },
    );

    test(
      'valid idle paint does not schedule an unconditional fetch',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        );
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);
        final afterLoad = fakeRoom.fetchMessagesCallCount;

        final paint = _paint('m-idle');
        fakeRoom.emitInvalidation(
          BeaconRoomEntityType.roomMessage,
          operation: RealtimeOperation.insert,
          messageId: paint.id,
          paint: paint,
        );
        await _settle();

        expect(cubit.state.messages.any((m) => m.id == paint.id), isTrue);
        expect(fakeRoom.fetchMessagesCallCount, afterLoad);
      },
    );

    test(
      'deleting a pinned off-window message removes row and pin id',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final inWindow = _msg('m-window');
        final offWindow = _msg(
          'm-pin',
          createdAt: _kBaseTime.subtract(const Duration(days: 1)),
        );
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..messages = [inWindow]
          ..fetchMessageTargetsById[offWindow.id] = offWindow;
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        expect(await cubit.jumpToRepliedMessage(offWindow.id), isTrue);
        expect(cubit.state.pinnedJumpMessageIds, contains(offWindow.id));
        expect(cubit.state.messages.any((m) => m.id == offWindow.id), isTrue);

        await cubit.deleteMessage(messageId: offWindow.id);
        expect(cubit.state.messages.any((m) => m.id == offWindow.id), isFalse);
        expect(cubit.state.pinnedJumpMessageIds, isNot(contains(offWindow.id)));
      },
    );
  });

  group('RoomCubit paint race catch-up', () {
    test('catch-up full refresh uses the same overlay protection', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);
      final existing = _msg('m0', body: 'seed');
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..messages = [existing];
      addTearDown(fakeRoom.dispose);
      final cubit = roomCubitForTest(
        fakeRoom,
        realtimeSyncCase: realtime.case_,
      );
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      final messagesGate = Completer<void>();
      final participantsGate = Completer<void>();
      fakeRoom
        ..fetchMessagesCompleter = messagesGate
        ..fetchParticipantsCompleter = participantsGate;
      realtime.port.emitCatchUp(connectionEpoch: 2);
      await _pump();

      messagesGate.complete();
      await _pump();
      final paint = _paint('m-catchup');
      fakeRoom.emitInvalidation(
        BeaconRoomEntityType.roomMessage,
        operation: RealtimeOperation.insert,
        messageId: paint.id,
        paint: paint,
      );
      await _pump();
      participantsGate.complete();
      await _settle();

      expect(cubit.state.messages.any((m) => m.id == paint.id), isTrue);
    });
  });
}
