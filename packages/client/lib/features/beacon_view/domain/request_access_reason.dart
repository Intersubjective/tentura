import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/entity/beacon.dart';

/// Whether the viewer sees [beacon] only because of a related Request or
/// Post (parent or child). Applied and forwarded access are explained
/// elsewhere, so they take priority.
bool requestAccessViaRelated(Beacon beacon) {
  if (beacon.accessLevel != BeaconAccessLevel.observer) return false;
  final reasons = BeaconAccessReason.decode(beacon.accessReasons);
  if (reasons.contains(BeaconAccessReason.applied) ||
      reasons.contains(BeaconAccessReason.forwarded)) {
    return false;
  }
  return reasons.contains(BeaconAccessReason.contextChild) ||
      reasons.contains(BeaconAccessReason.contextAncestor);
}

/// [requestAccessViaRelated] through the Request's lineage parent (the
/// contextChild reason) — for a Request budded from a Post, its members
/// (#724).
bool requestAccessViaParent(Beacon beacon) =>
    requestAccessViaRelated(beacon) &&
    BeaconAccessReason.decode(
      beacon.accessReasons,
    ).contains(BeaconAccessReason.contextChild) &&
    (beacon.lineageParentBeaconId?.trim().isNotEmpty ?? false);
