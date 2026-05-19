import 'package:freezed_annotation/freezed_annotation.dart';

import 'notification_priority.dart';
import 'notification_recipient_reason.dart';

part 'beacon_notification_recipient.freezed.dart';

@freezed
abstract class BeaconNotificationRecipient with _$BeaconNotificationRecipient {
  const factory BeaconNotificationRecipient({
    required String userId,
    required NotificationRecipientReason reason,
    required NotificationPriority priority,
  }) = _BeaconNotificationRecipient;
}
