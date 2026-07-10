import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';

/// Author-only HUD actions on the beacon detail operational header.
enum BeaconHudAuthorAction {
  resolveBlocker,
  reviewOffers,
  markEnoughHelp,
  wrapUpForReview,
  reviewContributions,
  closeNow,
  forward,
}

/// Resolved author ACT for the HUD action rail.
class BeaconHudAuthorActSpec {
  const BeaconHudAuthorActSpec({
    required this.action,
    required this.label,
    required this.icon,
    required this.filled,
  });

  final BeaconHudAuthorAction action;
  final String label;
  final IconData icon;
  final bool filled;
}

bool authorHudActGate(BeaconViewState state) {
  if (!state.isBeaconMine) return false;
  if (!state.beaconContextLoaded) return false;
  if (state.isLoading) return false;
  final status = state.beacon.status;
  if (status == BeaconStatus.deleted ||
      status == BeaconStatus.closed ||
      status == BeaconStatus.cancelled) {
    return false;
  }
  return true;
}

bool authorPersonallyOwnsBlocker(BeaconViewState state) {
  final input = beaconPhaseInputFromViewState(state);
  return viewerIsPersonallyResponsibleForBlocker(
    openBlocker: input.openBlocker,
    viewerUserId: state.myProfile.id,
  );
}

bool authorForwardAllowed(BeaconViewState state) {
  final b = state.beacon;
  if (!b.allowsForward) return false;
  if (b.status != BeaconStatus.open &&
      b.status != BeaconStatus.needsMoreHelp) {
    return false;
  }
  return true;
}

/// Derives the author HUD action kind without UI labels.
BeaconHudAuthorAction? deriveBeaconHudAuthorAction(BeaconViewState state) {
  if (!authorHudActGate(state)) return null;

  final beacon = state.beacon;
  final lifecycle = beacon.status;

  if (lifecycle == BeaconStatus.reviewOpen) {
    return _reviewOpenAuthorAction(state);
  }

  if (!lifecycle.isOpenFamily) return null;

  if (authorPersonallyOwnsBlocker(state)) {
    return BeaconHudAuthorAction.resolveBlocker;
  }

  if (state.unansweredHelpOffersCount > 0) {
    return BeaconHudAuthorAction.reviewOffers;
  }

  final readiness = computeClosureReadiness(state);
  final blocked = readiness == BeaconClosureReadiness.blocked;
  final ready = readiness == BeaconClosureReadiness.readyToClose;
  final hasCommitters = beaconStateHasCommitters(state);

  if (!blocked && hasCommitters) {
    if (ready) {
      return BeaconHudAuthorAction.wrapUpForReview;
    }
    if (lifecycle != BeaconStatus.enoughHelp) {
      return BeaconHudAuthorAction.markEnoughHelp;
    }
  }

  if (authorForwardAllowed(state)) {
    return BeaconHudAuthorAction.forward;
  }

  return null;
}

BeaconHudAuthorAction? _reviewOpenAuthorAction(BeaconViewState state) {
  final review = state.reviewWindowInfo;
  if (review == null || !review.hasWindow || review.windowComplete) {
    return null;
  }

  if (review.viewerHasOutstandingReviewWork) {
    return BeaconHudAuthorAction.reviewContributions;
  }

  if (review.canCloseNow == true) {
    return BeaconHudAuthorAction.closeNow;
  }

  return null;
}

IconData iconForBeaconHudAuthorAction(BeaconHudAuthorAction action) {
  return switch (action) {
    BeaconHudAuthorAction.resolveBlocker => Icons.warning_amber_outlined,
    BeaconHudAuthorAction.reviewOffers => Icons.people_outline,
    BeaconHudAuthorAction.markEnoughHelp => Icons.check_circle_outline,
    BeaconHudAuthorAction.wrapUpForReview => Icons.rate_review_outlined,
    BeaconHudAuthorAction.reviewContributions => Icons.rate_review_outlined,
    BeaconHudAuthorAction.closeNow => Icons.lock_outline,
    BeaconHudAuthorAction.forward => Icons.send_outlined,
  };
}

bool filledBeaconHudAuthorAction(BeaconHudAuthorAction action) =>
    action != BeaconHudAuthorAction.forward &&
    action != BeaconHudAuthorAction.closeNow;

String labelForBeaconHudAuthorAction(L10n l10n, BeaconHudAuthorAction action) {
  return switch (action) {
    BeaconHudAuthorAction.resolveBlocker => l10n.beaconPhaseCtaResolveBlocker,
    BeaconHudAuthorAction.reviewOffers => l10n.beaconPhaseCtaReviewOffers,
    BeaconHudAuthorAction.markEnoughHelp => l10n.beaconHudActMarkEnoughHelp,
    BeaconHudAuthorAction.wrapUpForReview => l10n.beaconHudActWrapUpForReview,
    BeaconHudAuthorAction.reviewContributions =>
      l10n.beaconHudActReviewContributions,
    BeaconHudAuthorAction.closeNow => l10n.beaconReviewCloseNowAction,
    BeaconHudAuthorAction.forward => l10n.labelForward,
  };
}

/// Derives at most one author HUD action from loaded beacon view state.
BeaconHudAuthorActSpec? deriveBeaconHudAuthorActSpec({
  required L10n l10n,
  required BeaconViewState state,
}) {
  final action = deriveBeaconHudAuthorAction(state);
  if (action == null) return null;
  return BeaconHudAuthorActSpec(
    action: action,
    label: labelForBeaconHudAuthorAction(l10n, action),
    icon: iconForBeaconHudAuthorAction(action),
    filled: filledBeaconHudAuthorAction(action),
  );
}

/// Whether Forward should appear in overflow (not duplicated in the HUD ACT).
bool forwardShownInAuthorHud(BeaconViewState state) =>
    deriveBeaconHudAuthorAction(state) == BeaconHudAuthorAction.forward;
