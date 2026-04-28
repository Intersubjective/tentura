/// [`beacon_activity_event.visibility`]: public vs room-only consumers.
abstract final class BeaconActivityEventVisibilityBits {
  static const public = 0;
  static const room = 1;
}

/// [`beacon_activity_event.type`] — coarse activity taxonomy (Phase 5).
abstract final class BeaconActivityEventTypeBits {
  static const planUpdated = 1;
  static const factPinned = 2;
  static const blockerOpened = 10;
  static const blockerResolved = 11;
  static const needInfoOpened = 12;
  static const doneMarked = 13;
}
