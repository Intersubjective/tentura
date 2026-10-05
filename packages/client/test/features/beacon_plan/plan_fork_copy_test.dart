import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_copy_sheet.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

/// Copy-with-plan time arithmetic (#220, plan §5.11). Instants are built in
/// the local zone, like the pickers do, so the test holds in any TZ.
void main() {
  final steps = [
    const PlanStep(id: 'A', title: 'Untimed first'),
    PlanStep(
      id: 'B',
      title: 'Buy screws',
      startAt: DateTime(2026, 10, 12, 8, 30),
      endAt: DateTime(2026, 10, 12, 9),
    ),
    PlanStep(id: 'C', title: 'Due only', endAt: DateTime(2026, 10, 13, 18)),
  ];

  test('anchor is the first timed step in plan order', () {
    expect(planCopySourceAnchor(steps), DateTime(2026, 10, 12, 8, 30));
    expect(planCopySourceAnchor(const [PlanStep(id: 'X', title: 'x')]), isNull);
  });

  test('shift splits into calendar days and minutes of the day', () {
    final shift = planCopyShift(
      sourceAnchor: DateTime(2026, 10, 12, 8, 30),
      newAnchor: DateTime(2026, 10, 19, 8),
    );
    expect(shift, (days: 7, minutes: -30));
    expect(
      planCopyShift(
        sourceAnchor: DateTime(2026, 10, 12, 23, 30),
        newAnchor: DateTime(2026, 10, 11, 0, 30),
      ),
      (days: -1, minutes: -1380),
    );
  });

  test('every timed step moves by the shift; untimed stays untimed', () {
    final times = planCopyStepTimes(steps, (days: 7, minutes: -30));
    expect(times.map((t) => t.sourceStepId), ['A', 'B', 'C']);
    expect(times[0].startAt, isNull);
    expect(times[0].endAt, isNull);
    expect(times[1].startAt, DateTime(2026, 10, 19, 8).toUtc());
    expect(times[1].endAt, DateTime(2026, 10, 19, 8, 30).toUtc());
    expect(times[2].startAt, isNull);
    expect(times[2].endAt, DateTime(2026, 10, 20, 17, 30).toUtc());
    // Wall-clock duration is kept.
    expect(times[1].endAt!.difference(times[1].startAt!), 30.minutes);
  });

  test('calendar arithmetic keeps the local time of day across months', () {
    final moved = shiftPlanInstant(
      DateTime(2026, 1, 31, 8, 30),
      (days: 30, minutes: 0),
    );
    expect(moved.toLocal().hour, 8);
    expect(moved.toLocal().minute, 30);
    expect(moved.toLocal().day, 2);
    expect(moved.toLocal().month, 3);
  });

  test('default anchor keeps a future source, else the next same time', () {
    final source = DateTime(2026, 10, 12, 8, 30);
    expect(
      defaultPlanCopyAnchor(sourceAnchor: source, now: DateTime(2026, 10, 2)),
      source,
    );
    expect(
      defaultPlanCopyAnchor(
        sourceAnchor: source,
        now: DateTime(2026, 10, 20, 7),
      ),
      DateTime(2026, 10, 20, 8, 30).toUtc(),
    );
    expect(
      defaultPlanCopyAnchor(
        sourceAnchor: source,
        now: DateTime(2026, 10, 20, 9),
      ),
      DateTime(2026, 10, 21, 8, 30).toUtc(),
    );
  });

  test('shift label is signed and pluralized', () {
    final en = L10nEn();
    final ru = L10nRu();
    expect(planCopyShiftLabel((days: 0, minutes: 0), en), en.planCopyNoShift);
    expect(
      planCopyShiftLabel((days: 7, minutes: 0), en),
      'all steps shift by +7 days',
    );
    expect(
      planCopyShiftLabel((days: -1, minutes: 0), ru),
      'все шаги сдвинутся на −1 день',
    );
    expect(
      planCopyShiftLabel((days: 5, minutes: 0), ru),
      'все шаги сдвинутся на +5 дней',
    );
    expect(
      planCopyShiftLabel((days: 2, minutes: -30), en),
      startsWith('all steps shift by +2 days −'),
    );
  });
}

extension on int {
  Duration get minutes => Duration(minutes: this);
}
