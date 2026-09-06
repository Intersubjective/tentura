/// Persisted `beacon_child_commands.result_state` values.
abstract final class BeaconChildCommandResultState {
  static const created = 0;
  static const replayed = 1;
  static const alreadyPromoted = 2;
}

/// Persisted `beacon_hierarchy_deliveries.direction` wire values.
abstract final class BeaconHierarchyDeliveryDirectionWire {
  static const ancestor = 'ancestor';
  static const child = 'child';
}

/// Persisted `beacon_hierarchy_deliveries.state` wire values.
abstract final class BeaconHierarchyDeliveryStateWire {
  static const pending = 'pending';
  static const leased = 'leased';
  static const delivered = 'delivered';
  static const suppressed = 'suppressed';
  static const parked = 'parked';
}

/// `beacon_room_message.system_message_kind` discriminator for system-authored rows.
abstract final class BeaconRoomSystemMessageKind {
  static const hierarchyLifecycle = 1;
  static const childCreated = 2;
}

/// Opaque hierarchy list cursor version.
const kBeaconHierarchyCursorVersion = 1;
