import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';

import 'room_cubit_fakes.dart';

final _kBaseTime = DateTime.utc(2026, 1, 1, 12);

BeaconFactCard _factCard({
  String id = 'fact-1',
  int revisionSeq = 3,
  String factText = 'bring the ladder',
  String pinnedBy = 'anna',
}) => BeaconFactCard(
  id: id,
  beaconId: kRoomCubitFakeBeaconId,
  factText: factText,
  visibility: 0,
  pinnedBy: pinnedBy,
  createdAt: _kBaseTime,
  status: 0,
  revisionSeq: revisionSeq,
);

void main() {
  group('RoomCubit pendingQuotedFact', () {
    test('setting from a card with revisionSeq 3 stores seq 3', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      expect(cubit.state.pendingQuotedFact, isNull);

      final card = _factCard(id: 'fact-3', revisionSeq: 3);
      cubit.setPendingQuotedFact(card);

      expect(cubit.state.pendingQuotedFact, isNotNull);
      expect(cubit.state.pendingQuotedFact!.factCardId, 'fact-3');
      expect(cubit.state.pendingQuotedFact!.seq, 3);
    });

    test('send passes quotedFactCardId and quotedFactRevisionSeq', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);

      final card = _factCard(id: 'fact-3', revisionSeq: 3);
      cubit.setPendingQuotedFact(card);

      expect(await cubit.sendMessage(body: 'see attached fact'), isTrue);
      expect(fakeRoom.lastQuotedFactCardId, 'fact-3');
      expect(fakeRoom.lastQuotedFactRevisionSeq, 3);
    });

    test('successful send clears the pending quote', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);

      cubit.setPendingQuotedFact(_factCard());
      expect(await cubit.sendMessage(body: 'done'), isTrue);

      expect(cubit.state.pendingQuotedFact, isNull);
    });

    test('a failed send keeps the pending quote', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..createMessageError = StateError('network');
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);

      final card = _factCard(id: 'fact-3', revisionSeq: 3);
      cubit.setPendingQuotedFact(card);

      expect(await cubit.sendMessage(body: 'retry me'), isFalse);

      expect(cubit.state.pendingQuotedFact, isNotNull);
      expect(cubit.state.pendingQuotedFact!.factCardId, 'fact-3');
    });

    test(
      'send with empty text and a pending quote is allowed (quote-only send)',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        );
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);

        await awaitRoomCubitLoad(cubit);

        cubit.setPendingQuotedFact(_factCard(id: 'fact-3', revisionSeq: 3));

        expect(await cubit.sendMessage(body: ''), isTrue);
        expect(fakeRoom.createMessageCalls, 1);
        expect(fakeRoom.lastQuotedFactCardId, 'fact-3');
        expect(fakeRoom.lastQuotedFactRevisionSeq, 3);
      },
    );

    test('clearPendingQuotedFact nulls the pending quote', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);

      cubit.setPendingQuotedFact(_factCard());
      expect(cubit.state.pendingQuotedFact, isNotNull);

      cubit.clearPendingQuotedFact();
      expect(cubit.state.pendingQuotedFact, isNull);
    });
  });
}
