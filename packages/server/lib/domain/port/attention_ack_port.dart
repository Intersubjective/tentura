import 'package:tentura_server/domain/attention/attention_models.dart';

abstract interface class AttentionAckPort {
  Future<int> markSeen({
    required String accountId,
    required List<String> ids,
  });

  Future<int> markUnseen({
    required String accountId,
    required List<String> ids,
  });

  /// #601: *Mark unread* on an Updates item — un-clears (`cleared_at`,
  /// `clear_reason`, `cleared_by_operation_id` back to NULL) and un-reads
  /// (`seen_at` NULL) the caller's own visible optional receipts, so a
  /// cleared item returns under Unread. Live obligations (`requires_action`)
  /// are never cleared and are not touched. Unlike [markUnseen] it does not
  /// defer to an unseen sibling sharing the `dedup_key`.
  Future<int> markUnread({
    required String accountId,
    required List<String> ids,
  });

  Future<int> markAllSeen(String accountId, {AttentionSurface? surface});

  Future<int> markSeenForBeacon({
    required String accountId,
    required String beaconId,
  });

  // DORMANT(item-threads): per-item-thread attention read watermark bridge.
  // Rooms are General-only (guard: beacon_room_message_general_only_guard, DiscussionScopeDisabledException); thread_item_id is always NULL for new rows. Do not design for this path. See #192.
  Future<int> bridgeRoomWatermark({
    required String accountId,
    required String beaconId,
    required String? threadItemId,
    required DateTime lastSeenAt,
  });
}
