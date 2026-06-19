/// Mirrors server `beacon_activity_event` visibility.
abstract final class BeaconActivityEventVisibilityBits {
  static const public = 0;
  static const room = 1;
}

/// Mirrors server `beacon_activity_event.type` (Phase 5+).
///
/// Two encodings share the `type` int:
/// - **Named bits** below (low values) for non-coordination-item events.
/// - **Coordination-item events** use `kind * 100 + eventKind` in the
///   [coordinationTypeMin]..[coordinationTypeMax] range, where `kind` is a
///   `CoordinationItemKind` value (1 plan, 2 ask, 3 blocker, 4 resolution;
///   5 promise is intentionally not surfaced in the activity log) and the
///   remainder is a `CoordinationItemEventKind` value. Decode via
///   `BeaconActivityEvent.coordinationKind` / `.coordinationEventKind`.
abstract final class BeaconActivityEventTypeBits {
  static const planUpdated = 1;
  static const factPinned = 2;
  static const blockerOpened = 10;
  static const blockerResolved = 11;
  static const needInfoOpened = 12;
  static const doneMarked = 13;
  static const factVisibilityChanged = 14;
  static const beaconPublished = 15;

  /// Inclusive lower bound of the `kind * 100 + eventKind` coordination range.
  static const coordinationTypeMin = 100;

  /// Exclusive upper bound (excludes promise = kind 5, i.e. 500+).
  static const coordinationTypeMax = 500;
}
