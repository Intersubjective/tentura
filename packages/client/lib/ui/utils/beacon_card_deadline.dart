import 'package:intl/intl.dart';

import 'package:tentura/ui/l10n/l10n.dart';

bool _sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Calendar-relative deadline copy: overdue / due today / due tomorrow / short weekday.
///
/// Same semantics as the My Work status strip time slot when the beacon has a deadline.
({String text, bool overdue})? beaconCardCalendarDeadlineStatus(
  L10n l10n,
  DateTime? endAt, {
  DateTime? now,
}) {
  if (endAt == null) return null;
  final endLocal = endAt.toLocal();
  final nowLocal = (now ?? DateTime.now()).toLocal();
  if (!endLocal.isAfter(nowLocal)) {
    return (text: l10n.myWorkStatusOverdue, overdue: true);
  }
  if (_sameCalendarDay(endLocal, nowLocal)) {
    return (text: l10n.myWorkStatusDueToday, overdue: false);
  }
  final tomorrow = nowLocal.add(const Duration(days: 1));
  if (_sameCalendarDay(endLocal, tomorrow)) {
    return (text: l10n.myWorkStatusDueTomorrow, overdue: false);
  }
  final weekday = DateFormat('EEE', l10n.localeName).format(endLocal);
  return (text: l10n.myWorkStatusDueWeekday(weekday), overdue: false);
}

/// Remaining time line for inbox / My Work beacon cards (deadline [endAt]).
///
/// Uses hours-only below 24h; from 24h upward shows days and hours (e.g. `2d 5h left`).
({String text, bool urgent})? beaconCardDeadlineRemainingMeta(
  L10n l10n,
  DateTime? endAt,
) {
  if (endAt == null) return null;
  final now = DateTime.now();
  if (!endAt.isAfter(now)) {
    return (text: l10n.inboxDeadlineEnded, urgent: true);
  }
  final d = endAt.difference(now);
  final totalHours = d.inHours;
  if (totalHours < 1) {
    return (text: l10n.inboxDeadlineLessThanHour, urgent: true);
  }
  if (totalHours >= 24) {
    final days = d.inDays;
    final hoursInDay = totalHours % 24;
    return (
      text: l10n.inboxDeadlineDaysHoursRemaining(days, hoursInDay),
      urgent: false,
    );
  }
  final urgent = totalHours < 24;
  return (text: l10n.inboxDeadlineHoursRemaining(totalHours), urgent: urgent);
}

/// Ultra-compact remaining time for inbox deadline pill (e.g. `31d`, `4h`).
///
/// The `urgent` flag is true when under 24h or already ended.
({String text, bool urgent})? compactDeadlineLabel(L10n l10n, DateTime? endAt) {
  if (endAt == null) return null;
  final now = DateTime.now();
  if (!endAt.isAfter(now)) {
    return (text: l10n.inboxDeadlineEnded, urgent: true);
  }
  final d = endAt.difference(now);
  final totalHours = d.inHours;
  if (totalHours < 1) {
    return (text: l10n.inboxDeadlinePillUnderHour, urgent: true);
  }
  if (totalHours < 24) {
    return (text: l10n.inboxDeadlinePillHours(totalHours), urgent: true);
  }
  final days = d.inDays;
  return (text: l10n.inboxDeadlinePillDays(days), urgent: false);
}
