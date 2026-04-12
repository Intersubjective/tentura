import 'package:tentura/ui/l10n/l10n.dart';

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
