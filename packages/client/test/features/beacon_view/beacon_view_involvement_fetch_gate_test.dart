import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

class _CountingCoordinationRepository
    extends FakeBeaconViewCoordinationRepository {
  int fetchCalls = 0;

  @override
  Future<List<FakeHelpOfferCoordinationRow>> fetchHelpOffersWithCoordination({
    required String beaconId,
  }) {
    fetchCalls++;
    return super.fetchHelpOffersWithCoordination(beaconId: beaconId);
  }
}

class _CountingActivityEventRepository
    extends FakeBeaconViewActivityEventRepository {
  int listCalls = 0;

  @override
  Future<List<BeaconActivityEvent>> list({required String beaconId}) {
    listCalls++;
    return super.list(beaconId: beaconId);
  }
}

void main() {
  const myProfile = Profile(id: 'Uviewer', displayName: 'Viewer');
  const beaconId = 'Bobserver01';

  Beacon beaconFor({required bool canReadInvolvement}) => Beacon(
    id: beaconId,
    title: 'Observed request',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: BeaconStatus.open,
    canReadContent: true,
    canReadInvolvement: canReadInvolvement,
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );

  Future<
    ({
      _CountingCoordinationRepository coordination,
      _CountingActivityEventRepository activity,
      FakeBeaconViewRoomRepository room,
      FakeBeaconViewFactCardRepository factCards,
      BeaconViewCubit cubit,
    })
  >
  load({required bool canReadInvolvement}) async {
    final coordination = _CountingCoordinationRepository();
    final activity = _CountingActivityEventRepository();
    final room = FakeBeaconViewRoomRepository();
    final factCards = FakeBeaconViewFactCardRepository();
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (_) async =>
          beaconFor(canReadInvolvement: canReadInvolvement);
    final cubit = BeaconViewCubit(
      id: beaconId,
      myProfile: myProfile,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: coordination,
        activityEventsRepo: activity,
        roomRepo: room,
        factCardsRepo: factCards,
      ),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
    return (
      coordination: coordination,
      activity: activity,
      room: room,
      factCards: factCards,
      cubit: cubit,
    );
  }

  group('BeaconViewCubit involvement fetch gate', () {
    test('observer without involvement access skips involvement fetches', () async {
      final r = await load(canReadInvolvement: false);

      expect(r.cubit.state.beaconContentLoaded, isTrue);
      expect(r.cubit.state.beaconUnavailable, isFalse);
      expect(r.cubit.state.beacon.title, 'Observed request');
      expect(r.factCards.listCalls, greaterThan(0));
      expect(r.coordination.fetchCalls, 0);
      expect(r.room.fetchBeaconRoomStateCalls, 0);
      expect(r.activity.listCalls, 0);
    });

    test('involved viewer still fetches involvement data', () async {
      final r = await load(canReadInvolvement: true);

      expect(r.coordination.fetchCalls, greaterThan(0));
      expect(r.room.fetchBeaconRoomStateCalls, greaterThan(0));
      expect(r.activity.listCalls, greaterThan(0));
    });
  });
}

Future<void> pumpUntil(
  Stream<BeaconViewState> stream,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (condition()) return;
  await stream.timeout(timeout).firstWhere((_) => condition());
}
