import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';
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

  Future<String?> latestPublicFactSnippet(String beaconId);

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

  Future<void> correct({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required String newText,
  });

  Future<void> remove({
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
