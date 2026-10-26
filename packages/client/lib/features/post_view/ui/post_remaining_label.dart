import 'package:tentura/ui/l10n/l10n.dart';

/// Countdown rounded down to whole days or hours, with at least one minute.
String postRemainingLabel(L10n l10n, Duration remaining) {
  if (remaining.inDays >= 1) return l10n.postRemainingDays(remaining.inDays);
  if (remaining.inHours >= 1) return l10n.postRemainingHours(remaining.inHours);
  return l10n.postRemainingMinutes(
    remaining.inMinutes < 1 ? 1 : remaining.inMinutes,
  );
}
