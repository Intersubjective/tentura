@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/ui/test_ids.dart';

import 'beacon_view_screen_harness.dart';

/// #804: after the Request closes in another tab, the stale «Add plan» ⋮ entry
/// must disappear even when the cached plan is still `editable`.
void main() {
  testWidgets('⋮ loses Add plan when beacon status becomes closed live', (
    tester,
  ) async {
    final author = beaconViewHarnessAuthorState();
    final harness = await pumpBeaconViewHarness(
      tester,
      size: kBeaconViewHarnessCompact,
      beaconState: author,
      threadsState: beaconViewHarnessThreadsState(),
      plan: const BeaconPlan(
        beaconId: kBeaconViewHarnessBeaconId,
        editable: true,
        tickable: true,
      ),
    );
    final addPlan = find.byKey(TestIds.key(TestIds.beaconOverflowAddPlan));
    await tester.tap(find.byKey(TestIds.key(TestIds.beaconOverflowMenu)).first);
    await tester.pumpAndSettle();
    expect(addPlan, findsOneWidget);

    await tester.tapAt(const Offset(20, 500));
    await tester.pumpAndSettle();

    harnessSetBeaconViewState(
      harness.beaconViewCubit,
      author.copyWith(
        beacon: author.beacon.copyWith(status: BeaconStatus.closed),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(TestIds.key(TestIds.beaconOverflowMenu)).first);
    await tester.pumpAndSettle();
    expect(addPlan, findsNothing);
  });
}
