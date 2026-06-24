import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_channel.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/entity/digest_cadence.dart';
import 'package:tentura_server/domain/entity/user_presence_entity.dart';

/// Outcome of the email-routing decision for a single event/recipient.
///
/// Exactly one outcome per event so a notification is never both immediately
/// emailed and digested (which would double-notify).
enum EmailDecision {
  /// Do not email (push and/or the Notification Center already cover it).
  none,

  /// Send a per-event email now (highest-stakes, user away / push failed).
  immediate,

  /// Defer to the batched digest.
  digest,
}

/// Pure policy that decides, per recipient, whether a channel may fire.
///
/// Holds no state and performs no I/O — the single place where preference
/// semantics (matrix, snooze, per-beacon mute, quiet hours) are evaluated.
class NotificationPreferenceGate {
  const NotificationPreferenceGate();

  /// Whether [channel] is allowed to deliver this [category] right now.
  ///
  /// [mutedBeaconIds] is the set of beacons currently muted for the account
  /// (the caller resolves any `mutedUntil` expiry before passing it in).
  bool allowsChannel({
    required NotificationChannel channel,
    required NotificationCategory category,
    required NotificationPreferencesEntity prefs,
    required DateTime now,
    String? beaconId,
    Set<String> mutedBeaconIds = const {},
  }) {
    if (prefs.isSnoozedAt(now)) {
      return false;
    }
    if (beaconId != null && mutedBeaconIds.contains(beaconId)) {
      return false;
    }
    final enabled = switch (channel) {
      NotificationChannel.push => prefs.pushCategories.contains(category),
      NotificationChannel.email => prefs.emailCategories.contains(category),
    };
    if (!enabled) {
      return false;
    }
    if (prefs.isWithinQuietHours(now)) {
      return false;
    }
    return true;
  }

  /// Decide how (if at all) email should handle this event for the recipient.
  ///
  /// Immediate email is reserved for [NotificationCategory.asksOfMe] when the
  /// user is absent or push was not delivered; everything else that is
  /// email-enabled flows into the digest (when a cadence is configured).
  EmailDecision decideEmail({
    required NotificationCategory category,
    required NotificationPreferencesEntity prefs,
    required UserPresenceEntity? presence,
    required bool pushDelivered,
    required DateTime now,
    String? beaconId,
    Set<String> mutedBeaconIds = const {},
  }) {
    if (prefs.isSnoozedAt(now)) {
      return EmailDecision.none;
    }
    if (beaconId != null && mutedBeaconIds.contains(beaconId)) {
      return EmailDecision.none;
    }
    if (!prefs.emailCategories.contains(category)) {
      return EmailDecision.none;
    }

    final userAbsent = presence == null || presence.shouldNotify;
    final immediateEligible = category == NotificationCategory.asksOfMe &&
        (!pushDelivered || userAbsent);

    if (immediateEligible && !prefs.isWithinQuietHours(now)) {
      return EmailDecision.immediate;
    }
    if (prefs.emailDigest != DigestCadence.off) {
      return EmailDecision.digest;
    }
    return EmailDecision.none;
  }
}
