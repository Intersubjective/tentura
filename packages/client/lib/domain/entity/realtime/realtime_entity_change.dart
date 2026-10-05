import 'package:freezed_annotation/freezed_annotation.dart';

import 'realtime_room_message_paint.dart';
import 'realtime_seen_peer.dart';

part 'realtime_entity_change.freezed.dart';

/// Closed set of server-owned state that can invalidate a client projection.
enum RealtimeEntityKind {
  beacon,
  forward,
  helpOffer,
  inboxItem,
  roomMessage,
  roomReaction,
  roomPoll,
  roomBaton,
  participant,
  factCard,
  activityEvent,
  coordinationItem,
  capability,
  contact,
  roomSeen,
  roomSeenPeer,
  peopleSeen,
  relationship,
  profile,
  notification,
  beaconHierarchy,
  constellationAnchor,
  inviteSeedPrompt,
  ;

  /// Maps the closed WebSocket protocol vocabulary into a domain kind.
  static RealtimeEntityKind? fromWire(Object? raw) => switch (raw) {
    'beacon' => RealtimeEntityKind.beacon,
    'forward' => RealtimeEntityKind.forward,
    'help_offer' => RealtimeEntityKind.helpOffer,
    'inbox_item' => RealtimeEntityKind.inboxItem,
    'room_message' => RealtimeEntityKind.roomMessage,
    'room_reaction' => RealtimeEntityKind.roomReaction,
    'room_poll' => RealtimeEntityKind.roomPoll,
    'room_baton' => RealtimeEntityKind.roomBaton,
    'participant' => RealtimeEntityKind.participant,
    'fact_card' => RealtimeEntityKind.factCard,
    'activity_event' => RealtimeEntityKind.activityEvent,
    'coordination_item' => RealtimeEntityKind.coordinationItem,
    'capability' || 'person_capability_event' => RealtimeEntityKind.capability,
    'contact' => RealtimeEntityKind.contact,
    'room_seen' => RealtimeEntityKind.roomSeen,
    'room_seen_peer' => RealtimeEntityKind.roomSeenPeer,
    'people_seen' => RealtimeEntityKind.peopleSeen,
    'relationship' => RealtimeEntityKind.relationship,
    'profile' => RealtimeEntityKind.profile,
    'notification' => RealtimeEntityKind.notification,
    'beacon_hierarchy' => RealtimeEntityKind.beaconHierarchy,
    'constellation_anchor' => RealtimeEntityKind.constellationAnchor,
    'invite_seed_prompt' => RealtimeEntityKind.inviteSeedPrompt,
    _ => null,
  };
}

enum RealtimeOperation { insert, update, delete }

/// The signal identifies server truth; it never carries derived projection data.
enum RealtimeChangeSource { serverInvalidation }

@freezed
abstract class RealtimeEntityChange with _$RealtimeEntityChange {
  const factory RealtimeEntityChange({
    required RealtimeEntityKind kind,
    required String aggregateId,
    required RealtimeOperation operation,
    required RealtimeChangeSource source,
    String? actorUserId,
  /// Child row id from NOTIFY extras (e.g. `message_id` for room messages).
    String? childId,
  /// Validated plain-text insert paint from WS `payload.message`.
    RealtimeRoomMessagePaint? roomMessagePaint,
  /// Peer read cursor from WS `seen_user_id` / `last_seen_at` extras.
    RealtimeSeenPeer? seenPeer,
  /// Author/steward People-surface watermark from WS `people_seen` `last_seen_at`.
    DateTime? peopleSeenAt,
  }) = _RealtimeEntityChange;
}
