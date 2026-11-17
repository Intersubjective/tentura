// RoomCubit.batonRespond optimistic card state, before the server replies:
// Can't help and solo Can help drop a previously named partner; «together»
// shows the partner's real name (from the room's people), never an empty one;
// a failed call restores the previous card and shows an error.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

const _batonId = 'baton-1';
const _partnerId = 'u-bob';

const _withPendingPartner = RoomBatonCandidateData(
  id: _batonId,
  status: RoomBatonStatus.collecting,
  myResponse: RoomBatonResponse.canHelp,
  myPartner: RoomBatonMyPartner(id: _partnerId, title: 'Bob', status: 'pending'),
);

const _waiting = RoomBatonCandidateData(
  id: _batonId,
  status: RoomBatonStatus.collecting,
  myResponse: RoomBatonResponse.waiting,
);

class _GatedRepo extends FakeBeaconThreadsRepository {
  _GatedRepo({required super.userId});

  Completer<void>? gate;
  Exception? error;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #batonRespond) return _respond();
    return super.noSuchMethod(invocation);
  }

  Future<RoomBatonData?> _respond() async {
    await gate?.future;
    final failure = error;
    if (failure != null) throw failure;
    return null;
  }
}

BeaconParticipant _person(String id, String title) => BeaconParticipant(
  id: 'p-$id',
  beaconId: kRoomCubitFakeBeaconId,
  userId: id,
  role: 0,
  status: 0,
  roomAccess: RoomAccessBits.admitted,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  userTitle: title,
);

void main() {
  group('RoomCubit.batonRespond optimistic state', () {
    late _GatedRepo repo;
    late FakeUiEffectPort effects;
    late RoomCubit cubit;

    Future<void> openRoom(RoomBatonCandidateData baton) async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      repo = _GatedRepo(userId: kRoomCubitFakeMyUserId)
        ..participants = [
          _person(kRoomCubitFakeMyUserId, 'Me'),
          _person(_partnerId, 'Bob'),
        ]
        ..messages = [
          RoomMessage(
            id: 'msg-1',
            beaconId: kRoomCubitFakeBeaconId,
            authorId: 'u-anna',
            body: 'Who can drive?',
            createdAt: DateTime.utc(2026, 10, 3),
            baton: baton,
          ),
        ]
        ..gate = Completer<void>();
      effects = FakeUiEffectPort();
      cubit = roomCubitForTest(repo, effects: effects);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      if (!cubit.state.participantsLoaded) {
        await cubit.stream.firstWhere((s) => s.participantsLoaded);
      }
    }

    RoomBatonCandidateData shown() =>
        cubit.state.messages.firstWhere((m) => m.id == 'msg-1').baton!
            as RoomBatonCandidateData;

    test("Can't help clears a pending partner before the server replies", () async {
      await openRoom(_withPendingPartner);

      final call = cubit.batonRespond(
        messageId: 'msg-1',
        batonId: _batonId,
        canHelp: false,
      );

      expect(shown().myResponse, RoomBatonResponse.cantHelp);
      expect(shown().myPartner, isNull);
      repo.gate!.complete();
      await call;
    });

    test('solo Can help clears a pending partner before the server replies', () async {
      await openRoom(_withPendingPartner);

      final call = cubit.batonRespond(
        messageId: 'msg-1',
        batonId: _batonId,
        canHelp: true,
      );

      expect(shown().myResponse, RoomBatonResponse.canHelp);
      expect(shown().myPartner, isNull);
      repo.gate!.complete();
      await call;
    });

    test('together names the partner from the room people, not empty', () async {
      await openRoom(_waiting);

      final call = cubit.batonRespond(
        messageId: 'msg-1',
        batonId: _batonId,
        canHelp: true,
        partnerUserId: _partnerId,
      );

      expect(shown().myResponse, RoomBatonResponse.canHelp);
      expect(shown().myPartner?.id, _partnerId);
      expect(shown().myPartner?.title, 'Bob');
      expect(shown().myPartner?.status, 'pending');
      repo.gate!.complete();
      await call;
    });

    test("a failed Can't help restores the earlier partner and shows an error",
        () async {
      await openRoom(_withPendingPartner);
      repo.error = Exception('boom');
      repo.gate!.complete();

      await cubit.batonRespond(
        messageId: 'msg-1',
        batonId: _batonId,
        canHelp: false,
      );
      await pumpEventQueue();

      expect(shown().myResponse, RoomBatonResponse.canHelp);
      expect(shown().myPartner?.id, _partnerId);
      expect(shown().myPartner?.title, 'Bob');
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
    });

    test('a failed together answer restores the previous card and shows an '
        'error', () async {
      await openRoom(_waiting);
      repo.error = Exception('boom');
      repo.gate!.complete();

      await cubit.batonRespond(
        messageId: 'msg-1',
        batonId: _batonId,
        canHelp: true,
        partnerUserId: _partnerId,
      );
      await pumpEventQueue();

      expect(shown().myResponse, RoomBatonResponse.waiting);
      expect(shown().myPartner, isNull);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
    });
  });
}
