import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

/// Pending-invite subtitle: `Waiting · {relative time}`.
String invitePendingSubtitle({
  required L10n l10n,
  required DateTime when,
  required DateTime now,
}) =>
    '${l10n.invitationPendingWaiting} · ${compactRelativeTimeAgo(
      when: when,
      now: now,
      l10n: l10n,
    )}';
