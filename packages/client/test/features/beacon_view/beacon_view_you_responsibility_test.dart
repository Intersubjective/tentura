import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

void main() {
  const myProfile = Profile(id: 'Uhelper', displayName: 'Helper');
  const beaconId = 'Bask01';

  Beacon readableBeacon() => Beacon(
    id: beaconId,
    title: 'Coordination beacon',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: BeaconStatus.open,
    canReadContent: true,
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );

  group('BeaconViewCubit YOU responsibility', () {
    test(
      'initial load no longer fetches retired item responsibility',
      () async {
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => readableBeacon();
        final case_ = buildTestBeaconViewCase(beaconRepo: beaconRepo);
        final cubit = BeaconViewCubit(
          id: beaconId,
          myProfile: myProfile,
          beaconViewCase: case_,
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);

        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

        expect(cubit.state.youResponsibility, isNull);
      },
    );

    test('refreshBeaconRoomCue updates NOW without YOU fetch', () async {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon();
      final roomRepo = FakeBeaconViewRoomRepository(
        roomState: BeaconRoomState(
          beaconId: beaconId,
          updatedAt: DateTime.utc(2026, 9, 15),
          currentLine: 'Updated NOW',
        ),
      );
      final case_ = buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        roomRepo: roomRepo,
      );
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: case_,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

      await cubit.refreshBeaconRoomCue(savedCurrentLine: 'Updated NOW');

      expect(cubit.state.youResponsibility, isNull);
      expect(
        cubit.state.beaconRoomCue?.currentLine,
        'Updated NOW',
      );
    });
  });
}
