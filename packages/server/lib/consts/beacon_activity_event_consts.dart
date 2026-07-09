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
  static const factVisibilityChanged = 14;
  static const beaconPublished = 15;
  static const beaconLifecycleChanged = 16;
  static const participantRemoved = 17;
}

/// [`beacon_activity_event.diff.reason`] for type [BeaconActivityEventTypeBits.beaconLifecycleChanged].
abstract final class BeaconLifecycleChangeReason {
  static const reviewWindowOpened = 'reviewWindowOpened';
  static const directClose = 'directClose';
  static const authorCloseNow = 'authorCloseNow';
  static const reviewExpired = 'reviewExpired';
  static const reopenedFromReview = 'reopenedFromReview';
  static const cancelled = 'cancelled';
  static const deleted = 'deleted';
  static const needsMoreHelp = 'needsMoreHelp';
  static const enoughHelp = 'enoughHelp';
  static const neutralOpen = 'neutralOpen';
}

/// Matches client [`BeaconActivityEvent.isCoordinationLogEvent`] / Log tab filter.
bool isCoordinationLogEventType(int type) {
  if (type >= 100 && type < 500) return true;
  return switch (type) {
    BeaconActivityEventTypeBits.planUpdated => true,
    BeaconActivityEventTypeBits.factPinned => true,
    BeaconActivityEventTypeBits.blockerOpened => true,
    BeaconActivityEventTypeBits.blockerResolved => true,
    BeaconActivityEventTypeBits.needInfoOpened => true,
    BeaconActivityEventTypeBits.doneMarked => true,
    BeaconActivityEventTypeBits.factVisibilityChanged => true,
    BeaconActivityEventTypeBits.beaconPublished => true,
    BeaconActivityEventTypeBits.beaconLifecycleChanged => true,
    _ => false,
  };
}
