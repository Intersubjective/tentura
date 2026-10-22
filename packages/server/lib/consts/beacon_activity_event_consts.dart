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
  static const participantJoined = 18;
  static const factEdited = 19;
  static const factRemoved = 20;
  static const planRevised = 21;
  static const planStepDone = 22;
  static const planCantMake = 23;
  static const planCopied = 24;

  /// A helper withdrew and left the room (B084); pairs with the
  /// `participantLeft` chat line via `source_message_id`.
  static const participantLeft = 25;

  /// #528: the next step or the title changed. `diff` is
  /// `{field, from, to}` ([RequestEditField]); pairs with the
  /// `requestEdited` chat line via `source_message_id`.
  static const requestEdited = 26;
}

/// [`beacon_activity_event.diff.field`] / `requestEdited` line payload
/// `field` (#528): which Request text changed.
abstract final class RequestEditField {
  static const nextStep = 'nextStep';
  static const title = 'title';

  static const all = {nextStep, title};
}

/// [`beacon_activity_event.diff.reason`] for type [BeaconActivityEventTypeBits.beaconLifecycleChanged].
abstract final class BeaconLifecycleChangeReason {
  static const closureOpened = 'closureOpened';
  static const directClose = 'directClose';
  static const authorCloseNow = 'authorCloseNow';
  static const closureExpired = 'closureExpired';
  static const reopenedFromReview = 'reopenedFromReview';
  static const cancelled = 'cancelled';
  static const deleted = 'deleted';
  static const needsMoreHelp = 'needsMoreHelp';
  static const enoughHelp = 'enoughHelp';
  static const neutralOpen = 'neutralOpen';

  /// #380: the author extended the final check; status stays reviewOpen and
  /// `diff.closesAt` carries the new end date. Room visibility only.
  static const closureExtended = 'closureExtended';
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
    BeaconActivityEventTypeBits.factEdited => true,
    BeaconActivityEventTypeBits.factRemoved => true,
    BeaconActivityEventTypeBits.planRevised => true,
    BeaconActivityEventTypeBits.planStepDone => true,
    BeaconActivityEventTypeBits.planCantMake => true,
    BeaconActivityEventTypeBits.planCopied => true,
    BeaconActivityEventTypeBits.requestEdited => true,
    _ => false,
  };
}
