import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';

/// #607: «Create from this request» carries the chosen plan step times in
/// the editor's URL, so a web reload (args rebuilt from the query alone)
/// still copies the plan at those times. The call site hands the times to
/// `AppNavigator.createBeacon` (plan_copy_sheet_test.dart); this pins the
/// route half: `forkPlanTimes` is both an arg and the `fork_plan` query.
void main() {
  test('BeaconCreateRoute puts forkPlanTimes in the URL query', () {
    final times = [
      PlanStepTime(
        sourceStepId: 'PS1',
        startAt: DateTime.utc(2026, 10, 3, 9),
        endAt: DateTime.utc(2026, 10, 3, 10),
      ),
      const PlanStepTime(sourceStepId: 'PS2'),
    ];
    final encoded = encodePlanStepTimesQuery(times);

    final route = BeaconCreateRoute(
      forkSourceId: 'src',
      forkPlanTimes: encoded,
    );

    expect(route.args!.forkPlanTimes, encoded);
    final fromUrl = decodePlanStepTimesQuery(
      route.queryParams.getString(kQueryBeaconForkPlan, ''),
    );
    expect(fromUrl, times);
  });

  test('no plan times leave the fork_plan query empty', () {
    final route = BeaconCreateRoute(forkSourceId: 'src');

    expect(
      decodePlanStepTimesQuery(
        route.queryParams.getString(kQueryBeaconForkPlan, ''),
      ),
      isNull,
    );
  });
}
