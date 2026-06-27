import 'package:tentura_root/domain/entity/beacon_status.dart';

/// Derived display phase (not persisted).
enum BeaconDisplayPhase {
  blocked,
  wrappingUp,
  needsMoreHelp,
  enoughHelpInMotion,
  offersAwaitingAuthor,
  coordinating,
  lookingForHelpers,
  closed,
  cancelled,
  draft,
  openFloor,
}

enum BeaconDisplayTier {
  coordination,
  public,
}

enum BeaconDisplaySlot2Kind {
  blockerNeedsClearing,
  courtAuthor,
  reviewCountdown,
  freshness,
  noOffersYet,
  lifecycleEndedAt,
  none,
}

enum BeaconDisplayPrimaryAction {
  resolveBlocker,
  reviewOffers,
  forward,
  offerHelp,
  reviewContributions,
  none,
}

class BeaconDisplayStatusInput {
  const BeaconDisplayStatusInput({
    required this.status,
    required this.tier,
    this.helpOfferCount = 0,
    this.hasOpenBlocker = false,
    this.hasUnreviewedOffers = false,
    this.hasOpenRoomAsks = false,
    this.reviewClosesAt,
    this.reviewWindowStatus,
    this.updatedAt,
    this.lastActivityAt,
  });

  final BeaconStatus status;
  final BeaconDisplayTier tier;
  final int helpOfferCount;
  final bool hasOpenBlocker;
  final bool hasUnreviewedOffers;
  final bool hasOpenRoomAsks;
  final DateTime? reviewClosesAt;
  final int? reviewWindowStatus;
  final DateTime? updatedAt;
  final DateTime? lastActivityAt;
}

class BeaconDisplayStatusResult {
  const BeaconDisplayStatusResult({
    required this.phase,
    required this.suggestedAction,
    this.slot2Kind = BeaconDisplaySlot2Kind.none,
    this.reviewClosesAt,
    this.lastActivityAt,
    this.lifecycleEndedAt,
  });

  final BeaconDisplayPhase phase;
  final BeaconDisplayPrimaryAction suggestedAction;
  final BeaconDisplaySlot2Kind slot2Kind;
  final DateTime? reviewClosesAt;
  final DateTime? lastActivityAt;
  final DateTime? lifecycleEndedAt;
}

BeaconDisplayStatusResult deriveBeaconDisplayStatus(
  BeaconDisplayStatusInput input,
) {
  final status = input.status;

  if (status == BeaconStatus.deleted) {
    return _terminal(
      phase: BeaconDisplayPhase.closed,
      lifecycleEndedAt: input.updatedAt,
    );
  }
  if (status == BeaconStatus.cancelled) {
    return _terminal(
      phase: BeaconDisplayPhase.cancelled,
      lifecycleEndedAt: input.updatedAt,
    );
  }
  if (status == BeaconStatus.closed) {
    return _terminal(
      phase: BeaconDisplayPhase.closed,
      lifecycleEndedAt: input.updatedAt,
    );
  }
  if (status == BeaconStatus.draft) {
    return const BeaconDisplayStatusResult(
      phase: BeaconDisplayPhase.draft,
      suggestedAction: BeaconDisplayPrimaryAction.none,
    );
  }

  if (input.tier == BeaconDisplayTier.public) {
    return _derivePublic(input);
  }
  return _deriveCoordination(input);
}

BeaconDisplayStatusResult _deriveCoordination(BeaconDisplayStatusInput input) {
  final activityAt = input.lastActivityAt ?? input.updatedAt;

  if (input.status == BeaconStatus.reviewOpen) {
    return BeaconDisplayStatusResult(
      phase: BeaconDisplayPhase.wrappingUp,
      slot2Kind: _reviewSlot2(input),
      suggestedAction: BeaconDisplayPrimaryAction.reviewContributions,
      reviewClosesAt: input.reviewClosesAt,
      lastActivityAt: activityAt,
    );
  }

  if (!input.status.isOpenFamily) {
    return _floor(activityAt);
  }

  if (input.hasOpenBlocker) {
    return BeaconDisplayStatusResult(
      phase: BeaconDisplayPhase.blocked,
      slot2Kind: BeaconDisplaySlot2Kind.blockerNeedsClearing,
      suggestedAction: BeaconDisplayPrimaryAction.resolveBlocker,
      lastActivityAt: activityAt,
    );
  }

  if (input.hasUnreviewedOffers) {
    return BeaconDisplayStatusResult(
      phase: BeaconDisplayPhase.offersAwaitingAuthor,
      slot2Kind: BeaconDisplaySlot2Kind.freshness,
      suggestedAction: BeaconDisplayPrimaryAction.reviewOffers,
      lastActivityAt: activityAt,
    );
  }

  if (input.status == BeaconStatus.needsMoreHelp) {
    return BeaconDisplayStatusResult(
      phase: BeaconDisplayPhase.needsMoreHelp,
      slot2Kind: BeaconDisplaySlot2Kind.freshness,
      suggestedAction: BeaconDisplayPrimaryAction.offerHelp,
      lastActivityAt: activityAt,
    );
  }

  if (input.status == BeaconStatus.enoughHelp) {
    return BeaconDisplayStatusResult(
      phase: BeaconDisplayPhase.enoughHelpInMotion,
      slot2Kind: BeaconDisplaySlot2Kind.freshness,
      suggestedAction: BeaconDisplayPrimaryAction.none,
      lastActivityAt: activityAt,
    );
  }

  if (input.hasOpenRoomAsks ||
      (input.helpOfferCount > 0 && !input.hasUnreviewedOffers)) {
    return BeaconDisplayStatusResult(
      phase: BeaconDisplayPhase.coordinating,
      slot2Kind: BeaconDisplaySlot2Kind.freshness,
      suggestedAction: BeaconDisplayPrimaryAction.none,
      lastActivityAt: activityAt,
    );
  }

  if (input.helpOfferCount == 0) {
    return BeaconDisplayStatusResult(
      phase: BeaconDisplayPhase.lookingForHelpers,
      slot2Kind: BeaconDisplaySlot2Kind.noOffersYet,
      suggestedAction: BeaconDisplayPrimaryAction.forward,
      lastActivityAt: activityAt,
    );
  }

  return BeaconDisplayStatusResult(
    phase: BeaconDisplayPhase.coordinating,
    slot2Kind: BeaconDisplaySlot2Kind.freshness,
    suggestedAction: BeaconDisplayPrimaryAction.none,
    lastActivityAt: activityAt,
  );
}

BeaconDisplayStatusResult _derivePublic(BeaconDisplayStatusInput input) {
  final activityAt = input.lastActivityAt ?? input.updatedAt;

  if (input.status == BeaconStatus.reviewOpen) {
    return BeaconDisplayStatusResult(
      phase: BeaconDisplayPhase.wrappingUp,
      suggestedAction: BeaconDisplayPrimaryAction.none,
      lastActivityAt: activityAt,
    );
  }

  if (!input.status.isOpenFamily) {
    return _floor(activityAt);
  }

  if (input.status == BeaconStatus.needsMoreHelp) {
    return BeaconDisplayStatusResult(
      phase: BeaconDisplayPhase.needsMoreHelp,
      suggestedAction: BeaconDisplayPrimaryAction.offerHelp,
      lastActivityAt: activityAt,
    );
  }
  if (input.status == BeaconStatus.enoughHelp) {
    return BeaconDisplayStatusResult(
      phase: BeaconDisplayPhase.enoughHelpInMotion,
      suggestedAction: BeaconDisplayPrimaryAction.offerHelp,
      lastActivityAt: activityAt,
    );
  }
  if (input.helpOfferCount > 0) {
    return BeaconDisplayStatusResult(
      phase: BeaconDisplayPhase.coordinating,
      suggestedAction: BeaconDisplayPrimaryAction.offerHelp,
      lastActivityAt: activityAt,
    );
  }

  return BeaconDisplayStatusResult(
    phase: BeaconDisplayPhase.lookingForHelpers,
    slot2Kind: BeaconDisplaySlot2Kind.noOffersYet,
    suggestedAction: BeaconDisplayPrimaryAction.offerHelp,
    lastActivityAt: activityAt,
  );
}

BeaconDisplaySlot2Kind _reviewSlot2(BeaconDisplayStatusInput input) {
  final closesAt = input.reviewClosesAt;
  if (closesAt == null || input.reviewWindowStatus == 1) {
    return BeaconDisplaySlot2Kind.none;
  }
  return BeaconDisplaySlot2Kind.reviewCountdown;
}

BeaconDisplayStatusResult _terminal({
  required BeaconDisplayPhase phase,
  DateTime? lifecycleEndedAt,
}) {
  return BeaconDisplayStatusResult(
    phase: phase,
    slot2Kind: lifecycleEndedAt != null
        ? BeaconDisplaySlot2Kind.lifecycleEndedAt
        : BeaconDisplaySlot2Kind.none,
    suggestedAction: BeaconDisplayPrimaryAction.none,
    lifecycleEndedAt: lifecycleEndedAt,
  );
}

BeaconDisplayStatusResult _floor(DateTime? lastActivityAt) {
  return BeaconDisplayStatusResult(
    phase: BeaconDisplayPhase.openFloor,
    suggestedAction: BeaconDisplayPrimaryAction.none,
    lastActivityAt: lastActivityAt,
  );
}
