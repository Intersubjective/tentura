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

  /// The viewer's `inbox_item.status` for [beaconId] (any context), or null
  /// when the Request never reached them.
  Future<int?> findStatus({
    required String userId,
    required String beaconId,
  });

  Future<void> setStatus({
    required String userId,
    required String beaconId,
    required int status,
    required String rejectionMessage,
  });

  /// Set recipient inbox status to closedBeforeResponse (3) when a forward is
  /// cancelled by the sender, but only if the item is still in needsMe (0).
  Future<void> markForwardCancelledForRecipient({
    required String beaconId,
    required String recipientId,
  });

  /// Pins [beaconId] in [userId]'s «Для вас» after an author invite: status
  /// 0 and `tombstone_dismissed_at` cleared. The forward-insert trigger keeps
  /// an existing row's status, so the invite re-pins explicitly. Tombstone
  /// rows (status 3/4) are immutable and stay as they are.
  Future<void> repinForAuthorInvite({
    required String userId,
    required String beaconId,
  });
}
