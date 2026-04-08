import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

/// One-line last-seen / online from snapshot [UserPresenceStatus] + [lastSeenAt]
/// (e.g. Hasura). Uses chat-relative strings under 7 local calendar days, else a
/// localized date.
String profilePresenceDisplayLine({
  required L10n l10n,
  required Locale locale,
  UserPresenceStatus? status,
  DateTime? lastSeenAt,
}) {
  if (status == UserPresenceStatus.online) {
    return l10n.chatPresenceOnline;
  }
  final ts = lastSeenAt;
  if (ts == null || ts.millisecondsSinceEpoch <= 0) {
    return '';
  }
  final localTs = ts.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final lastDay = DateTime(localTs.year, localTs.month, localTs.day);
  final calendarDaysAgo = today.difference(lastDay).inDays;
  if (calendarDaysAgo >= 7) {
    final formatted = DateFormat.yMMMd(locale.toString()).format(localTs);
    return l10n.profilePresenceLastSeenOnDate(formatted);
  }
  final diff = now.difference(localTs);
  if (diff.inSeconds < 60) {
    return l10n.chatPresenceLastSeenJustNow;
  }
  if (diff.inMinutes < 60) {
    return l10n.chatPresenceLastSeenMinutes(diff.inMinutes);
  }
  if (diff.inHours < 24) {
    return l10n.chatPresenceLastSeenHours(diff.inHours);
  }
  return l10n.chatPresenceLastSeenDays(calendarDaysAgo);
}
