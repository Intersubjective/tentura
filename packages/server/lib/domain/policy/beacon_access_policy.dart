import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

/// Typed inputs for [BeaconAccessPolicy] (issue #146 architecture §2.1).
///
/// Context facts [isMemberOfImmediateParent] and [isMemberOfDescendant] are
/// live from m0171 (`beacon_ancestor` + `beacon_access_reasons` bits 64/128).
///
/// Budding B3 (m0242): under a Post parent ([parentIsPost]) contextChild is the
/// bud snapshot ([isBudObserver]) instead of [isMemberOfImmediateParent], and
/// contextAncestor never grants a Post ([isPost]).
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
    this.isPost = false,
    this.parentIsPost = false,
    this.isBudObserver = false,
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

  /// The target beacon is a Post (`kind = 1`).
  final bool isPost;

  /// The immediate parent is a Post (`kind = 1`).
  final bool parentIsPost;

  /// The viewer holds a `beacon_bud_observer` row for this beacon, the parent
  /// Post is live (not deleted / draft) and its author does not block them.
  final bool isBudObserver;
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
    final isContextChild = f.parentIsPost
        ? f.isBudObserver
        : f.isMemberOfImmediateParent;
    if (f.isPublished && isContextChild) {
      mask |= BeaconAccessReason.contextChild.bit;
    }
    if (f.isPublished && !f.isPost && f.isMemberOfDescendant) {
      mask |= BeaconAccessReason.contextAncestor.bit;
    }
    return mask;
  }

  static BeaconAccessLevel level(BeaconAccessFacts f) =>
      beaconAccessLevelFromReasons(reasons(f));
}
