// Pure Dart (no package imports): server tests import this file to pin both
// ends of the reader's private read-cursor contract.

/// The `entity_changes` notification `markBeaconRoomSeen` publishes once it
/// persists [readerId]'s cursor: [event] is `insert` for the reader's first
/// read of a scope and `update` afterwards.
///
/// room_seen_scoped_watermark_hint_pg_test checks the real trigger against it.
Map<String, dynamic> roomSeenReadCursorNotification({
  required String readerId,
  required String beaconId,
  required DateTime at,
  required String event,
  String? threadItemId,
}) => {
  'entity': 'room_seen',
  'id': beaconId,
  'event': event,
  'actor_user_id': readerId,
  'user_ids': [readerId],
  'thread_item_id': threadItemId,
  'last_seen_at': at.toUtc().toIso8601String(),
};

/// The frame production websocket fan-out sends to every signed-in session of
/// [readerId] for [roomSeenReadCursorNotification], with actor echo on or off.
///
/// websocket_realtime_protocol_test and the room_seen PG test pin this against
/// the server's actual fan-out, so client tests feed it instead of building
/// their own room_seen frames.
Map<String, dynamic> roomSeenReadCursorFrame({
  required String readerId,
  required String beaconId,
  required DateTime at,
  required String event,
  String? threadItemId,
}) => {
  'type': 'subscription',
  'path': 'entity_changes',
  'payload': {
    'entity': 'room_seen',
    'id': beaconId,
    'event': event,
    'actor_user_id': readerId,
    'thread_item_id': threadItemId,
    'last_seen_at': at.toUtc().toIso8601String(),
  },
};
