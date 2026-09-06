import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_denial_code.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';

/// Typed inputs for effective admission (author/steward/admitted participant).
class BeaconEffectiveAdmissionFacts {
  const BeaconEffectiveAdmissionFacts({
    required this.isAuthor,
    required this.isSteward,
    required this.isAdmittedParticipant,
    required this.isBlockedByOwner,
  });

  final bool isAuthor;
  final bool isSteward;
  final bool isAdmittedParticipant;
  final bool isBlockedByOwner;
}

/// Facts for the parent→child one-edge grant.
class BeaconImmediateParentLinkFacts {
  const BeaconImmediateParentLinkFacts({
    required this.parentStatus,
    required this.viewerEffectivelyAdmittedToParent,
    required this.isBlockedByParentOwner,
  });

  final BeaconStatus parentStatus;
  final bool viewerEffectivelyAdmittedToParent;
  final bool isBlockedByParentOwner;
}

/// Facts for the child→parent one-edge grant.
class BeaconImmediateChildLinkFacts {
  const BeaconImmediateChildLinkFacts({
    required this.childStatus,
    required this.viewerEffectivelyAdmittedToChild,
    required this.isBlockedByChildOwner,
  });

  final BeaconStatus childStatus;
  final bool viewerEffectivelyAdmittedToChild;
  final bool isBlockedByChildOwner;
}

/// Parent-side capability inputs for list/create hints.
class BeaconHierarchyCapabilityFacts {
  const BeaconHierarchyCapabilityFacts({
    required this.admission,
    required this.parentStatus,
    required this.parentHasKnownOwner,
  });

  final BeaconEffectiveAdmissionFacts admission;
  final BeaconStatus parentStatus;
  final bool parentHasKnownOwner;
}

/// Parent-reference resolution inputs for child detail headers.
class BeaconParentReferenceFacts {
  const BeaconParentReferenceFacts({
    required this.hasParent,
    this.parentStatus,
    this.parentLinkedDetailAuthorized = false,
    this.parentBeaconId,
    this.parentTitle,
  });

  final bool hasParent;
  final BeaconStatus? parentStatus;
  final bool parentLinkedDetailAuthorized;
  final String? parentBeaconId;
  final String? parentTitle;
}

/// Pure hierarchy lifecycle, capability, and one-edge direction policy.
abstract final class BeaconHierarchyPolicy {
  BeaconHierarchyPolicy._();

  static bool hasEffectiveAdmission(BeaconEffectiveAdmissionFacts facts) {
    if (facts.isBlockedByOwner) {
      return false;
    }
    return facts.isAuthor ||
        facts.isSteward ||
        facts.isAdmittedParticipant;
  }

  /// One-edge grant: viewer is effectively admitted to the adjacent parent.
  ///
  /// The adjacent parent must be published (non-draft) and not deleted.
  /// Closed/cancelled parents may still grant the link read.
  static bool isAdmittedToImmediateParent(
    BeaconImmediateParentLinkFacts facts,
  ) {
    if (facts.isBlockedByParentOwner) {
      return false;
    }
    if (facts.parentStatus == BeaconStatus.draft ||
        facts.parentStatus == BeaconStatus.deleted) {
      return false;
    }
    return facts.viewerEffectivelyAdmittedToParent;
  }

  /// One-edge grant: viewer is effectively admitted to the adjacent child.
  ///
  /// The adjacent child must be published (non-draft) and not deleted.
  static bool isAdmittedToImmediatePublishedChild(
    BeaconImmediateChildLinkFacts facts,
  ) {
    if (facts.isBlockedByChildOwner) {
      return false;
    }
    if (facts.childStatus == BeaconStatus.draft ||
        facts.childStatus == BeaconStatus.deleted) {
      return false;
    }
    return facts.viewerEffectivelyAdmittedToChild;
  }

  static BeaconHierarchyCapabilities resolveCapabilities(
    BeaconHierarchyCapabilityFacts facts,
  ) {
    if (!hasEffectiveAdmission(facts.admission)) {
      return const BeaconHierarchyCapabilities(
        canListChildren: false,
        canCreateChild: false,
        denialCode: BeaconHierarchyDenialCode.notAdmitted,
      );
    }
    if (facts.parentStatus == BeaconStatus.draft) {
      return const BeaconHierarchyCapabilities(
        canListChildren: false,
        canCreateChild: false,
        denialCode: BeaconHierarchyDenialCode.parentDraft,
      );
    }
    if (facts.parentStatus == BeaconStatus.deleted) {
      return const BeaconHierarchyCapabilities(
        canListChildren: false,
        canCreateChild: false,
        denialCode: BeaconHierarchyDenialCode.parentDeleted,
      );
    }
    if (facts.admission.isBlockedByOwner) {
      return const BeaconHierarchyCapabilities(
        canListChildren: false,
        canCreateChild: false,
        denialCode: BeaconHierarchyDenialCode.blocked,
      );
    }

    final canList = true;
    final canCreate = facts.parentStatus.allowsCoordination;
    BeaconHierarchyDenialCode? denial;
    if (!canCreate) {
      denial = facts.parentStatus.isTerminal
          ? BeaconHierarchyDenialCode.parentTerminal
          : BeaconHierarchyDenialCode.parentNotCoordinatable;
    }

    return BeaconHierarchyCapabilities(
      canListChildren: canList,
      canCreateChild: canCreate,
      denialCode: denial,
    );
  }

  static BeaconParentReference resolveParentReference(
    BeaconParentReferenceFacts facts,
  ) {
    if (!facts.hasParent) {
      return BeaconParentReference.none;
    }
    if (facts.parentStatus == BeaconStatus.deleted ||
        !facts.parentLinkedDetailAuthorized) {
      return BeaconParentReference.unavailable;
    }
    return BeaconParentReference(
      state: BeaconParentReferenceState.available,
      beaconId: facts.parentBeaconId,
      title: facts.parentTitle,
    );
  }

  static BeaconHierarchyChildGroup? publicChildGroupForStatus(
    BeaconStatus status,
  ) {
    if (status == BeaconStatus.draft) {
      return null;
    }
    if (status == BeaconStatus.deleted) {
      return BeaconHierarchyChildGroup.deleted;
    }
    if (status.isFinished) {
      return BeaconHierarchyChildGroup.finished;
    }
    if (status.isOpenFamily || status == BeaconStatus.reviewOpen) {
      return BeaconHierarchyChildGroup.active;
    }
    return null;
  }

  /// Whether a committed status transition should record a hierarchy lifecycle
  /// event. Draft hard-delete and local reopen paths are excluded.
  static bool isHierarchyLifecycleNoticeEligible({
    required BeaconStatus from,
    required BeaconStatus to,
    BeaconStatusTransitionReason? reason,
  }) {
    if (from == BeaconStatus.draft) {
      return false;
    }
    if (reason == BeaconStatusTransitionReason.reopenedFromReview) {
      return false;
    }

    final transition = validateBeaconStatusTransition(
      from: from,
      to: to,
      reason: reason,
    );
    if (transition.verdict == BeaconStatusTransitionVerdict.noop) {
      return false;
    }

    return to == BeaconStatus.reviewOpen ||
        to == BeaconStatus.closed ||
        to == BeaconStatus.cancelled ||
        to == BeaconStatus.deleted;
  }

  static BeaconHierarchyDeliveryDirection deliveryDirectionForTarget({
    required bool targetIsImmediateParentOfSource,
  }) {
    if (targetIsImmediateParentOfSource) {
      return BeaconHierarchyDeliveryDirection.child;
    }
    return BeaconHierarchyDeliveryDirection.ancestor;
  }

  static bool canReadDeletedChildTombstoneCard({
    required bool viewerAdmittedToImmediateParent,
    required bool isBlockedByKnownChildOwner,
  }) {
    return viewerAdmittedToImmediateParent && !isBlockedByKnownChildOwner;
  }
}
