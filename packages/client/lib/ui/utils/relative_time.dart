import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

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

/// #189 rev 2 — the short age on a For You card, its tombstone and its rows:
/// «сейчас · 40 мин · 2 ч · 3 дн. · сб, 12 сент. · пт, 12 сент. 2025 г.»
/// (EN «now · 40m · 2h · 3d · Sat, Sep 12 · Fri, Sep 12, 2025»). It has to
/// fit beside a one-line event at 1.3x text, which the shared
/// [compactRelativeTimeAgo] («92 дн. назад») does
/// not; that one keeps its many other callers unchanged.
///
/// Speak [cardRelativeAgeSpoken] instead: the abbreviations are for the eye.
String cardRelativeAge({
  required DateTime when,
  required DateTime now,
  required L10n l10n,
}) {
  final localWhen = when.toLocal();
  final diff = now.difference(localWhen);
  if (diff.isNegative || diff.inSeconds < 60) {
    return l10n.relativeTimeCompactNow;
  }
  if (diff.inMinutes < 60) return l10n.relativeTimeCompactMinutes(diff.inMinutes);
  if (diff.inHours < 24) return l10n.relativeTimeCompactHours(diff.inHours);
  if (diff.inDays < 7) return l10n.relativeTimeCompactDays(diff.inDays);
  // #450/#609: past a week it is the app's weekday day, «Sat, Oct 31» /
  // «сб, 31 окт.», with the year when it is not this year — never a
  // numeric yMd date.
  return dateFormatDay(localWhen, locale: l10n.localeName, now: now);
}

/// The spoken form of [cardRelativeAge]: «40 минут назад», «2 hours ago».
/// Past a week it is the same date the eye reads.
String cardRelativeAgeSpoken({
  required DateTime when,
  required DateTime now,
  required L10n l10n,
}) {
  final diff = now.difference(when.toLocal());
  if (diff.isNegative || diff.inSeconds < 60) {
    return l10n.relativeTimeSpokenNow;
  }
  if (diff.inMinutes < 60) return l10n.relativeTimeSpokenMinutes(diff.inMinutes);
  if (diff.inHours < 24) return l10n.relativeTimeSpokenHours(diff.inHours);
  if (diff.inDays < 7) return l10n.relativeTimeSpokenDays(diff.inDays);
  return cardRelativeAge(when: when, now: now, l10n: l10n);
}
