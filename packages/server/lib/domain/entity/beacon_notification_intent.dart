import 'package:freezed_annotation/freezed_annotation.dart';

import 'beacon_kind.dart';
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
    int? coordinationItemKind,
    String? coordinationItemId,
    String? targetPersonId,
    @Default([]) List<String> forwardRecipientIds,
    @Default([]) List<String> admittedUserIds,
    @Default([]) List<String> moderatorUserIds,
    @Default(false) bool promiseWithdrawn,
    @Default(false) bool isBackupOffer,
    @Default(BeaconKind.request) BeaconKind beaconKind,

    /// Request plan copy: a relative distance in whole minutes (until a step
    /// starts, or how late it is). Server copy never prints a clock time
    /// (plan K16).
    int? relativeMinutes,
  }) = _BeaconNotificationIntent;
}
