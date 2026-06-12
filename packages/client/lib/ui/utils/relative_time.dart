import 'package:tentura/ui/l10n/l10n.dart';

/// Compact human-readable "time ago" label: just now → minutes → hours → days.
String compactRelativeTimeAgo({
  required DateTime when,
  required DateTime now,
  required L10n l10n,
}) {
  final localWhen = when.toLocal();
  final diff = now.difference(localWhen);
  if (diff.isNegative || diff.inSeconds < 60) {
    return l10n.relativeTimeJustNow;
  }
  if (diff.inMinutes < 60) {
    return l10n.relativeTimeMinutesAgo(diff.inMinutes);
  }
  if (diff.inHours < 24) {
    return l10n.relativeTimeHoursAgo(diff.inHours);
  }
  final today = DateTime(now.year, now.month, now.day);
  final whenDay = DateTime(localWhen.year, localWhen.month, localWhen.day);
  final calendarDaysAgo = today.difference(whenDay).inDays;
  return l10n.relativeTimeDaysAgo(calendarDaysAgo);
}
