import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';

abstract class BeaconFactCardRepositoryPort {
  Future<BeaconFactCardEntity?> findNonRemovedBySourceMessage({
    required String beaconId,
    required String sourceMessageId,
  });

  Future<List<BeaconFactCardEntity>> listForBeacon(String beaconId);

  Future<String?> latestPublicFactSnippet(String beaconId);

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
