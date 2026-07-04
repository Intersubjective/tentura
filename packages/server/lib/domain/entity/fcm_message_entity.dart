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
}
