import 'package:meta/meta.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

/// PG NOTIFY `entity` values for beacon room–related tables, mapped for client
/// invalidation routing over the V2 `entity_changes` WebSocket path.
enum BeaconRoomEntityType {
  roomMessage,
  roomReaction,
  roomPoll,
  activityEvent,
  participant,
  factCard,
  coordinationItem,
  roomSeen,
}

/// One debounced invalidation for the current user's beacon room slice.
///
/// A plain class (not a record) so Flutter web/DDC RTI does not mis-classify
/// the stream event when enums cross JS-interop JSON boundaries.
@immutable
final class BeaconRoomInvalidation {
  const BeaconRoomInvalidation({
    required this.beaconId,
    required this.entityType,
  });

  final String beaconId;
  final BeaconRoomEntityType entityType;

  /// Adapts the shared realtime boundary to the room projection contract.
  static BeaconRoomInvalidation? fromRealtimeChange(
    RealtimeEntityChange change,
  ) {
    final entityType = switch (change.kind) {
      RealtimeEntityKind.roomMessage => BeaconRoomEntityType.roomMessage,
      RealtimeEntityKind.roomReaction => BeaconRoomEntityType.roomReaction,
      RealtimeEntityKind.roomPoll => BeaconRoomEntityType.roomPoll,
      RealtimeEntityKind.activityEvent => BeaconRoomEntityType.activityEvent,
      RealtimeEntityKind.participant => BeaconRoomEntityType.participant,
      RealtimeEntityKind.factCard => BeaconRoomEntityType.factCard,
      RealtimeEntityKind.coordinationItem =>
        BeaconRoomEntityType.coordinationItem,
      RealtimeEntityKind.roomSeen => BeaconRoomEntityType.roomSeen,
      _ => null,
    };
    return entityType == null
        ? null
        : BeaconRoomInvalidation(
            beaconId: change.aggregateId,
            entityType: entityType,
          );
  }

  @override
  bool operator ==(Object other) =>
      other is BeaconRoomInvalidation &&
      beaconId == other.beaconId &&
      entityType == other.entityType;

  @override
  int get hashCode => Object.hash(beaconId, entityType);
}
