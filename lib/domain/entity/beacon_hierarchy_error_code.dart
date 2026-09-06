/// Wire-stable hierarchy error identifiers mapped in later tasks.
enum BeaconHierarchyErrorCode {
  beaconChildCreateForbidden,
  beaconParentNotCoordinatable,
  beaconPromotionSourceInvalid,
  beaconSourceAlreadyPromoted,
  beaconChildCommandConflict,
  beaconChildCommandGone,
  beaconHierarchyCursorInvalid,
  discussionScopeDisabled,
  coordinationKindDisabled,
}

extension BeaconHierarchyErrorCodeWire on BeaconHierarchyErrorCode {
  String get wireName => switch (this) {
        BeaconHierarchyErrorCode.beaconChildCreateForbidden =>
          'BEACON_CHILD_CREATE_FORBIDDEN',
        BeaconHierarchyErrorCode.beaconParentNotCoordinatable =>
          'BEACON_PARENT_NOT_COORDINATABLE',
        BeaconHierarchyErrorCode.beaconPromotionSourceInvalid =>
          'BEACON_PROMOTION_SOURCE_INVALID',
        BeaconHierarchyErrorCode.beaconSourceAlreadyPromoted =>
          'BEACON_SOURCE_ALREADY_PROMOTED',
        BeaconHierarchyErrorCode.beaconChildCommandConflict =>
          'BEACON_CHILD_COMMAND_CONFLICT',
        BeaconHierarchyErrorCode.beaconChildCommandGone =>
          'BEACON_CHILD_COMMAND_GONE',
        BeaconHierarchyErrorCode.beaconHierarchyCursorInvalid =>
          'BEACON_HIERARCHY_CURSOR_INVALID',
        BeaconHierarchyErrorCode.discussionScopeDisabled =>
          'DISCUSSION_SCOPE_DISABLED',
        BeaconHierarchyErrorCode.coordinationKindDisabled =>
          'COORDINATION_KIND_DISABLED',
      };
}
