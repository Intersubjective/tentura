import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';

/// #607: «Create from this request» carries the chosen plan times in the URL
/// so a web reload of the copy editor does not lose them.
void main() {
  final times = [
    PlanStepTime(
      sourceStepId: 'step-1',
      startAt: DateTime.utc(2026, 11, 3, 8, 30),
      endAt: DateTime.utc(2026, 11, 3, 10),
    ),
    PlanStepTime(
      sourceStepId: 'step-2',
      startAt: DateTime.utc(2026, 11, 4, 9, 15, 30),
    ),
    PlanStepTime(
      sourceStepId: 'step-3',
      endAt: DateTime.utc(2026, 11, 5, 18),
    ),
    const PlanStepTime(sourceStepId: 'step-4'),
  ];

  test('fork plan query key stays stable for web deep links', () {
    expect(kQueryBeaconForkPlan, 'fork_plan');
    expect(kQueryBeaconForkPlan, isNot(kQueryBeaconForkFrom));
  });

  test('plan step times survive the URL round trip', () {
    final encoded = encodePlanStepTimesQuery(times);
    expect(encoded, isNotEmpty);
    expect(decodePlanStepTimesQuery(encoded), times);
  });

  test('times given in local time come back as the same instants', () {
    final local = DateTime(2026, 11, 3, 8, 30);
    final decoded = decodePlanStepTimesQuery(
      encodePlanStepTimesQuery([
        PlanStepTime(sourceStepId: 's', startAt: local),
      ]),
    )!;
    expect(decoded.single.startAt!.isAtSameMomentAs(local), isTrue);
  });

  test('no plan stays no plan; an empty plan stays an empty plan', () {
    expect(encodePlanStepTimesQuery(null), isEmpty);
    expect(decodePlanStepTimesQuery(''), isNull);
    final empty = encodePlanStepTimesQuery(const []);
    expect(empty, isNotEmpty);
    expect(decodePlanStepTimesQuery(empty), isEmpty);
  });

  test('a malformed value copies no plan instead of throwing', () {
    for (final bad in [
      'not json',
      '{"a":1}',
      '[1]',
      '[["s",1]]',
      '[["s","x",null]]',
      '[[null,null,null]]',
      '[["",null,null]]',
    ]) {
      expect(decodePlanStepTimesQuery(bad), isNull, reason: bad);
    }
  });
}
