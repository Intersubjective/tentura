import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/notification_excerpt.dart';
import 'package:tentura_server/domain/port/beacon_notification_port.dart';

/// Legacy façade over [BeaconNotificationPort] for room-related pushes.
@lazySingleton
class BeaconRoomPushService {
  BeaconRoomPushService(this._notifications);

  final BeaconNotificationPort _notifications;

  Future<void> notifyForwardReceived({
    required String beaconId,
    required String senderId,
    required String beaconAuthorId,
    required List<String> recipientIds,
  }) =>
      _notifications.dispatch(
        BeaconNotificationIntent(
          kind: NotificationKind.newRelay,
          priority: NotificationPriority.low,
          beaconId: beaconId,
          actorUserId: senderId,
          forwardRecipientIds: recipientIds
              .where((id) => id != senderId && id != beaconAuthorId)
              .toList(),
        ),
      );

  Future<void> notifyHelpOfferToAuthor({
    required String beaconId,
    required String helpOffererId,
    required String authorId,
  }) =>
      _notifications.dispatch(
        BeaconNotificationIntent(
          kind: NotificationKind.commitmentEvent,
          priority: NotificationPriority.normal,
          beaconId: beaconId,
          actorUserId: helpOffererId,
          targetPersonId: authorId,
        ),
      );

  Future<void> notifyRoomAdmitted({
    required String receiverId,
    required String beaconId,
    required String actorUserId,
  }) =>
      _notifications.dispatch(
        BeaconNotificationIntent(
          kind: NotificationKind.roomAccess,
          priority: NotificationPriority.normal,
          beaconId: beaconId,
          actorUserId: actorUserId,
          targetPersonId: receiverId,
        ),
      );

  Future<void> notifyHelpOfferedToModerators({
    required String beaconId,
    required String offererUserId,
    required List<String> moderatorUserIds,
  }) =>
      _notifications.dispatch(
        BeaconNotificationIntent(
          kind: NotificationKind.commitmentEvent,
          priority: NotificationPriority.normal,
          beaconId: beaconId,
          actorUserId: offererUserId,
          moderatorUserIds: moderatorUserIds,
        ),
      );

  Future<void> notifyPlanUpdatedToRoom({
    required String beaconId,
    required String actorUserId,
    required List<String> admittedUserIds,
    String planExcerpt = '',
  }) =>
      _notifications.dispatch(
        BeaconNotificationIntent(
          kind: NotificationKind.coordinationChanged,
          priority: NotificationPriority.normal,
          beaconId: beaconId,
          actorUserId: actorUserId,
          bodyExcerpt: notificationExcerpt(planExcerpt),
          admittedUserIds: admittedUserIds,
        ),
      );

  @Deprecated('Fact pinning does not send push notifications')
  Future<void> notifyFactPinned({
    required String beaconId,
    required String actorUserId,
    required bool isPublic,
    required List<String> recipientUserIds,
  }) async {}

  /// Coordination-item helpers (preferred over removed legacy room-message paths).
  Future<void> notifyNeedsMe({
    required String beaconId,
    required String actorUserId,
    required String targetUserId,
    required String excerpt,
    String? coordinationItemId,
  }) =>
      _notifications.dispatch(
        BeaconNotificationIntent(
          kind: NotificationKind.needsMe,
          priority: NotificationPriority.high,
          beaconId: beaconId,
          actorUserId: actorUserId,
          targetPersonId: targetUserId,
          bodyExcerpt: notificationExcerpt(excerpt),
          coordinationItemId: coordinationItemId,
        ),
      );

  Future<void> notifyPromiseMade({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    String? targetPersonId,
    String? coordinationItemId,
    bool withdrawn = false,
  }) =>
      _notifications.dispatch(
        BeaconNotificationIntent(
          kind: NotificationKind.promiseMade,
          priority: NotificationPriority.normal,
          beaconId: beaconId,
          actorUserId: actorUserId,
          bodyExcerpt: notificationExcerpt(excerpt),
          targetPersonId: targetPersonId,
          coordinationItemId: coordinationItemId,
          promiseWithdrawn: withdrawn,
        ),
      );

  Future<void> notifyBlockerOpened({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    String? targetPersonId,
    String? coordinationItemId,
  }) =>
      _notifications.dispatch(
        BeaconNotificationIntent(
          kind: NotificationKind.blockerOpened,
          priority: NotificationPriority.high,
          beaconId: beaconId,
          actorUserId: actorUserId,
          bodyExcerpt: notificationExcerpt(excerpt),
          targetPersonId: targetPersonId,
          coordinationItemId: coordinationItemId,
        ),
      );

  Future<void> notifyBlockerResolved({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    String? targetPersonId,
    String? coordinationItemId,
  }) =>
      _notifications.dispatch(
        BeaconNotificationIntent(
          kind: NotificationKind.blockerResolved,
          priority: NotificationPriority.normal,
          beaconId: beaconId,
          actorUserId: actorUserId,
          bodyExcerpt: notificationExcerpt(excerpt),
          targetPersonId: targetPersonId,
          coordinationItemId: coordinationItemId,
        ),
      );

  Future<void> notifyStaleRemind({
    required String beaconId,
    required String actorUserId,
    required String targetPersonId,
    required String excerpt,
    String? coordinationItemId,
  }) =>
      _notifications.dispatch(
        BeaconNotificationIntent(
          kind: NotificationKind.staleRemind,
          priority: NotificationPriority.high,
          beaconId: beaconId,
          actorUserId: actorUserId,
          targetPersonId: targetPersonId,
          bodyExcerpt: notificationExcerpt(excerpt),
          coordinationItemId: coordinationItemId,
        ),
      );

  Future<void> notifyReviewOpened({
    required String beaconId,
    required String beaconTitle,
    required Set<String> recipientUserIds,
    required String actorUserId,
  }) =>
      _notifications.dispatch(
        BeaconNotificationIntent(
          kind: NotificationKind.reviewReady,
          priority: NotificationPriority.high,
          beaconId: beaconId,
          actorUserId: actorUserId,
          beaconTitle: beaconTitle,
          admittedUserIds: recipientUserIds.toList(),
        ),
      );
}
