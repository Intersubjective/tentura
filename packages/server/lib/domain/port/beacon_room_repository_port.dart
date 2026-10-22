import 'package:tentura_server/domain/entity/room_latest_activity.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_record.dart';
import 'package:tentura_server/domain/entity/room_read_watermark_record.dart';

abstract class BeaconRoomRepositoryPort {
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

  /// U087 — last activity + latest member message of each Request's main
  /// room, keyed by beacon id, read in one query. Callers pass only Requests
  /// the viewer may read; ids with no room rows still get an entry with null
  /// fields.
  Future<Map<String, RoomLatestActivity>> latestRoomActivities(
    Iterable<String> beaconIds,
  );

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
    String? factCardId,
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
    String? quotedFactCardId,
    int? quotedFactRevisionSeq,
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

  /// Admits [offerUserId] with [authorUserId] (the confirming author, author
  /// or steward) recorded as the join actor. Runs in a mutating unit for
  /// [mutatingUserId] (default: [authorUserId]); pass the authenticated actor
  /// when it differs from the confirming author (Arch §5.3).
  Future<void> inviteOfferUserToBeaconRoom({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
    String admissionReason = 'accept',
    String? mutatingUserId,
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

  Future<List<RoomReadWatermarkRecord>> mainRoomReadWatermarks(String beaconId);

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

  /// A helper who is in the room leaves it by withdrawing: post the
  /// `participantLeft` system line (reason key + optional, trimmed note) and
  /// the matching `participantLeft` activity event linked to that line, so
  /// the others see who left and why. The caller decides who qualifies
  /// (`HelpOfferCase.withdraw`: admitted, not a Post addressee).
  /// Call before [revokeOfferUserBeaconRoomAccess] (B084).
  Future<void> recordParticipantLeft({
    required String beaconId,
    required String userId,
    required String withdrawReason,
    String note = '',
  });

  /// The author ended an admitted helper's participation: post the neutral
  /// `participantRemoved` system line (`systemPayload` carries only
  /// `removedUserId`; no actor, no reason, per U41) so the others see the
  /// helper is no longer in the request. The removal reason stays on the
  /// author-side records (`CoordinationRepositoryPort.removeFromRoom`). The
  /// caller decides who qualifies (`CoordinationCase.releaseCommitment`:
  /// admitted, once per release) (#489).
  Future<void> recordParticipantRemoved({
    required String beaconId,
    required String userId,
  });

  /// Writes the next step if its revision is still [baseRevision] (#517).
  /// Returns the saved row, or null when someone changed the line meanwhile
  /// (nothing is written then).
  Future<BeaconRoomStateRecord?> setBeaconRoomCurrentLine({
    required String beaconId,
    required String text,
    required String updatedBy,
    required int baseRevision,
  });

  Future<void> setBeaconSteward({
    required String beaconId,
    required String stewardUserId,
    required String authorUserId,
  });

  /// Returns whether the reaction was added (`false`: it was removed).
  Future<bool> toggleReaction({
    required String messageId,
    required String userId,
    required String emoji,
  });

  /// Claims the member's first response to a Post (`kind` 1: message, 2:
  /// reaction; [sourceId] the message or reaction id). `true` only for the
  /// winning call; `false` for the Post's author, a Request, or a member who
  /// already holds the claim.
  Future<bool> claimPostFirstResponse({
    required String beaconId,
    required String userId,
    required int kind,
    required String sourceId,
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

  /// Title, handle and picture meta per user id, read together.
  Future<
    Map<
      String,
      ({
        String title,
        String handle,
        bool hasPicture,
        int picHeight,
        int picWidth,
        String blurHash,
        String imageId,
      })
    >
  >
  userProfilesByIds(Iterable<String> userIds);
}
