import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_room/fake_coordination_item_case.dart';
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
    test('initial load retries transient fetch and emits ask counts', () async {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon();
      final case_ = buildTestBeaconViewCase(beaconRepo: beaconRepo);
      final coordination = TrackingCoordinationItemCase(
        responsibility: CoordinationResponsibility(
          beaconId: beaconId,
          askOpen: 1,
          askNew: 1,
        ),
        failFetchCount: 1,
      );
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: case_,
        coordinationItemCase: coordination,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

      expect(coordination.fetchResponsibilityCalls, 2);
      expect(cubit.state.youResponsibility?.askOpen, 1);
      expect(cubit.state.youResponsibility?.askNew, 0);
      expect(coordination.markItemsSeenCalls, 1);
    });

    test('refreshBeaconRoomCue refreshes YOU even without invalidation', () async {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon();
      final case_ = buildTestBeaconViewCase(beaconRepo: beaconRepo);
      final coordination = TrackingCoordinationItemCase(
        responsibility: CoordinationResponsibility(beaconId: beaconId),
      );
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: case_,
        coordinationItemCase: coordination,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

      coordination.responsibility = CoordinationResponsibility(
        beaconId: beaconId,
        askOpen: 1,
      );
      coordination.fetchResponsibilityCalls = 0;
      coordination.markItemsSeenCalls = 0;

      await cubit.refreshBeaconRoomCue(savedCurrentLine: 'Updated NOW');

      expect(coordination.fetchResponsibilityCalls, greaterThanOrEqualTo(1));
      expect(cubit.state.youResponsibility?.askOpen, 1);
      expect(
        cubit.state.beaconRoomCue?.currentLine,
        'Updated NOW',
      );
    });
  });
}

class TrackingCoordinationItemCase extends FakeCoordinationItemCaseForRoom {
  TrackingCoordinationItemCase({
    required this.responsibility,
    this.failFetchCount = 0,
  });

  CoordinationResponsibility responsibility;
  final int failFetchCount;
  int fetchResponsibilityCalls = 0;
  int markItemsSeenCalls = 0;

  @override
  Future<CoordinationResponsibility> fetchResponsibility(
    String beaconId,
  ) async {
    fetchResponsibilityCalls++;
    if (fetchResponsibilityCalls <= failFetchCount) {
      throw StateError('transient responsibility fetch');
    }
    return responsibility;
  }

  @override
  Future<void> markItemsSeen(String beaconId) async {
    markItemsSeenCalls++;
    if (markItemsSeenException != null) throw markItemsSeenException!;
  }
}
