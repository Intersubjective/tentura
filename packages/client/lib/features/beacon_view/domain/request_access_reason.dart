import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/entity/beacon.dart';

/// Whether the viewer sees [beacon] only through a related Request.
/// Applied and forwarded access take priority.
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

/// Whether the related Request is the immediate parent of [beacon].
bool requestAccessViaParent(Beacon beacon) =>
    requestAccessViaRelated(beacon) &&
    BeaconAccessReason.decode(
      beacon.accessReasons,
    ).contains(BeaconAccessReason.contextChild);
