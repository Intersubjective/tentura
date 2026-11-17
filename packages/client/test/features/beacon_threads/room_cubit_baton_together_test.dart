import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/exception/baton_exceptions.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../support/baton_together_expectations.dart';
import '../../support/baton_together_projection_accessors.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

const _batonId = 'baton-1';
const _partnerUserId = 'Uxxxxxxxxxxx';

const _waiting = RoomBatonCandidateData(
  id: _batonId,
  status: RoomBatonStatus.collecting,
  myResponse: RoomBatonResponse.waiting,
);

class _PartnerRespondRepository extends FakeBeaconThreadsRepository {
  _PartnerRespondRepository({required super.userId});

  Completer<void>? gate;
  Exception? error;
  String? lastPartnerUserId;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #batonRespond) {
      lastPartnerUserId =
          invocation.namedArguments[#partnerUserId] as String?;
      final batonId = invocation.namedArguments[#batonId] as String;
      final canHelp = invocation.namedArguments[#canHelp] as bool;
      final partnerUserId =
          invocation.namedArguments[#partnerUserId] as String?;
      return _respond(
        batonId: batonId,
        canHelp: canHelp,
        partnerUserId: partnerUserId,
      );
    }
    return super.noSuchMethod(invocation);
  }

  Future<RoomBatonData?> _respond({
    required String batonId,
    required bool canHelp,
    String? partnerUserId,
  }) async {
    final held = gate;
    if (held != null) await held.future;
    final failure = error;
    if (failure != null) throw failure;
    return RoomBatonCandidateData(
      id: batonId,
      status: RoomBatonStatus.collecting,
      myResponse: canHelp
          ? RoomBatonResponse.canHelp
          : RoomBatonResponse.cantHelp,
    );
  }
}

void main() {
  group('RoomCubit.batonRespond optimistic together state', () {
    late _PartnerRespondRepository repo;
    late RoomCubit cubit;

    Future<void> openRoom() async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      repo = _PartnerRespondRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [
          RoomMessage(
            id: 'msg-1',
            beaconId: kRoomCubitFakeBeaconId,
            authorId: 'u-anna',
            body: 'Who can drive?',
            createdAt: DateTime.utc(2026, 10, 3),
            baton: _waiting,
          ),
        ];
      cubit = roomCubitForTest(repo, effects: FakeUiEffectPort());
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
    }

    RoomBatonData? shownBaton() =>
        cubit.state.messages.firstWhere((m) => m.id == 'msg-1').baton;

    test('shows pending partner on the card before the server replies', () async {
      await openRoom();
      repo.gate = Completer<void>();

      final respond = (cubit as dynamic).batonRespond(
        messageId: 'msg-1',
        batonId: _batonId,
        canHelp: true,
        partnerUserId: _partnerUserId,
      ) as Future<void>;

      expect(candidatePartnerStatus(shownBaton()), 'pending');
      expect(repo.lastPartnerUserId, _partnerUserId);
      repo.gate!.complete();
      await respond;
    });
  });

  group('RoomCubit.batonRespond partner invalid error', () {
    late _PartnerRespondRepository repo;
    late FakeUiEffectPort effects;
    late RoomCubit cubit;

    Future<void> openRoom() async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      repo = _PartnerRespondRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [
          RoomMessage(
            id: 'msg-1',
            beaconId: kRoomCubitFakeBeaconId,
            authorId: 'u-anna',
            body: 'Who can drive?',
            createdAt: DateTime.utc(2026, 10, 3),
            baton: _waiting,
          ),
        ];
      effects = FakeUiEffectPort();
      cubit = roomCubitForTest(repo, effects: effects);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
    }

    RoomBatonResponse? shownResponse() {
      final baton =
          cubit.state.messages.firstWhere((m) => m.id == 'msg-1').baton;
      return baton is RoomBatonCandidateData ? baton.myResponse : null;
    }

    test('rolls back and shows a snackbar when the server rejects the partner',
        () async {
      await openRoom();
      repo.error = const BatonPartnerInvalidException();

      await (cubit as dynamic).batonRespond(
        messageId: 'msg-1',
        batonId: _batonId,
        canHelp: true,
        partnerUserId: _partnerUserId,
      );
      await pumpEventQueue();

      expect(shownResponse(), RoomBatonResponse.waiting);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      final snackError = effects.emitted.whereType<ShowError>().single.error;
      expect(snackError, isExpectedBatonPartnerInvalidException());
    });
  });
}
