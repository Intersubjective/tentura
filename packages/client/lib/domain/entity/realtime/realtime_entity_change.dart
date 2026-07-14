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
  blocker,
  activityEvent,
  coordinationItem,
  capability,
  contact,
  roomSeen,
  relationship,
  profile,
  notification,
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
