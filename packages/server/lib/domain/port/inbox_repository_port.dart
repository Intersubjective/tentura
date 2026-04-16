import 'package:tentura_server/domain/entity/inbox_item_entity.dart';

abstract class InboxRepositoryPort {
  Future<List<InboxItemEntity>> fetchByUserId(
    String userId, {
    String? context,
    int limit = 50,
    int offset = 0,
  });

  Future<List<String>> fetchRejectedUserIdsByBeacon(String beaconId);

  Future<List<String>> fetchWatchingUserIdsByBeacon(String beaconId);

  Future<void> applyTombstoneAfterWithdraw({
    required String userId,
    required String beaconId,
  });

  Future<void> upsertWatchingForSender({
    required String senderId,
    required String beaconId,
    String? context,
    bool touchForwardOrdering = true,
  });

  Future<void> setStatus({
    required String userId,
    required String beaconId,
    required int status,
    required String rejectionMessage,
  });
}
