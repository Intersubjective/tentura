import 'package:tentura/ui/l10n/l10n.dart';

/// Compact remaining duration: `{days}d {hours}h` → `{hours}h {minutes}m` → `{minutes}m` → `<1m`.
String formatCompactDurationRemaining(
  Duration remaining,
  L10n l10n,
) {
  if (remaining.isNegative || remaining == Duration.zero) {
    return l10n.evaluationReviewDurationLessThanMinute;
  }
  final days = remaining.inDays;
  final hoursTotal = remaining.inHours;
  final hours = hoursTotal % 24;
  final minutes = remaining.inMinutes % 60;
  if (days > 0) {
    return l10n.evaluationReviewDurationDaysHours(days, hours);
  }
  if (hoursTotal > 0) {
    return l10n.evaluationReviewDurationHoursMinutes(hoursTotal, minutes);
  }
  if (minutes > 0) {
    return l10n.evaluationReviewDurationMinutes(minutes);
  }
  return l10n.evaluationReviewDurationLessThanMinute;
}
