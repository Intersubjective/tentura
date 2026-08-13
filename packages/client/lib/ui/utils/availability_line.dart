import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/calendar_day_display.dart';
import 'package:tentura_root/domain/enums.dart';

/// Renders `resume_on` for `{when}` placeholders (pure calendar date; no `toLocal()`).
String availabilityWhenLabel(
  L10n l10n,
  DateTime resumeOn,
  DateTime todayUtc,
) =>
    formatFutureCalendarDayLabel(l10n, resumeOn, todayUtc);

/// Primary own-profile availability status line, or null when open-only is omitted by caller.
String ownAvailabilityPrimaryLine(
  L10n l10n,
  Availability availability,
  DateTime todayUtc,
) {
  switch (availability.effectiveOn(todayUtc)) {
    case AvailabilityView.open:
      return l10n.availabilitySelfOpen;
    case AvailabilityView.limited:
      return l10n.availabilitySelfLimited;
    case AvailabilityView.paused:
      final resumeOn = availability.resumeOn;
      assert(resumeOn != null);
      return l10n.availabilitySelfPausedUntil(
        availabilityWhenLabel(l10n, resumeOn!, todayUtc),
      );
  }
}

/// Secondary own-profile line when limited and paused (resume target state).
String? ownAvailabilitySecondaryLine(
  L10n l10n,
  Availability availability,
  DateTime todayUtc,
) {
  if (!availability.isLimited) return null;
  if (availability.effectiveOn(todayUtc) != AvailabilityView.paused) {
    return null;
  }
  return l10n.availabilitySelfThenLimited;
}

/// Neutral informational line for another person's non-open availability.
String? otherAvailabilityStatusLine(
  L10n l10n,
  Availability availability,
  DateTime todayUtc,
) {
  switch (availability.effectiveOn(todayUtc)) {
    case AvailabilityView.open:
      return null;
    case AvailabilityView.limited:
      return l10n.availabilityLimitedTitle;
    case AvailabilityView.paused:
      final resumeOn = availability.resumeOn;
      assert(resumeOn != null);
      return l10n.availabilityPausedUntil(
        availabilityWhenLabel(l10n, resumeOn!, todayUtc),
      );
  }
}

/// Person-forward paused banner (UNIT 15).
String personForwardPausedBanner(
  L10n l10n, {
  required String name,
  required DateTime resumeOn,
  required DateTime todayUtc,
}) =>
    l10n.availabilityPersonPaused(
      name,
      availabilityWhenLabel(l10n, resumeOn, todayUtc),
    );

/// Partial forward delivery when exactly one person was skipped for availability.
String availabilityDeliveredPartialLine(
  L10n l10n, {
  required int deliveredCount,
  required int requestedCount,
  required String skippedName,
}) =>
    l10n.availabilityDeliveredPartial(
      deliveredCount,
      requestedCount,
      skippedName,
    );

/// Partial forward delivery when two or more people were skipped for availability.
String availabilityDeliveredPartialManyLine(
  L10n l10n, {
  required int deliveredCount,
  required int requestedCount,
  required int skippedCount,
}) =>
    l10n.availabilityDeliveredPartialMany(
      deliveredCount,
      requestedCount,
      skippedCount,
    );
