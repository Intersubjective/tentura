import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../entity/beacon_coordination_phase.dart';
import '../entity/coordination_response_type.dart';

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
}

enum BeaconYouEmptyFallback {
  hidden,
  waitingOnOthers,
  noOpenItems,
  awaitingAuthorReview,
  authorReviewOffers,
  noInfo,
  closed,
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

/// Priority ladder:
/// 1. Closed/deleted -> closed.
/// 2. Author has unanswered offers -> authorReviewOffers.
/// 3. Helper waiting for author review -> awaitingAuthorReview.
/// 4. Others open > 0 -> waitingOnOthers.
/// 5. Open non-author non-compact -> noInfo.
/// 6. Compact without personal obligation -> hidden.
/// 7. noOpenItems.
BeaconYouEmptyFallback deriveBeaconYouEmptyFallback(
  BeaconYouSituationInput input,
) {
  if (input.lifecycle == BeaconStatus.closed ||
      input.lifecycle == BeaconStatus.deleted) {
    return BeaconYouEmptyFallback.closed;
  }
  if (viewerHasAuthorReviewObligation(input)) {
    return BeaconYouEmptyFallback.authorReviewOffers;
  }
  if (input.isAwaitingAuthorReview) {
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

bool hasBeaconYouPersonalObligation(BeaconYouSituationInput input) =>
    input.hasRoomObligations ||
    input.viewerBlocked ||
    viewerHasAuthorReviewObligation(input) ||
    input.isAwaitingAuthorReview;

bool isBeaconYouRowVisible(BeaconYouSituationInput input) =>
    deriveBeaconYouEmptyFallback(input) != BeaconYouEmptyFallback.hidden ||
    input.hasRoomObligations ||
    input.viewerBlocked ||
    viewerHasAuthorReviewObligation(input) ||
    input.isAwaitingAuthorReview;

/// Segments to show before room responsibility chips.
List<BeaconYouOfferReviewSegmentKind> offerReviewSegments(
  BeaconYouSituationInput input,
) {
  final out = <BeaconYouOfferReviewSegmentKind>[];
  if (viewerHasAuthorReviewObligation(input)) {
    out.add(BeaconYouOfferReviewSegmentKind.authorReview);
  } else if (input.isAwaitingAuthorReview) {
    out.add(BeaconYouOfferReviewSegmentKind.helperAwaitingAuthor);
  }
  return out;
}
