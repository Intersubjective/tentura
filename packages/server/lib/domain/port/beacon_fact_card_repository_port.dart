import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_outcome.dart';
import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';
import 'package:tentura_server/domain/entity/fact_copy_source.dart';
import 'package:tentura_server/domain/entity/prepared_fact_copy.dart';

/// Server-side data for checking the attachment list a fact edit sends.
typedef FactEditAttachmentLookup = ({
  /// Attachments on any revision of the fact, by attachment id; when an id
  /// is on several revisions, the latest one wins.
  Map<String, Map<String, Object?>> known,

  /// Image rows the actor authored, by image id.
  Map<String, ({String blurHash, int width, int height})> ownedImages,
});

/// One Request a fact can be copied into.
typedef FactCopyDestinationRow = ({
  String id,
  int kind,
  String title,
  bool isDraft,
  DateTime? expiresAt,
});

abstract class BeaconFactCardRepositoryPort {
  /// One SELECT: beacon status, room use (author, steward or admitted) and
  /// `beacon_can_read_content`. `exists` is false for an unknown beacon.
  Future<BeaconFactRoomAccess> loadRoomAccess({
    required String beaconId,
    required String userId,
  });

  /// Non-removed facts with pinner / last editor titles joined; room-only
  /// facts only when [includeRoomOnly]. `savedByMe` is for [viewerId].
  Future<List<BeaconFactCardEntity>> listForBeacon({
    required String beaconId,
    required String viewerId,
    required bool includeRoomOnly,
  });

  /// Newest live (active or corrected) public fact per beacon, trimmed and
  /// at most 160 chars. Beacons without one have no entry.
  Future<Map<String, String>> publicFactSnippetsByBeaconIds(
    List<String> beaconIds,
  );

  /// Pins [factText] (trimmed) as a live fact in one statement. Throws
  /// `BeaconFactCardAlreadyPinnedException` when [sourceMessageId] already
  /// has a live fact and `IdNotFoundException` when it is not a message of
  /// [beaconId].
  Future<BeaconFactCardEntity> pinFact({
    required String beaconId,
    required String factText,
    required int visibility,
    required String pinnedBy,
    String? sourceMessageId,
  });

  /// Inserts [prepared] as live room-only facts of [destinationBeaconId]
  /// with origin and a copied revision 1, joining an ambient transaction of
  /// the same actor. Locks the destination row: missing or deleted throws
  /// `UnauthorizedException`; a published destination gets one
  /// facts-brought line and a `factPinned` event per inserted fact. An
  /// origin that already has a live copy there is skipped. Returns, per
  /// prepared copy and in order, its `factCardId` when inserted, or the
  /// existing copy's id.
  Future<List<String>> insertPreparedCopies({
    required String destinationBeaconId,
    required String actorUserId,
    required List<PreparedFactCopy> prepared,
  });

  /// Copy revisions (kind copied) [actorUserId] wrote within [window].
  Future<int> countRecentCopyRevisions({
    required String actorUserId,
    required Duration window,
  });

  /// The status, visibility and origin columns of [factCardId] when it
  /// belongs to [beaconId]; null otherwise.
  Future<FactOriginRef?> loadOriginRef({
    required String factCardId,
    required String beaconId,
  });

  /// One SELECT: each existing fact of [factCardIds] with its beacon kind,
  /// status, visibility and head revision; per head attachment, whether its
  /// image row exists, and per file attachment, its object's storage key.
  /// Missing ids are absent.
  Future<List<FactCopySource>> loadCopySources({
    required List<String> factCardIds,
  });

  /// The file attachment [attachmentId] of a copied fact's head revision,
  /// with its own stored object; null when there is none.
  Future<CopiedFactFile?> findCopiedFactFile({required String attachmentId});

  /// Requests and published, unexpired Posts [userId] authors, stewards or
  /// is admitted to (room_access 3) whose status is one of
  /// [writableStatuses], except
  /// [excludeBeaconId], most recently active first, at most [limit].
  Future<List<FactCopyDestinationRow>> listCopyDestinations({
    required String userId,
    required String excludeBeaconId,
    required List<int> writableStatuses,
    required int limit,
  });

  /// Live (active or corrected) copies in [beaconId] of
  /// [originFactCardIds], as origin id → copy id.
  Future<Map<String, String>> liveCopiesByOrigin({
    required String beaconId,
    required List<String> originFactCardIds,
  });

  Future<void> setVisibility({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required int visibility,
  });

  /// Replaces the fact text with [newText] (trimmed by the caller) when
  /// [baseRevisionSeq] is still current; one statement shared with
  /// [restoreRevision]. When [attachmentsJson] is non-null it becomes the
  /// new head snapshot (same shape as room `attachmentsJson`); when null on
  /// a text edit the previous head snapshot is copied. A change to either
  /// text or attachments is a real edit (not NoOp).
  Future<FactEditOutcome> editText({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required String newText,
    required int baseRevisionSeq,
    required Duration rateWindow,
    required int rateMax,
    required Duration quietWindow,
    String? attachmentsJson,
  });

  /// Restores the text (and attachment snapshot) of revision [fromSeq] as a
  /// new revision; both are read inside the statement, never from the client.
  Future<FactEditOutcome> restoreRevision({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required int fromSeq,
    required int baseRevisionSeq,
    required Duration rateWindow,
    required int rateMax,
    required Duration quietWindow,
  });

  /// Head revision `attachments_json` per fact id (`'[]'` when missing).
  Future<Map<String, String>> headAttachmentsJsonByFactIds(
    Iterable<String> factCardIds,
  );

  /// One SELECT: the attachments with [attachmentIds] found on any revision
  /// of [factCardId] in [beaconId], and the [imageIds] whose image row
  /// [actorUserId] authored.
  Future<FactEditAttachmentLookup> findEditAttachments({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required List<String> attachmentIds,
    required List<String> imageIds,
  });

  /// Attachment snapshot for a specific revision seq (`'[]'` when missing).
  Future<String> attachmentsJsonForRevision({
    required String factCardId,
    required int seq,
  });

  /// True only when this call unpinned the fact.
  Future<bool> remove({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
  });

  /// Plan R5 / §5.4: deletes a fact of a draft that [actorUserId] authors,
  /// with no chat line and no event. Throws `UnauthorizedException` unless
  /// the beacon is still a draft authored by [actorUserId]. `deleted` is
  /// true only when this call deleted the row; `fileKeys` are the storage
  /// keys of the copied files it owned, for the caller to remove after the
  /// commit.
  Future<({bool deleted, List<String> fileKeys})> deleteFromDraft({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
  });

  /// Fact timeline, newest first by `(createdAt, entryKey)`; [before] is the
  /// exclusive keyset cursor. Returns up to `limit + 1` rows (look-ahead).
  Future<List<BeaconFactHistoryEntry>> history({
    required String factCardId,
    required String beaconId,
    ({DateTime createdAt, String entryKey})? before,
    int limit = kFactHistoryPageSize,
  });
}
