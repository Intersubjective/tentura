import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

class _HarnessRouter extends Mock implements StackRouter {
  int popAndPushCount = 0;
  PageRouteInfo? lastPopAndPush;

  @override
  Future<T?> popAndPush<T extends Object?, TO extends Object?>(
    PageRouteInfo route, {
    TO? result,
    OnNavigationFailure? onFailure,
  }) async {
    popAndPushCount++;
    lastPopAndPush = route;
    return null;
  }
}

void main() {
  test(
    'after successful makeLive, popCreateAndOpenLiveBeacon popAndPushes view',
    () async {
      final write = FakeBeaconWritePort(
        beacon: Beacon.empty.copyWith(id: 'B1', status: BeaconStatus.draft),
      );
      final cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      cubit
        ..setTitle('Need a piano moved')
        ..setDescription('Two flights of stairs, this weekend.');

      await cubit.makeLive(context: 'c');
      expect(cubit.state.isLive, isTrue);
      expect(cubit.state.draftId, 'B1');

      final router = _HarnessRouter();
      await popCreateAndOpenLiveBeacon(router, beaconId: cubit.state.draftId!);

      expect(router.popAndPushCount, 1);
      expect(router.lastPopAndPush, isA<BeaconViewRoute>());
      final route = router.lastPopAndPush! as BeaconViewRoute;
      expect(route.args!.id, 'B1');
    },
  );
}
