import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';

import '../auth/auth_test_helpers.dart';
import 'bookkeeping_refresh_test_support.dart';

void main() {
  test('recalculateForCurrentUser notifies refresh and refreshes beacons', () async {
    final repo = FakeBookkeepingRefreshRepository();
    final beaconRepo = FakeBeaconRepositoryForBookkeeping();
    final signal = BookkeepingRefreshSignal();
    final events = <void>[];
    final sub = signal.stream.listen(events.add);
    final case_ = buildTestBookkeepingRefreshCase(
      repository: repo,
      authCase: buildTestAuthCase(SignedInAuthLocal(), EmptyAuthRemote()),
      beaconRepository: beaconRepo,
      refreshSignal: signal,
    );

    final result = await case_.recalculateForCurrentUser();

    expect(repo.callCount, 1);
    expect(result.coordinationRepairedCount, 1);
    expect(events, hasLength(1));
    expect(beaconRepo.refreshedBeaconIds, ['B1', 'B2']);
    await sub.cancel();
    await signal.dispose();
  });
}
