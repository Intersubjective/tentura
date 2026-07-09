import 'package:mockito/mockito.dart';

import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';

/// Test double with no-op implementations for all [BeaconRoomNotificationPort] methods.
class NoopBeaconRoomNotificationPort extends Fake
    implements BeaconRoomNotificationPort {
  @override
  Future<void> notifyBlockerOpened({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    String? targetPersonId,
    String? coordinationItemId,
  }) async {}

  @override
  Future<void> notifyBlockerResolved({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    String? targetPersonId,
    String? coordinationItemId,
  }) async {}

  @override
  Future<void> notifyForwardReceived({
    required String beaconId,
    required String senderId,
    required String beaconAuthorId,
    required List<String> recipientIds,
  }) async {}

  @override
  Future<void> notifyHelpOfferToAuthor({
    required String beaconId,
    required String helpOffererId,
    required String authorId,
  }) async {}

  @override
  Future<void> notifyHelpOfferedToModerators({
    required String beaconId,
    required String offererUserId,
    required List<String> moderatorUserIds,
  }) async {}

  @override
  Future<void> notifyCommitmentDeclined({
    required String receiverId,
    required String beaconId,
    required String actorUserId,
    required String reason,
  }) async {}

  @override
  Future<void> notifyCommitmentRemoved({
    required String receiverId,
    required String beaconId,
    required String actorUserId,
    required String reason,
  }) async {}

  @override
  Future<void> notifyHelpWithdrawn({
    required String beaconId,
    required String withdrawerUserId,
  }) async {}

  @override
  Future<void> notifyNeedsMe({
    required String beaconId,
    required String actorUserId,
    required String targetUserId,
    required String excerpt,
    String? coordinationItemId,
  }) async {}

  @override
  Future<void> notifyPlanUpdatedToRoom({
    required String beaconId,
    required String actorUserId,
    required List<String> admittedUserIds,
    String planExcerpt = '',
  }) async {}

  @override
  Future<void> notifyPromiseMade({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    String? targetPersonId,
    String? coordinationItemId,
    bool withdrawn = false,
  }) async {}

  @override
  Future<void> notifyReviewOpened({
    required String beaconId,
    required String beaconTitle,
    required Set<String> recipientUserIds,
    required String actorUserId,
  }) async {}

  @override
  Future<void> notifyRoomAdmitted({
    required String receiverId,
    required String beaconId,
    required String actorUserId,
  }) async {}

  @override
  Future<void> notifyStaleRemind({
    required String beaconId,
    required String actorUserId,
    required String targetPersonId,
    required String excerpt,
    String? coordinationItemId,
  }) async {}
}
