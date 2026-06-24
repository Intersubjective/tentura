import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../entity/beacon.dart';
import '../entity/beacon_coordination_phase.dart';
import '../entity/open_blocker_cue.dart';
import 'beacon_coordination_phase_input.dart';
import 'beacon_has_unreviewed_offers.dart';

/// Priority ladder: first match wins; floor is never blank ([phase] always set).
///
/// Deprecated: prefer server [BeaconDisplayStatusDto] when available.
BeaconCoordinationPhaseResult deriveBeaconCoordinationPhase(
  BeaconCoordinationPhaseInput input,
) {
  final beacon = input.beacon;
  final status = beacon.status;

  if (status == BeaconStatus.deleted) {
    return _terminal(
      phase: BeaconCoordinationPhase.closed,
      action: BeaconPhasePrimaryAction.none,
      lifecycleEndedAt: beacon.updatedAt,
    );
  }
  if (status == BeaconStatus.cancelled) {
    return _terminal(
      phase: BeaconCoordinationPhase.cancelled,
      action: BeaconPhasePrimaryAction.none,
      lifecycleEndedAt: beacon.updatedAt,
    );
  }
  if (status == BeaconStatus.closed) {
    return _terminal(
      phase: BeaconCoordinationPhase.closed,
      action: BeaconPhasePrimaryAction.none,
      lifecycleEndedAt: beacon.updatedAt,
    );
  }
  if (status == BeaconStatus.draft) {
    return const BeaconCoordinationPhaseResult(
      phase: BeaconCoordinationPhase.draft,
      suggestedAction: BeaconPhasePrimaryAction.none,
      rowHarmony: BeaconPhaseRowHarmony.empty,
    );
  }

  if (input.tier == BeaconVisibilityTier.public) {
    return _derivePublicTier(input);
  }

  return _deriveCoordinationTier(input);
}

BeaconCoordinationPhaseResult _deriveCoordinationTier(
  BeaconCoordinationPhaseInput input,
) {
  final beacon = input.beacon;
  final status = beacon.status;
  final activityAt = _activityAt(input);

  if (status == BeaconStatus.reviewOpen) {
    return BeaconCoordinationPhaseResult(
      phase: BeaconCoordinationPhase.wrappingUp,
      slot2Kind: _reviewSlot2(beacon),
      suggestedAction: BeaconPhasePrimaryAction.reviewContributions,
      rowHarmony: const BeaconPhaseRowHarmony(suppressNowPlaceholder: true),
      reviewClosesAt: beacon.reviewClosesAt,
      lastActivityAt: activityAt,
    );
  }

  if (!status.isOpenFamily) {
    return _floor(activityAt);
  }

  if (input.hasOpenBlocker) {
    return BeaconCoordinationPhaseResult(
      phase: BeaconCoordinationPhase.blocked,
      slot2Kind: BeaconPhaseSlot2Kind.blockerNeedsClearing,
      suggestedAction: BeaconPhasePrimaryAction.resolveBlocker,
      rowHarmony: const BeaconPhaseRowHarmony(
        preferBlockedYouSegment: true,
        showBlockedTitleInNowSubline: true,
        suppressNowPlaceholder: true,
      ),
      lastActivityAt: activityAt,
    );
  }

  if (status == BeaconStatus.needsMoreHelp) {
    return BeaconCoordinationPhaseResult(
      phase: BeaconCoordinationPhase.needsMoreHelp,
      slot2Kind: BeaconPhaseSlot2Kind.freshness,
      suggestedAction: BeaconPhasePrimaryAction.offerHelp,
      rowHarmony: BeaconPhaseRowHarmony.empty,
      lastActivityAt: activityAt,
    );
  }

  if (status == BeaconStatus.enoughHelp) {
    return BeaconCoordinationPhaseResult(
      phase: BeaconCoordinationPhase.enoughHelpInMotion,
      slot2Kind: BeaconPhaseSlot2Kind.freshness,
      suggestedAction: BeaconPhasePrimaryAction.none,
      rowHarmony: BeaconPhaseRowHarmony.empty,
      lastActivityAt: activityAt,
    );
  }

  final unreviewed = input.hasUnreviewedOffers ||
      beaconHasUnreviewedOffers(beacon);
  if (unreviewed) {
    return BeaconCoordinationPhaseResult(
      phase: BeaconCoordinationPhase.offersAwaitingAuthor,
      slot2Kind: BeaconPhaseSlot2Kind.freshness,
      suggestedAction: BeaconPhasePrimaryAction.reviewOffers,
      rowHarmony: const BeaconPhaseRowHarmony(
        suppressYouAwaitingAuthor: true,
      ),
      lastActivityAt: activityAt,
    );
  }

  if (input.hasOpenRoomAsks ||
      (beacon.helpOfferCount > 0 && !unreviewed)) {
    return BeaconCoordinationPhaseResult(
      phase: BeaconCoordinationPhase.coordinating,
      slot2Kind: BeaconPhaseSlot2Kind.freshness,
      suggestedAction: BeaconPhasePrimaryAction.none,
      rowHarmony: BeaconPhaseRowHarmony.empty,
      lastActivityAt: activityAt,
    );
  }

  if (beacon.helpOfferCount == 0) {
    return BeaconCoordinationPhaseResult(
      phase: BeaconCoordinationPhase.lookingForHelpers,
      slot2Kind: BeaconPhaseSlot2Kind.noOffersYet,
      suggestedAction: BeaconPhasePrimaryAction.forward,
      rowHarmony: BeaconPhaseRowHarmony.empty,
      lastActivityAt: activityAt,
    );
  }

  return BeaconCoordinationPhaseResult(
    phase: BeaconCoordinationPhase.coordinating,
    slot2Kind: BeaconPhaseSlot2Kind.freshness,
    suggestedAction: BeaconPhasePrimaryAction.none,
    rowHarmony: BeaconPhaseRowHarmony.empty,
    lastActivityAt: activityAt,
  );
}

BeaconCoordinationPhaseResult _derivePublicTier(
  BeaconCoordinationPhaseInput input,
) {
  final beacon = input.beacon;
  final status = beacon.status;
  final activityAt = _activityAt(input);

  if (status == BeaconStatus.reviewOpen) {
    return BeaconCoordinationPhaseResult(
      phase: BeaconCoordinationPhase.wrappingUp,
      suggestedAction: BeaconPhasePrimaryAction.none,
      rowHarmony: BeaconPhaseRowHarmony.empty,
      lastActivityAt: activityAt,
    );
  }

  if (!status.isOpenFamily) {
    return _floor(activityAt);
  }

  if (status == BeaconStatus.needsMoreHelp) {
    return BeaconCoordinationPhaseResult(
      phase: BeaconCoordinationPhase.needsMoreHelp,
      suggestedAction: BeaconPhasePrimaryAction.offerHelp,
      rowHarmony: BeaconPhaseRowHarmony.empty,
      lastActivityAt: activityAt,
    );
  }
  if (status == BeaconStatus.enoughHelp) {
    return BeaconCoordinationPhaseResult(
      phase: BeaconCoordinationPhase.enoughHelpInMotion,
      suggestedAction: BeaconPhasePrimaryAction.offerHelp,
      rowHarmony: BeaconPhaseRowHarmony.empty,
      lastActivityAt: activityAt,
    );
  }
  if (beacon.helpOfferCount > 0) {
    return BeaconCoordinationPhaseResult(
      phase: BeaconCoordinationPhase.coordinating,
      suggestedAction: BeaconPhasePrimaryAction.offerHelp,
      rowHarmony: BeaconPhaseRowHarmony.empty,
      lastActivityAt: activityAt,
    );
  }

  return BeaconCoordinationPhaseResult(
    phase: BeaconCoordinationPhase.lookingForHelpers,
    slot2Kind: BeaconPhaseSlot2Kind.noOffersYet,
    suggestedAction: BeaconPhasePrimaryAction.offerHelp,
    rowHarmony: BeaconPhaseRowHarmony.empty,
    lastActivityAt: activityAt,
  );
}

BeaconPhaseSlot2Kind _reviewSlot2(Beacon beacon) {
  final closesAt = beacon.reviewClosesAt;
  if (closesAt == null || beacon.reviewWindowStatus == 1) {
    return BeaconPhaseSlot2Kind.none;
  }
  return BeaconPhaseSlot2Kind.reviewCountdown;
}

DateTime? _activityAt(BeaconCoordinationPhaseInput input) {
  return input.lastActivityAt ?? input.beacon.updatedAt;
}

BeaconCoordinationPhaseResult _terminal({
  required BeaconCoordinationPhase phase,
  required BeaconPhasePrimaryAction action,
  DateTime? lastActivityAt,
  DateTime? lifecycleEndedAt,
}) {
  return BeaconCoordinationPhaseResult(
    phase: phase,
    slot2Kind: lifecycleEndedAt != null
        ? BeaconPhaseSlot2Kind.lifecycleEndedAt
        : BeaconPhaseSlot2Kind.none,
    suggestedAction: action,
    rowHarmony: BeaconPhaseRowHarmony.empty,
    lastActivityAt: lastActivityAt,
    lifecycleEndedAt: lifecycleEndedAt,
  );
}

BeaconCoordinationPhaseResult _floor(DateTime? lastActivityAt) {
  return BeaconCoordinationPhaseResult(
    phase: BeaconCoordinationPhase.openFloor,
    suggestedAction: BeaconPhasePrimaryAction.none,
    rowHarmony: BeaconPhaseRowHarmony.empty,
    lastActivityAt: lastActivityAt,
  );
}

BeaconCoordinationPhaseInput buildBeaconCoordinationPhaseInput({
  required Beacon beacon,
  required BeaconVisibilityTier tier,
  DateTime? now,
  bool hasOpenBlocker = false,
  bool hasUnreviewedOffers = false,
  bool hasOpenRoomAsks = false,
  OpenBlockerCue? openBlocker,
  DateTime? lastActivityAt,
}) {
  return BeaconCoordinationPhaseInput(
    beacon: beacon,
    tier: tier,
    now: now ?? DateTime.now(),
    hasOpenBlocker: hasOpenBlocker,
    hasUnreviewedOffers: hasUnreviewedOffers,
    hasOpenRoomAsks: hasOpenRoomAsks,
    openBlocker: openBlocker,
    lastActivityAt: lastActivityAt,
  );
}
