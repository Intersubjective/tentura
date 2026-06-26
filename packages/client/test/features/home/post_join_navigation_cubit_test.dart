import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/home/domain/entity/post_join_destination.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';

void main() {
  group('PostJoinNavigationCubit', () {
    late PostJoinNavigationCubit cubit;

    setUp(() => cubit = PostJoinNavigationCubit());

    test('setFromBeaconInvite exposes hasPending until consumed', () {
      cubit.setFromBeaconInvite(
        beaconId: 'B1',
        beaconTitle: 'Help',
        inviterName: 'Alice',
      );
      expect(cubit.hasPending, isTrue);
      final dest = cubit.takeDestination();
      expect(dest?.beaconId, 'B1');
      expect(dest?.showSnackbar, isTrue);
      expect(cubit.hasPending, isFalse);
    });

    test('set preserves showSnackbar flag', () {
      cubit.set(
        const PostJoinDestination(
          beaconId: 'B1',
          beaconTitle: 'T',
          showSnackbar: false,
        ),
      );
      expect(cubit.takeDestination()?.showSnackbar, isFalse);
    });
  });
}
