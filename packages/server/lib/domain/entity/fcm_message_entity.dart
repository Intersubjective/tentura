import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

sealed class FcmMessageEntity {}

/// Sent over the wire as a data-only FCM message — title/body travel in
/// `data`, never in a top-level `notification` block, so display is always
/// the client's explicit `showNotification()` call, consistent across every
/// browser instead of each one's inconsistent automatic default. See
/// `buildFcmMessagePayload` in `data/service/fcm_service.dart` for the full
/// story (including a corrected theory about why this doesn't actually
/// explain iOS-specific delivery failures — that turned out to be an iOS
/// 16.x platform setting, not this).
class FcmNotificationEntity implements FcmMessageEntity {
  const FcmNotificationEntity({
    required this.title,
    required this.body,
    this.actionUrl,
    this.imageUrl,
    this.beaconId,
    this.coordinationItemId,
    this.kind,
    this.priority,
    this.beaconKind = BeaconKind.request,
    this.stepId,
    this.actions = const [],
    this.actionToken,
    this.actionFeedback,
    this.tag,
    this.ttlSeconds,
    this.urgency,
  });

  final String title;

  final String body;

  final String? imageUrl;

  final String? actionUrl;

  /// Used for batch coalescing (not all fields sent on FCM wire).
  final String? beaconId;

  final String? coordinationItemId;

  final NotificationKind? kind;

  final NotificationPriority? priority;

  /// Which copy family batches of this message use.
  final BeaconKind beaconKind;

  /// Plan step a plan push is about (#220 §5.9).
  final String? stepId;

  /// Notification buttons (Chromium web push only; elsewhere a tap opens
  /// [actionUrl]).
  final List<FcmNotificationAction> actions;

  /// Signed push action token (`PushActionTokenPort`) the service worker
  /// posts back for [actions].
  final String? actionToken;

  /// Localized lines the service worker shows after a button tap.
  final FcmActionFeedback? actionFeedback;

  /// Notification tag (one notification per tag on the device).
  final String? tag;

  /// Overrides the sender's default TTL.
  final int? ttlSeconds;

  /// Web push `Urgency` header (`very-low` | `low` | `normal` | `high`).
  final String? urgency;
}

/// One notification button.
final class FcmNotificationAction {
  const FcmNotificationAction({required this.id, required this.title});

  /// `done` | `ack` | `open`.
  final String id;
  final String title;

  Map<String, String> toJson() => {'id': id, 'title': title};
}

/// What the service worker shows once a button was handled.
final class FcmActionFeedback {
  const FcmActionFeedback({
    required this.done,
    required this.ack,
    required this.failed,
  });

  /// «Отмечено».
  final String done;

  /// «Подтверждено».
  final String ack;

  /// «Не получилось — откройте шаг».
  final String failed;
}
