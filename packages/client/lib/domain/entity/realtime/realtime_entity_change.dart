import 'package:freezed_annotation/freezed_annotation.dart';

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
  participant,
  factCard,
  activityEvent,
  coordinationItem,
  capability,
  contact,
  roomSeen,
  relationship,
  profile,
  notification,
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
    'participant' => RealtimeEntityKind.participant,
    'fact_card' => RealtimeEntityKind.factCard,
    'activity_event' => RealtimeEntityKind.activityEvent,
    'coordination_item' => RealtimeEntityKind.coordinationItem,
    'capability' || 'person_capability_event' => RealtimeEntityKind.capability,
    'contact' => RealtimeEntityKind.contact,
    'room_seen' => RealtimeEntityKind.roomSeen,
    'relationship' => RealtimeEntityKind.relationship,
    'profile' => RealtimeEntityKind.profile,
    'notification' => RealtimeEntityKind.notification,
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
  }) = _RealtimeEntityChange;
}
