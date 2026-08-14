import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/coordination/beacon_you_situation.dart';
import 'package:tentura/domain/coordination/helper_offer_response_state.dart';

BeaconYouSituationInput _input({
  BeaconStatus lifecycle = BeaconStatus.open,
  bool isAuthorOrSteward = false,
  int othersOpenCount = 0,
  bool compactSurface = false,
  bool hasRoomObligations = false,
  bool isAwaitingAuthorReview = false,
  int authorUnreviewedHelpOfferCount = 0,
  bool viewerBlocked = false,
  HelperOfferResponseState? helperOfferState,
}) {
  return BeaconYouSituationInput(
    lifecycle: lifecycle,
    isAuthorOrSteward: isAuthorOrSteward,
    othersOpenCount: othersOpenCount,
    compactSurface: compactSurface,
    hasRoomObligations: hasRoomObligations,
    isAwaitingAuthorReview: isAwaitingAuthorReview,
    authorUnreviewedHelpOfferCount: authorUnreviewedHelpOfferCount,
    viewerBlocked: viewerBlocked,
    helperOfferState: helperOfferState,
  );
}

void main() {
  group('deriveBeaconYouEmptyFallback', () {
    test('closed without helper terminal offer stays closed', () {
      final fallback = deriveBeaconYouEmptyFallback(
        _input(
          lifecycle: BeaconStatus.closed,
          othersOpenCount: 2,
          isAwaitingAuthorReview: true,
          authorUnreviewedHelpOfferCount: 3,
          isAuthorOrSteward: true,
        ),
      );
      expect(fallback, BeaconYouEmptyFallback.closed);
    });

    test('closed with helper terminal offer uses offer fallback', () {
      final fallback = deriveBeaconYouEmptyFallback(
        _input(
          lifecycle: BeaconStatus.closed,
          helperOfferState: HelperOfferResponseState.closedWithoutResponse,
        ),
      );
      expect(fallback, BeaconYouEmptyFallback.offerClosedWithoutResponse);
    });

    test('author review wins before waitingOnOthers', () {
      final fallback = deriveBeaconYouEmptyFallback(
        _input(
          isAuthorOrSteward: true,
          authorUnreviewedHelpOfferCount: 2,
          othersOpenCount: 3,
        ),
      );
      expect(fallback, BeaconYouEmptyFallback.authorReviewOffers);
    });

    test('helper awaiting review wins before waitingOnOthers', () {
      final fallback = deriveBeaconYouEmptyFallback(
        _input(
          isAwaitingAuthorReview: true,
          othersOpenCount: 4,
        ),
      );
      expect(fallback, BeaconYouEmptyFallback.awaitingAuthorReview);
    });

    test('helper declined beats waitingOnOthers', () {
      final fallback = deriveBeaconYouEmptyFallback(
        _input(
          othersOpenCount: 4,
          helperOfferState: HelperOfferResponseState.declined,
        ),
      );
      expect(fallback, BeaconYouEmptyFallback.offerDeclined);
    });

    test('accepted does not select awaitingAuthorReview', () {
      final fallback = deriveBeaconYouEmptyFallback(
        _input(
          helperOfferState: HelperOfferResponseState.accepted,
        ),
      );
      expect(fallback, isNot(BeaconYouEmptyFallback.awaitingAuthorReview));
    });

    test('compact with no personal obligation is hidden', () {
      final fallback = deriveBeaconYouEmptyFallback(
        _input(compactSurface: true),
      );
      expect(fallback, BeaconYouEmptyFallback.hidden);
    });
  });

  group('offerReviewSegments', () {
    test('returns authorReview segment for author obligation', () {
      final segments = offerReviewSegments(
        _input(
          isAuthorOrSteward: true,
          authorUnreviewedHelpOfferCount: 1,
        ),
      );
      expect(segments, [BeaconYouOfferReviewSegmentKind.authorReview]);
    });

    test('returns helperAwaitingAuthor segment for helper wait', () {
      final segments = offerReviewSegments(
        _input(isAwaitingAuthorReview: true),
      );
      expect(
        segments,
        [BeaconYouOfferReviewSegmentKind.helperAwaitingAuthor],
      );
    });
  });
}
