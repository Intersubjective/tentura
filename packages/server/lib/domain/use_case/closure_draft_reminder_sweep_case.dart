import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/closure_reminder_sweep_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';

import '_use_case_base.dart';

/// A17: hourly reminder to voters whose draft is not what they committed,
/// 24 h before the closing window closes.
@Singleton(order: 3)
final class ClosureDraftReminderSweepCase extends UseCaseBase {
  ClosureDraftReminderSweepCase({
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
      action: () => _reminders.writeDraftReminders(now: instant),
    );
  }
}
