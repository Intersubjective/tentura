import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Everything a member can do with a Post from its screen: the app bar, the
/// ⋮ menu and the «О посте» sheet all resolve to one of these, and the screen
/// runs it.
enum PostAction {
  info,
  scrollToRoot,
  forward,
  mute,
  unmute,
  pin,
  unpin,
  forwardsGraph,
  showOnField,
  allowForwarding,
  convertToRequest,
  complain,
  leave,
  delete,
}

/// «до 18:40» today, «до 05.10.2026 18:40» on another day.
String postMuteUntilTime(DateTime until, DateTime now) {
  final local = until.toLocal();
  final today = now.toLocal();
  final sameDay =
      local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  return sameDay
      ? timeFormatHm(local)
      : '${dateFormatYMD(local)} ${timeFormatHm(local)}';
}

/// «Заглушено до …» / «навсегда» for a muted Post; null when it is not muted.
String? postMuteLine(
  L10n l10n, {
  required bool mutedForever,
  required DateTime? mutedUntil,
  required DateTime now,
}) {
  if (mutedForever) return l10n.postInfoMutedForever;
  if (mutedUntil == null || !mutedUntil.isAfter(now)) return null;
  return l10n.postInfoMutedUntil(postMuteUntilTime(mutedUntil, now));
}
