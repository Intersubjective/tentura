import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

/// Typed inputs for [BeaconAccessPolicy] (issue #146 architecture §2.1).
///
/// Phase-1 contract: callers pass `false` for [isMemberOfImmediateParent] and
/// [isMemberOfDescendant] until T09 wires the hierarchy-context SQL. Passing
/// `true` before then has no live caller and only affects this pure
/// function's output.
class BeaconAccessFacts {
  const BeaconAccessFacts({
    required this.status,
    required this.isBlocked,
    required this.isAuthor,
    required this.isSteward,
    required this.isAdmitted,
    required this.hasActiveForwardEdgeAsRecipient,
    required this.isActiveHelpOfferer,
    required this.isDiscoverable,
    required this.isPublished,
    required this.isTrustVisibleWithAuthor,
    required this.isMemberOfImmediateParent,
    required this.isMemberOfDescendant,
  });

  final BeaconStatus status;
  final bool isBlocked;
  final bool isAuthor;
  final bool isSteward;
  final bool isAdmitted;
  final bool hasActiveForwardEdgeAsRecipient;
  final bool isActiveHelpOfferer;
  final bool isDiscoverable;
  final bool isPublished;
  final bool isTrustVisibleWithAuthor;
  final bool isMemberOfImmediateParent;
  final bool isMemberOfDescendant;
}

/// Pure viewer access policy: reason bitmask and derived level.
abstract final class BeaconAccessPolicy {
  BeaconAccessPolicy._();

  static int reasons(BeaconAccessFacts f) {
    if (f.isBlocked) {
      return 0;
    }
    if (f.status == BeaconStatus.draft) {
      return f.isAuthor ? BeaconAccessReason.author.bit : 0;
    }
    if (f.status == BeaconStatus.deleted) {
      return 0;
    }
    var mask = 0;
    if (f.isAuthor) mask |= BeaconAccessReason.author.bit;
    if (f.isSteward) mask |= BeaconAccessReason.steward.bit;
    if (f.isAdmitted) mask |= BeaconAccessReason.admitted.bit;
    if (f.hasActiveForwardEdgeAsRecipient) {
      mask |= BeaconAccessReason.forwarded.bit;
    }
    if (f.isActiveHelpOfferer) mask |= BeaconAccessReason.applied.bit;
    if (f.isDiscoverable &&
        f.isPublished &&
        f.status.isOpenFamily &&
        f.isTrustVisibleWithAuthor) {
      mask |= BeaconAccessReason.discovered.bit;
    }
    if (f.isPublished && f.isMemberOfImmediateParent) {
      mask |= BeaconAccessReason.contextChild.bit;
    }
    if (f.isPublished && f.isMemberOfDescendant) {
      mask |= BeaconAccessReason.contextAncestor.bit;
    }
    return mask;
  }

  static BeaconAccessLevel level(BeaconAccessFacts f) =>
      beaconAccessLevelFromReasons(reasons(f));
}
