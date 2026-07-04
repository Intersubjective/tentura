import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

sealed class FcmMessageEntity {}

/// Sent over the wire as a data-only FCM message — title/body travel in
/// `data`, never in a top-level `notification` block. See
/// `buildFcmMessagePayload` in `data/service/fcm_service.dart` for why
/// (Safari silently cancels push subscriptions that don't get a displayed
/// notification, and the fix — the client showing it explicitly — would
/// double up with FCM's own automatic display if `notification` came back).
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
