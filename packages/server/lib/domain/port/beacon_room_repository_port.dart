import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_record.dart';

abstract class BeaconRoomRepositoryPort {
  Future<void> admitParticipant({
    required String beaconId,
    required String participantUserId,
    required String actorUserId,
    String admissionReason = 'admit',
  });

  Future<Map<String, String>> attachmentsJsonByMessageIds(
    Iterable<String> messageIds,
  );

  Future<String?> beaconAuthorUserId(String beaconId);

  Future<int> countAttachmentsForMessage(String messageId);

  Future<int> countRoomMessagesAfter({
    required String beaconId,
    DateTime? after,
    String? excludeAuthorId,
  });

  /// Count room messages authored by [authorId] within the trailing [window]
  /// (spam-control rate limiting; spans all beacons and threads).
  Future<int> countRecentMessagesByAuthor({
    required String authorId,
    required Duration window,
  });

  Future<void> deleteRoomMessage({required String messageId});

  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  });

  Future<BeaconRoomStateRecord?> getBeaconRoomState(String beaconId);

  Future<DateTime?> getMainRoomLastSeen({
    required String beaconId,
    required String userId,
  });

  Future<BeaconRoomMessageAttachmentRecord?> getRoomMessageAttachmentById(
    String attachmentId,
  );

  Future<BeaconRoomMessageRecord?> getRoomMessageById(String messageId);

  Future<BeaconRoomMessageRecord?> getRoomMessageByLinkedPollingId(
    String pollingId,
  );

  Future<Map<String, String?>> helpTypesByUserId(String beaconId);

  /// Active help-offer fields keyed by user id. Key present ⇒ active offer.
  /// [roleLabel] is never null when the key is present (`''` if unset in DB).
  Future<Map<String, ({String? helpType, String roleLabel})>>
  activeHelpOfferHintsByUserId(String beaconId);

  Future<void> insertActivityEvent({
    required String beaconId,
    required int visibility,
    required int type,
    required String actorId,
    String? targetUserId,
    String? sourceMessageId,
    Map<String, Object?>? diff,
  });

  Future<Map<String, Object?>> insertAndEnrichPollMessage({
    required String beaconId,
    required String authorId,
    required String linkedPollingId,
    required String viewerUserId,
  });

  Future<Map<String, Object?>?> roomMessageTarget({
    required String beaconId,
    required String messageId,
    required String viewerUserId,
  });

  // DORMANT(item-threads): threadItemId on room-message port methods; always null in production (General is thread_item_id IS NULL).
  // Rooms are General-only (guard: beacon_room_message_general_only_guard, DiscussionScopeDisabledException); thread_item_id is always NULL for new rows. Do not design for this path. See #192.
  Future<BeaconRoomMessageRecord> insertRoomMessage({
    required String beaconId,
    required String authorId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    String? linkedParticipantId,
    String? linkedPollingId,
    int? semanticMarker,
    Map<String, Object?>? systemPayload,
    List<String> mentions = const [],
    List<Map<String, Object?>> mentionSpans = const [],
  });

  Future<void> insertRoomMessageAttachmentFile({
    required String attachmentId,
    required String messageId,
    required int position,
    required String storagePath,
    required String mime,
    required int sizeBytes,
    required String displayName,
    required String mutatingUserId,
  });

  Future<void> insertRoomMessageAttachmentImage({
    required String attachmentId,
    required String messageId,
    required int position,
    required String imageId,
    required String mime,
    required int sizeBytes,
    required String displayName,
    required String mutatingUserId,
  });

  Future<void> inviteOfferUserToBeaconRoom({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
    String admissionReason = 'accept',
  });

  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  });

  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  });

  Future<List<MyWorkLastActivityEventRow>> latestActivityEventsByBeaconIds({
    required List<String> beaconIds,
    required String viewerUserId,
  });

  Future<DateTime?> latestMainRoomMessageCreatedAt(String beaconId);

  Future<List<Map<String, Object?>>> listActivityEvents({
    required String beaconId,
    int limit = 200,
  });

  Future<List<String>> listAdmittedUserIds(String beaconId);

  Future<List<AdmittedRoomMentionParticipant>> listAdmittedMentionParticipants(
    String beaconId,
  );

  Future<List<Map<String, Object?>>> listMessagesEnriched({
    required String beaconId,
    required String viewerUserId,
    String? threadItemId,
    DateTime? before,
    int limit = 50,
  });

  Future<List<BeaconParticipantRecord>> listParticipants(String beaconId);

  Future<List<String>> listStewardUserIds(String beaconId);

  Future<Map<String, DateTime>> mainRoomLastSeenByUserIds({
    required String beaconId,
    required List<String> userIds,
  });

  Future<DateTime> markBeaconRoomSeen({
    required String userId,
    required String beaconId,
    required String? threadItemId,
    required DateTime at,
  });

  Future<void> markRoomMessageSemanticDone({
    required String messageId,
    required String actingUserId,
  });

  Future<void> participantOfferHelp({
    required String beaconId,
    required String userId,
    required String note,
  });

  Future<List<String>> resolveMentionUserIdsForBeacon({
    required String beaconId,
    required String body,
  });

  Future<void> revokeOfferUserBeaconRoomAccess({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
  });

  Future<void> setBeaconRoomCurrentLine({
    required String beaconId,
    required String text,
    required String updatedBy,
  });

  Future<void> setBeaconSteward({
    required String beaconId,
    required String stewardUserId,
    required String authorUserId,
  });

  Future<void> toggleReaction({
    required String messageId,
    required String userId,
    required String emoji,
  });

  Future<void> updateMessage({
    required String messageId,
    required String newBody,
    required List<String> mentions,
    required List<Map<String, Object?>> mentionSpans,
  });

  Future<Map<String, String>> userHandlesByIds(Iterable<String> userIds);

  Future<
    Map<
      String,
      ({
        bool hasPicture,
        int picHeight,
        int picWidth,
        String blurHash,
        String imageId,
      })
    >
  >
  userPicMetaByIds(Iterable<String> userIds);

  Future<Map<String, String>> userTitlesByIds(Iterable<String> userIds);
}
