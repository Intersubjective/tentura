import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/schedule_date_format.dart';

/// Accepted-invite subtitle: relative under 7 days ("Joined 3h ago"),
/// absolute date at/after ("Joined on Aug 14") so it never decays into a
/// meaningless "Joined 47d ago".
String inviteAcceptedSubtitle({
  required L10n l10n,
  required DateTime acceptedAt,
  required DateTime now,
}) {
  final diff = now.difference(acceptedAt.toLocal());
  if (diff.inDays < 7) {
    return l10n.friendsInviteJoinedRelative(
      compactRelativeTimeAgo(when: acceptedAt, now: now, l10n: l10n),
    );
  }
  return l10n.friendsInviteJoinedOn(
    formatScheduleDate(acceptedAt, localeName: l10n.localeName, now: now),
  );
}
