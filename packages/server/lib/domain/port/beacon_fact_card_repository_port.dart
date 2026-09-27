import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_outcome.dart';
import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';

abstract class BeaconFactCardRepositoryPort {
  /// One SELECT: beacon status, room use (author, steward or admitted) and
  /// `beacon_can_read_content`. `exists` is false for an unknown beacon.
  Future<BeaconFactRoomAccess> loadRoomAccess({
    required String beaconId,
    required String userId,
  });

  /// Non-removed facts with pinner / last editor titles joined; room-only
  /// facts only when [includeRoomOnly].
  Future<List<BeaconFactCardEntity>> listForBeacon({
    required String beaconId,
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

  /// Fact timeline, newest first by `(createdAt, entryKey)`; [before] is the
  /// exclusive keyset cursor. Returns up to `limit + 1` rows (look-ahead).
  Future<List<BeaconFactHistoryEntry>> history({
    required String factCardId,
    ({DateTime createdAt, String entryKey})? before,
    int limit = kFactHistoryPageSize,
  });
}
