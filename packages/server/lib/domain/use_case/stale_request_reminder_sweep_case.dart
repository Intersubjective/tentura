import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/closure/iso_week_key.dart';
import 'package:tentura_server/domain/port/closure_reminder_sweep_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';

import '_use_case_base.dart';

/// A17: hourly weekly nudge to the author of an open request that is past its
/// end or has had no activity for 14 days (at most one per ISO week).
@Singleton(order: 3)
final class StaleRequestReminderSweepCase extends UseCaseBase {
  StaleRequestReminderSweepCase({
    required MutatingUnitOfWorkPort unitOfWork,
    required ClosureReminderSweepPort reminders,
    required super.env,
    required super.logger,
  }) : _uow = unitOfWork,
       _reminders = reminders;

  final MutatingUnitOfWorkPort _uow;
  final ClosureReminderSweepPort _reminders;

  Future<int> runDue({DateTime? now}) {
    final instant = (now ?? DateTime.timestamp()).toUtc();
    return _uow.run<int>(
      action: () => _reminders.writeStaleRequestReminders(
        now: instant,
        weekKey: isoWeekKey(instant),
      ),
    );
  }
}
