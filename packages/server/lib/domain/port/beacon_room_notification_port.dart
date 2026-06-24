abstract class BeaconRoomNotificationPort {
  Future<void> notifyBlockerOpened({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    String? targetPersonId,
    String? coordinationItemId,
  });

  Future<void> notifyBlockerResolved({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    String? targetPersonId,
    String? coordinationItemId,
  });

  Future<void> notifyForwardReceived({
    required String beaconId,
    required String senderId,
    required String beaconAuthorId,
    required List<String> recipientIds,
  });

  Future<void> notifyHelpOfferToAuthor({
    required String beaconId,
    required String helpOffererId,
    required String authorId,
  });

  Future<void> notifyHelpOfferedToModerators({
    required String beaconId,
    required String offererUserId,
    required List<String> moderatorUserIds,
  });

  Future<void> notifyHelpWithdrawn({
    required String beaconId,
    required String withdrawerUserId,
  });

  Future<void> notifyNeedsMe({
    required String beaconId,
    required String actorUserId,
    required String targetUserId,
    required String excerpt,
    String? coordinationItemId,
  });

  Future<void> notifyPlanUpdatedToRoom({
    required String beaconId,
    required String actorUserId,
    required List<String> admittedUserIds,
    String planExcerpt = '',
  });

  Future<void> notifyPromiseMade({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    String? targetPersonId,
    String? coordinationItemId,
    bool withdrawn = false,
  });

  Future<void> notifyReviewOpened({
    required String beaconId,
    required String beaconTitle,
    required Set<String> recipientUserIds,
    required String actorUserId,
  });

  Future<void> notifyRoomAdmitted({
    required String receiverId,
    required String beaconId,
    required String actorUserId,
  });

  Future<void> notifyStaleRemind({
    required String beaconId,
    required String actorUserId,
    required String targetPersonId,
    required String excerpt,
    String? coordinationItemId,
  });
}
