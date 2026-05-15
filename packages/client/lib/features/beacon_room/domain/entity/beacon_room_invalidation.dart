/// PG NOTIFY `entity` values for beacon room–related tables, mapped for client
/// invalidation routing over the V2 `entity_changes` WebSocket path.
enum BeaconRoomEntityType {
  roomMessage,
  activityEvent,
  participant,
  factCard,
  blocker,
  coordinationItem,
  coordinationItemMessage,
}

/// One debounced invalidation for the current user's beacon room slice.
typedef BeaconRoomInvalidation = ({
  String beaconId,
  BeaconRoomEntityType entityType,
});
