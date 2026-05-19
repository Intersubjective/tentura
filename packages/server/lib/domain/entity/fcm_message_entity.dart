import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

sealed class FcmMessageEntity {}

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
