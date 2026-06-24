import 'package:tentura_server/domain/entity/notification_kind.dart';

/// Decides and sends immediate "asked of you" emails (conservative opt-in).
abstract interface class EmailNotificationPort {
  /// Considers (and, if warranted, sends) an immediate email for one recipient
  /// of a just-dispatched notification. No-op unless the category is
  /// asks-of-me, email is enabled, the user is absent / push failed, a verified
  /// email exists, and the per-category cooldown allows it.
  Future<void> considerImmediate({
    required String recipientUserId,
    required NotificationKind kind,
    required String beaconId,
    required String dedupKey,
    required String title,
    required String body,
    required String actionUrl,
    required bool pushDelivered,
  });
}
