import 'package:freezed_annotation/freezed_annotation.dart';

import 'notification_kind.dart';
import 'notification_priority.dart';

part 'beacon_notification_intent.freezed.dart';

@freezed
abstract class BeaconNotificationIntent with _$BeaconNotificationIntent {
  const factory BeaconNotificationIntent({
    required NotificationKind kind,
    required NotificationPriority priority,
    required String beaconId,
    required String actorUserId,
  @Default('') String titleExcerpt,
  @Default('') String bodyExcerpt,
  @Default('') String beaconTitle,
    String? coordinationItemId,
    String? targetPersonId,
    @Default([]) List<String> forwardRecipientIds,
    @Default([]) List<String> admittedUserIds,
    @Default([]) List<String> moderatorUserIds,
    @Default(false) bool promiseWithdrawn,
  }) = _BeaconNotificationIntent;
}
