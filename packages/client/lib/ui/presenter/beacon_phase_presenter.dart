import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/duration_format.dart';

/// Localized STATUS line + tone from domain phase result.
class BeaconPhaseStatusPresentation {
  const BeaconPhaseStatusPresentation({
    required this.statusLine,
    required this.tone,
  });

  final String statusLine;
  final TenturaTone tone;
}

BeaconPhaseStatusPresentation formatBeaconPhaseStatus(
  L10n l10n,
  BeaconCoordinationPhaseResult result, {
  required DateTime now,
}) {
  final slot1 = _phaseSlot1(l10n, result.phase);
  final slot2 = _formatSlot2(l10n, result, now: now);
  final line = _joinSlots(slot1, slot2);
  return BeaconPhaseStatusPresentation(
    statusLine: line,
    tone: _toneForPhase(result.phase),
  );
}

String? formatBeaconPhasePrimaryCtaLabel(
  L10n l10n,
  BeaconPhasePrimaryAction action, {
  bool isAuthor = false,
}) {
  return switch (action) {
    BeaconPhasePrimaryAction.resolveBlocker => l10n.beaconPhaseCtaResolveBlocker,
    BeaconPhasePrimaryAction.reviewOffers => l10n.beaconPhaseCtaReviewOffers,
    BeaconPhasePrimaryAction.forward => l10n.labelForward,
    BeaconPhasePrimaryAction.offerHelp => l10n.labelOfferHelp,
    BeaconPhasePrimaryAction.postUpdate => l10n.postUpdateCTA,
    BeaconPhasePrimaryAction.reviewContributions =>
      l10n.beaconHudCtaReviewContributions,
    BeaconPhasePrimaryAction.none => null,
  };
}

/// Gates phase-suggested action by viewer capability / responsibility.
BeaconPhasePrimaryAction resolveEffectivePrimaryAction({
  required BeaconPhasePrimaryAction suggested,
  required bool isAuthor,
  required bool isAuthorOrSteward,
  required bool canCoordinateInRoom,
  required bool isPersonallyResponsibleForBlocker,
  required bool canOfferHelp,
  required bool canNavigateRoom,
}) {
  return switch (suggested) {
    BeaconPhasePrimaryAction.resolveBlocker =>
      (isPersonallyResponsibleForBlocker && canNavigateRoom)
          ? BeaconPhasePrimaryAction.resolveBlocker
          : BeaconPhasePrimaryAction.none,
    BeaconPhasePrimaryAction.reviewOffers =>
      isAuthor ? BeaconPhasePrimaryAction.reviewOffers : BeaconPhasePrimaryAction.none,
    BeaconPhasePrimaryAction.forward =>
      isAuthor ? BeaconPhasePrimaryAction.forward : BeaconPhasePrimaryAction.none,
    BeaconPhasePrimaryAction.offerHelp =>
      canOfferHelp ? BeaconPhasePrimaryAction.offerHelp : BeaconPhasePrimaryAction.none,
    BeaconPhasePrimaryAction.postUpdate =>
      (isAuthorOrSteward && canCoordinateInRoom)
          ? BeaconPhasePrimaryAction.postUpdate
          : BeaconPhasePrimaryAction.none,
    BeaconPhasePrimaryAction.reviewContributions =>
      BeaconPhasePrimaryAction.reviewContributions,
    BeaconPhasePrimaryAction.none => BeaconPhasePrimaryAction.none,
  };
}

String _phaseSlot1(L10n l10n, BeaconCoordinationPhase phase) => switch (phase) {
      BeaconCoordinationPhase.blocked => l10n.beaconPhaseBlocked,
      BeaconCoordinationPhase.wrappingUp => l10n.beaconPhaseWrappingUp,
      BeaconCoordinationPhase.needsMoreHelp => l10n.beaconPhaseNeedsMoreHelp,
      BeaconCoordinationPhase.enoughHelpInMotion =>
        l10n.beaconPhaseEnoughHelpInMotion,
      BeaconCoordinationPhase.offersAwaitingAuthor =>
        l10n.beaconPhaseOffersAwaitingAuthor,
      BeaconCoordinationPhase.coordinating => l10n.beaconPhaseCoordinating,
      BeaconCoordinationPhase.lookingForHelpers =>
        l10n.beaconPhaseLookingForHelpers,
      BeaconCoordinationPhase.closed => l10n.beaconPhaseClosed,
      BeaconCoordinationPhase.cancelled => l10n.beaconPhaseCancelled,
      BeaconCoordinationPhase.draft => l10n.beaconPhaseDraftNotPosted,
      BeaconCoordinationPhase.openFloor => l10n.beaconPhaseOpen,
    };

String? _formatSlot2(
  L10n l10n,
  BeaconCoordinationPhaseResult result, {
  required DateTime now,
}) {
  return switch (result.slot2Kind) {
    BeaconPhaseSlot2Kind.blockerNeedsClearing =>
      l10n.beaconPhaseBlockerNeedsClearing,
    BeaconPhaseSlot2Kind.courtAuthor => l10n.beaconPhaseCourtAuthor,
    BeaconPhaseSlot2Kind.reviewCountdown => _reviewCountdown(l10n, result, now),
    BeaconPhaseSlot2Kind.freshness => _freshness(l10n, result, now),
    BeaconPhaseSlot2Kind.noOffersYet => l10n.beaconPhaseNoOffersYet,
    BeaconPhaseSlot2Kind.none => null,
  };
}

String? _reviewCountdown(
  L10n l10n,
  BeaconCoordinationPhaseResult result,
  DateTime now,
) {
  final closesAt = result.reviewClosesAt;
  if (closesAt == null) return null;
  final remaining = closesAt.toUtc().difference(now.toUtc());
  if (remaining.isNegative) return null;
  return formatCompactDurationRemaining(remaining, l10n);
}

String? _freshness(
  L10n l10n,
  BeaconCoordinationPhaseResult result,
  DateTime now,
) {
  final at = result.lastActivityAt;
  if (at == null) return null;
  final days = now.toUtc().difference(at.toUtc()).inDays;
  if (days <= 0) return l10n.beaconPhaseActiveToday;
  return l10n.beaconPhaseQuietForDays(days);
}

String _joinSlots(String slot1, String? slot2) {
  final s2 = slot2?.trim() ?? '';
  if (s2.isEmpty) return slot1;
  return '$slot1 · $s2';
}

TenturaTone _toneForPhase(BeaconCoordinationPhase phase) => switch (phase) {
      BeaconCoordinationPhase.blocked => TenturaTone.warn,
      BeaconCoordinationPhase.needsMoreHelp => TenturaTone.warn,
      BeaconCoordinationPhase.enoughHelpInMotion => TenturaTone.good,
      BeaconCoordinationPhase.offersAwaitingAuthor => TenturaTone.info,
      BeaconCoordinationPhase.wrappingUp => TenturaTone.info,
      _ => TenturaTone.neutral,
    };
