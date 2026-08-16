import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';

void main() {
  group('HomeTabReselectCubit', () {
    test('requestInboxWatching increments count and stores beacon id', () {
      final cubit = HomeTabReselectCubit();
      addTearDown(cubit.close);

      expect(cubit.state.inboxWatchingOpenCount, 0);
      expect(cubit.state.inboxWatchingBeaconId, isNull);

      cubit.requestInboxWatching('B-watch');
      expect(cubit.state.inboxWatchingOpenCount, 1);
      expect(cubit.state.inboxWatchingBeaconId, 'B-watch');

      cubit.requestInboxWatching('B-other');
      expect(cubit.state.inboxWatchingOpenCount, 2);
      expect(cubit.state.inboxWatchingBeaconId, 'B-other');
    });

    test('bump inbox clears watching intent id', () {
      final cubit = HomeTabReselectCubit();
      addTearDown(cubit.close);

      cubit.requestInboxWatching('B-watch');
      cubit.bump(HomeTab.inbox);

      expect(cubit.state.inboxReselectCount, 1);
      expect(cubit.state.inboxWatchingBeaconId, isNull);
      expect(cubit.state.inboxWatchingOpenCount, 1);
    });
  });
}
