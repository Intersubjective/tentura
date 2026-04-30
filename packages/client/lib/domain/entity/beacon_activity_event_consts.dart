/// Mirrors server `beacon_activity_event` visibility.
abstract final class BeaconActivityEventVisibilityBits {
  static const public = 0;
  static const room = 1;
}

/// Mirrors server `beacon_activity_event.type` (Phase 5+).
abstract final class BeaconActivityEventTypeBits {
  static const planUpdated = 1;
  static const factPinned = 2;
  static const blockerOpened = 10;
  static const blockerResolved = 11;
  static const needInfoOpened = 12;
  static const doneMarked = 13;
  static const factVisibilityChanged = 14;
}
