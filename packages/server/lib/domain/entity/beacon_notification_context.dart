import 'package:freezed_annotation/freezed_annotation.dart';

part 'beacon_notification_context.freezed.dart';

@freezed
abstract class BeaconNotificationContext with _$BeaconNotificationContext {
  const factory BeaconNotificationContext({
    @Default('') String beaconAuthorId,
    @Default({}) Set<String> admittedUserIds,
    @Default({}) Set<String> stewardUserIds,
    @Default({}) Set<String> activeHelpOfferUserIds,
    @Default({}) Set<String> activeRequestParticipantUserIds,
    @Default({}) Set<String> activePlanParticipantUserIds,
    @Default({}) Set<String> inboxStanceUserIds,
  }) = _BeaconNotificationContext;
}
