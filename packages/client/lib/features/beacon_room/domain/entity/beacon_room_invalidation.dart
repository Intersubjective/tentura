import 'package:meta/meta.dart';

/// PG NOTIFY `entity` values for beacon room–related tables, mapped for client
/// invalidation routing over the V2 `entity_changes` WebSocket path.
enum BeaconRoomEntityType {
  roomMessage,
  roomReaction,
  roomPoll,
  activityEvent,
  participant,
  factCard,
  blocker,
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

  @override
  bool operator ==(Object other) =>
      other is BeaconRoomInvalidation &&
      beaconId == other.beaconId &&
      entityType == other.entityType;

  @override
  int get hashCode => Object.hash(beaconId, entityType);
}
