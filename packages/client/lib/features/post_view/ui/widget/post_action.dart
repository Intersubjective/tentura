import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Everything a member can do with a Post from its screen: the app bar, the
/// ⋮ menu and the «О посте» sheet all resolve to one of these, and the screen
/// runs it.
enum PostAction {
  info,

  /// «Участники»: «О посте» scrolled to its participants (#715).
  participants,
  scrollToRoot,
  forward,

  /// «Позвать» in the participants: the post invite dialog itself, not the
  /// Forward screen (#715).
  invite,
  mute,
  unmute,
  pin,
  unpin,
  forwardsGraph,
  showOnField,
  allowForwarding,

  /// «Сократить срок» / «Завершить сейчас»: author-only, open Post.
  shorten,
  closeNow,

  /// «Оформить запрос»: bud a Request from a Post message (plan D1).
  budRequest,
  complain,
  leave,
  delete,
}

/// «до 18:40» today, «до пн, 5 окт. 18:40» on another day (#450).
String postMuteUntilTime(
  DateTime until,
  DateTime now, {
  required String locale,
}) {
  final local = until.toLocal();
  final today = now.toLocal();
  final sameDay =
      local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  return sameDay
      ? timeFormatHm(local, locale: locale)
      : '${dateFormatDay(local, locale: locale, now: today)} '
            '${timeFormatHm(local, locale: locale)}';
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
  return l10n.postInfoMutedUntil(
    postMuteUntilTime(mutedUntil, now, locale: l10n.localeName),
  );
}
