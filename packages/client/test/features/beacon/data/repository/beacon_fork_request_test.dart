import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';

/// `beaconFork` with the plan copy arguments (#220, plan §5.11).
void main() {
  test('a plain fork sends only the id', () {
    final vars = BeaconRepository.forkRequest('B1').vars.toJson();
    expect(vars['id'], 'B1');
    expect(vars['copyPlan'], isNull);
    expect(vars['planStepTimes'], isNull);
  });

  test('copyPlan sends every step time as a UTC instant', () {
    final vars = BeaconRepository.forkRequest(
      'B1',
      copyPlan: true,
      planStepTimes: [
        PlanStepTime(
          sourceStepId: 'PS1',
          startAt: DateTime.utc(2026, 10, 19, 8, 30),
          endAt: DateTime.utc(2026, 10, 19, 9),
        ),
        const PlanStepTime(sourceStepId: 'PS2'),
      ],
    ).vars.toJson();
    expect(vars['copyPlan'], isTrue);
    expect(vars['planStepTimes'], [
      {
        'sourceStepId': 'PS1',
        'startAt': '2026-10-19T08:30:00.000Z',
        'endAt': '2026-10-19T09:00:00.000Z',
      },
      // An untimed step stays untimed (null fields are omitted).
      {'sourceStepId': 'PS2'},
    ]);
  });
}
