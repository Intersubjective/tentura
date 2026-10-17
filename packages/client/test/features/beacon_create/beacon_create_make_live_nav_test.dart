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
  int pushCount = 0;
  PageRouteInfo? lastPush;
  final calls = <String>[];

  @override
  void pop<T extends Object?>([T? result]) => calls.add('pop');

  @override
  void markUrlStateForReplace() => calls.add('markUrlStateForReplace');

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushCount++;
    calls.add('push');
    lastPush = route;
    return null;
  }
}

void main() {
  test(
    'after makeLive, popCreateAndOpenLiveBeacon opens the view in place',
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

      // #353: the URL is marked for replace after the pop, so the view's
      // browser entry takes the composer's place.
      expect(router.calls, ['pop', 'markUrlStateForReplace', 'push']);
      expect(router.pushCount, 1);
      expect(router.lastPush, isA<BeaconViewRoute>());
      final route = router.lastPush! as BeaconViewRoute;
      expect(route.args!.id, 'B1');
    },
  );
}
