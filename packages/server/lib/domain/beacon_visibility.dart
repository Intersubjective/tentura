import 'package:tentura_root/domain/entity/beacon_status.dart';

/// Typed inputs for [BeaconVisibility.canReadContent].
class BeaconContentVisibilityFacts {
  const BeaconContentVisibilityFacts({
    required this.status,
    required this.isAuthor,
    required this.hasActiveForwardEdgeAsRecipient,
    required this.isRoomAdmittedOrSteward,
    required this.isActiveHelpOfferer,
    required this.isMutualFriendOfAuthor,
  });

  final BeaconStatus status;
  final bool isAuthor;
  final bool hasActiveForwardEdgeAsRecipient;
  final bool isRoomAdmittedOrSteward;
  final bool isActiveHelpOfferer;
  final bool isMutualFriendOfAuthor;
}

/// Typed inputs for [BeaconVisibility.canReadInvolvement].
class BeaconInvolvementVisibilityFacts {
  const BeaconInvolvementVisibilityFacts({
    required this.contentFacts,
    required this.isOnActiveForwardEdge,
    required this.isActiveHelpOfferer,
    required this.isRoomAdmittedOrSteward,
    required this.isMutualFriendOfAuthor,
  });

  final BeaconContentVisibilityFacts contentFacts;
  final bool isOnActiveForwardEdge;
  final bool isActiveHelpOfferer;
  final bool isRoomAdmittedOrSteward;
  final bool isMutualFriendOfAuthor;

  bool get isAuthor => contentFacts.isAuthor;
}

/// Typed inputs for [BeaconVisibility.canReadTombstone].
class BeaconTombstoneFacts {
  const BeaconTombstoneFacts({
    required this.status,
    required this.isAuthor,
    required this.hasInboxItem,
    required this.hasForwardEdgeHistory,
    required this.hasHelpOfferHistory,
    required this.hasParticipantRow,
  });

  final BeaconStatus status;
  final bool isAuthor;
  final bool hasInboxItem;
  final bool hasForwardEdgeHistory;
  final bool hasHelpOfferHistory;
  final bool hasParticipantRow;
}

/// Typed inputs for [BeaconVisibility.canPreviewInvite].
class BeaconInvitePreviewFacts {
  const BeaconInvitePreviewFacts({
    required this.invitationExists,
    required this.invitationConsumed,
    required this.invitationExpired,
    required this.hasBeaconId,
    required this.beaconStatus,
    required this.beaconAllowsForward,
    required this.issuerCanReadContent,
    required this.issuerCanForward,
  });

  final bool invitationExists;
  final bool invitationConsumed;
  final bool invitationExpired;
  final bool hasBeaconId;
  final BeaconStatus beaconStatus;
  final bool beaconAllowsForward;
  final bool issuerCanReadContent;
  final bool issuerCanForward;
}

/// Pure relationship-scoped beacon visibility policy (ADR 0008).
abstract final class BeaconVisibility {
  BeaconVisibility._();

  /// Normal beacon content read — never authorizes deleted rows or drafts
  /// for non-authors. MeritRank is not part of this predicate.
  static bool canReadContent(BeaconContentVisibilityFacts facts) {
    if (facts.status == BeaconStatus.draft) {
      return facts.isAuthor;
    }
    if (facts.status == BeaconStatus.deleted) {
      return false;
    }
    if (facts.isAuthor) {
      return true;
    }
    return facts.hasActiveForwardEdgeAsRecipient ||
        facts.isRoomAdmittedOrSteward ||
        facts.isActiveHelpOfferer ||
        facts.isMutualFriendOfAuthor;
  }

  /// Involvement graph read — requires content visibility plus involved set
  /// or author's mutual friends. Deleted beacons return false.
  static bool canReadInvolvement(BeaconInvolvementVisibilityFacts facts) {
    if (!canReadContent(facts.contentFacts)) {
      return false;
    }
    return facts.isAuthor ||
        facts.isOnActiveForwardEdge ||
        facts.isActiveHelpOfferer ||
        facts.isRoomAdmittedOrSteward ||
        facts.isMutualFriendOfAuthor;
  }

  /// Generic deleted-state UX only — never authorizes normal content columns.
  static bool canReadTombstone(BeaconTombstoneFacts facts) {
    if (facts.status != BeaconStatus.deleted) {
      return false;
    }
    return facts.isAuthor ||
        facts.hasInboxItem ||
        facts.hasForwardEdgeHistory ||
        facts.hasHelpOfferHistory ||
        facts.hasParticipantRow;
  }

  /// Invite-code preview — separate from row-read predicate.
  static bool canPreviewInvite(BeaconInvitePreviewFacts facts) {
    if (!facts.invitationExists ||
        facts.invitationConsumed ||
        facts.invitationExpired ||
        !facts.hasBeaconId) {
      return false;
    }
    if (facts.beaconStatus == BeaconStatus.draft ||
        facts.beaconStatus == BeaconStatus.deleted) {
      return false;
    }
    if (!facts.beaconAllowsForward) {
      return false;
    }
    return facts.issuerCanReadContent && facts.issuerCanForward;
  }
}
