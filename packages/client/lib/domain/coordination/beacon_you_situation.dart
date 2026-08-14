import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../entity/beacon_coordination_phase.dart';
import '../entity/coordination_response_type.dart';
import 'helper_offer_response_state.dart';

/// Input humble object for YOU-row derivation.
class BeaconYouSituationInput {
  const BeaconYouSituationInput({
    required this.lifecycle,
    required this.isAuthorOrSteward,
    required this.othersOpenCount,
    required this.compactSurface,
    required this.hasRoomObligations,
    required this.isAwaitingAuthorReview,
    required this.authorUnreviewedHelpOfferCount,
    this.rowHarmony = BeaconPhaseRowHarmony.empty,
    this.viewerBlocked = false,
    this.helperOfferState,
  });

  final BeaconStatus lifecycle;
  final bool isAuthorOrSteward;
  final int othersOpenCount;
  final bool compactSurface;
  final bool hasRoomObligations;
  final bool isAwaitingAuthorReview;
  final int authorUnreviewedHelpOfferCount;
  final BeaconPhaseRowHarmony rowHarmony;
  final bool viewerBlocked;
  final HelperOfferResponseState? helperOfferState;
}

enum BeaconYouEmptyFallback {
  hidden,
  waitingOnOthers,
  noOpenItems,
  awaitingAuthorReview,
  authorReviewOffers,
  noInfo,
  closed,
  offerDeclined,
  offerSoftened,
  offerParticipationEnded,
  offerExited,
  offerClosedWithoutResponse,
}

enum BeaconYouOfferReviewSegmentKind {
  authorReview,
  helperAwaitingAuthor,
}

/// Whether offer-review obligation applies to this viewer.
bool viewerHasAuthorReviewObligation(BeaconYouSituationInput input) =>
    input.isAuthorOrSteward && input.authorUnreviewedHelpOfferCount > 0;

bool viewerAwaitingAuthorHelpOfferReview({
  required bool isAuthorOrSteward,
  required CoordinationResponseType? viewerOfferAuthorResponse,
  required bool viewerHasActiveHelpOffer,
}) =>
    !isAuthorOrSteward &&
    viewerHasActiveHelpOffer &&
    viewerOfferAuthorResponse == null;

BeaconYouEmptyFallback? _helperOfferTerminalFallback(
  HelperOfferResponseState state,
) =>
    switch (state) {
      HelperOfferResponseState.declined =>
        BeaconYouEmptyFallback.offerDeclined,
      HelperOfferResponseState.softened =>
        BeaconYouEmptyFallback.offerSoftened,
      HelperOfferResponseState.participationEnded =>
        BeaconYouEmptyFallback.offerParticipationEnded,
      HelperOfferResponseState.exited => BeaconYouEmptyFallback.offerExited,
      HelperOfferResponseState.closedWithoutResponse =>
        BeaconYouEmptyFallback.offerClosedWithoutResponse,
      _ => null,
    };

bool _helperOfferFallbackForcesPersonalCopy(BeaconYouEmptyFallback fallback) =>
    fallback == BeaconYouEmptyFallback.awaitingAuthorReview ||
    switch (fallback) {
      BeaconYouEmptyFallback.offerDeclined ||
      BeaconYouEmptyFallback.offerSoftened ||
      BeaconYouEmptyFallback.offerParticipationEnded ||
      BeaconYouEmptyFallback.offerExited ||
      BeaconYouEmptyFallback.offerClosedWithoutResponse =>
        true,
      _ => false,
    };

/// Whether the fallback should render as personal copy instead of inventory.
bool beaconYouEmptyFallbackForcesPersonalCopy(BeaconYouEmptyFallback fallback) =>
    _helperOfferFallbackForcesPersonalCopy(fallback);

/// Priority ladder:
/// 1. Helper terminal stake -> offer_* fallback.
/// 2. Closed/deleted -> closed.
/// 3. Author has unanswered offers -> authorReviewOffers.
/// 4. Helper waiting for author review -> awaitingAuthorReview.
/// 5. Others open > 0 -> waitingOnOthers.
/// 6. Open non-author non-compact -> noInfo.
/// 7. Compact without personal obligation -> hidden.
/// 8. noOpenItems.
BeaconYouEmptyFallback deriveBeaconYouEmptyFallback(
  BeaconYouSituationInput input,
) {
  final helperState = input.helperOfferState;
  if (helperState != null) {
    final terminal = _helperOfferTerminalFallback(helperState);
    if (terminal != null) {
      return terminal;
    }
  }

  if (input.lifecycle == BeaconStatus.closed ||
      input.lifecycle == BeaconStatus.deleted) {
    return BeaconYouEmptyFallback.closed;
  }
  if (viewerHasAuthorReviewObligation(input)) {
    return BeaconYouEmptyFallback.authorReviewOffers;
  }
  if (input.isAwaitingAuthorReview ||
      helperState == HelperOfferResponseState.awaitingAuthor) {
    return BeaconYouEmptyFallback.awaitingAuthorReview;
  }
  if (input.othersOpenCount > 0) {
    return BeaconYouEmptyFallback.waitingOnOthers;
  }
  if (!input.isAuthorOrSteward &&
      input.lifecycle == BeaconStatus.open &&
      !input.compactSurface) {
    return BeaconYouEmptyFallback.noInfo;
  }
  if (input.compactSurface && !hasBeaconYouPersonalObligation(input)) {
    return BeaconYouEmptyFallback.hidden;
  }
  return BeaconYouEmptyFallback.noOpenItems;
}

bool hasBeaconYouPersonalObligation(BeaconYouSituationInput input) {
  final helperState = input.helperOfferState;
  if (helperState != null &&
      helperOfferResponseStateHasStandingMessage(helperState)) {
    return true;
  }
  return input.hasRoomObligations ||
      input.viewerBlocked ||
      viewerHasAuthorReviewObligation(input) ||
      input.isAwaitingAuthorReview;
}

bool isBeaconYouRowVisible(BeaconYouSituationInput input) {
  final helperState = input.helperOfferState;
  return deriveBeaconYouEmptyFallback(input) != BeaconYouEmptyFallback.hidden ||
      input.hasRoomObligations ||
      input.viewerBlocked ||
      viewerHasAuthorReviewObligation(input) ||
      input.isAwaitingAuthorReview ||
      (helperState != null &&
          helperOfferResponseStateHasStandingMessage(helperState));
}

/// Segments to show before room responsibility chips.
List<BeaconYouOfferReviewSegmentKind> offerReviewSegments(
  BeaconYouSituationInput input,
) {
  final out = <BeaconYouOfferReviewSegmentKind>[];
  if (viewerHasAuthorReviewObligation(input)) {
    out.add(BeaconYouOfferReviewSegmentKind.authorReview);
  } else if (input.isAwaitingAuthorReview ||
      input.helperOfferState == HelperOfferResponseState.awaitingAuthor) {
    out.add(BeaconYouOfferReviewSegmentKind.helperAwaitingAuthor);
  }
  return out;
}
