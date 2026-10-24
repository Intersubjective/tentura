// #481: a fact pinned outside the room (the host's Add-fact form opened by
// "Pin your first fact") reaches the room's fact cards through
// RoomCubit.refreshFactCards, with no realtime echo of the viewer's own pin
// (the server can be run with actor echo off).

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

class _FactCardRepository extends FakeBeaconFactCardRepository {
  List<BeaconFactCard> cards = [];

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async =>
      List<BeaconFactCard>.of(cards);
}

BeaconFactCard _doorCode() => BeaconFactCard(
  id: 'fact-door',
  beaconId: kRoomCubitFakeBeaconId,
  factText: 'Door code 4711',
  visibility: 0,
  pinnedBy: kRoomCubitFakeMyUserId,
  createdAt: DateTime.utc(2026, 10, 24),
  status: 0,
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  test('a fact pinned by the host shows in the room after '
      'refreshFactCards, without a realtime invalidation', () async {
    registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
    final fakeRoom = FakeBeaconThreadsRepository(
      userId: kRoomCubitFakeMyUserId,
    );
    addTearDown(fakeRoom.dispose);
    final factRepo = _FactCardRepository();
    final cubit = roomCubitForTest(
      fakeRoom,
      effects: FakeUiEffectPort(),
      beaconRoomCase: BeaconThreadsCase(
        fakeRoom,
        factRepo,
        FakePollingRepository(),
        FakeBeaconRoomHintsRepository(),
        RoomReadWatermarkStore.testing(),
        buildTestRealtimeSync().case_,
        env: const Env(),
        logger: Logger('test'),
      ),
    );
    addTearDown(cubit.close);
    await awaitRoomCubitLoad(cubit);
    await _settle();
    expect(cubit.state.factCards, isEmpty);

    // The host's form pinned it; no factCard invalidation arrives.
    factRepo.cards = [_doorCode()];
    await cubit.refreshFactCards();
    await _settle();

    expect(
      cubit.state.factCards.map((f) => f.factText),
      ['Door code 4711'],
    );
  });
}
