import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_you_presentation.dart';

BeaconYouSituationInput _input({
  BeaconStatus lifecycle = BeaconStatus.open,
  bool isAuthorOrSteward = false,
  int othersOpenCount = 0,
  bool compactSurface = false,
  bool hasRoomObligations = false,
  bool isAwaitingAuthorReview = false,
  int authorUnreviewedHelpOfferCount = 0,
  bool viewerBlocked = false,
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
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('buildBeaconYouPresentation', () {
    test('returns ordered room segments with labels when not collapsed', () {
      const responsibility = CoordinationResponsibility(
        beaconId: 'b1',
        askOpen: 2,
        promiseOpen: 1,
      );
      final presentation = buildBeaconYouPresentation(
        l10n,
        responsibility,
        collapse: false,
        situationInput: _input(hasRoomObligations: true),
        emptyFallback: BeaconYouEmptyFallback.noOpenItems,
        showNewBadges: true,
      );
      expect(presentation.fallbackText, isNull);
      expect(presentation.segments, hasLength(2));
      expect(presentation.segments.first.label, l10n.beaconYouAskCount(2));
      expect(presentation.segments.last.label, l10n.beaconYouPromiseCount(1));
    });

    test('prepends author review segment before room obligations', () {
      const responsibility = CoordinationResponsibility(
        beaconId: 'b1',
        askOpen: 1,
      );
      final presentation = buildBeaconYouPresentation(
        l10n,
        responsibility,
        collapse: false,
        situationInput: _input(
          isAuthorOrSteward: true,
          hasRoomObligations: true,
          authorUnreviewedHelpOfferCount: 2,
        ),
        emptyFallback: BeaconYouEmptyFallback.noOpenItems,
        showNewBadges: false,
      );
      expect(presentation.segments, hasLength(2));
      expect(
        presentation.segments.first.label,
        l10n.beaconHudYouAuthorReview(2),
      );
      expect(presentation.segments[1].label, l10n.beaconYouAskCount(1));
    });

    test('prepends helper awaiting-author segment before room obligations', () {
      const responsibility = CoordinationResponsibility(
        beaconId: 'b1',
        askOpen: 1,
      );
      final presentation = buildBeaconYouPresentation(
        l10n,
        responsibility,
        collapse: false,
        situationInput: _input(
          hasRoomObligations: true,
          isAwaitingAuthorReview: true,
        ),
        emptyFallback: BeaconYouEmptyFallback.noOpenItems,
        showNewBadges: false,
      );
      expect(presentation.segments, hasLength(2));
      expect(presentation.segments.first.label, l10n.beaconYouOfferSent);
      expect(presentation.segments[1].label, l10n.beaconYouAskCount(1));
    });

    test('empty responsibility uses authorReviewOffers fallback', () {
      const responsibility = CoordinationResponsibility(beaconId: 'b1');
      final presentation = buildBeaconYouPresentation(
        l10n,
        responsibility,
        collapse: false,
        situationInput: _input(
          isAuthorOrSteward: true,
          authorUnreviewedHelpOfferCount: 3,
        ),
        emptyFallback: BeaconYouEmptyFallback.authorReviewOffers,
        showNewBadges: false,
      );
      expect(presentation.fallbackText, l10n.beaconHudYouAuthorReview(3));
    });

    test('empty responsibility hidden produces hidden presentation', () {
      const responsibility = CoordinationResponsibility(beaconId: 'b1');
      final presentation = buildBeaconYouPresentation(
        l10n,
        responsibility,
        collapse: false,
        situationInput: _input(compactSurface: true),
        emptyFallback: BeaconYouEmptyFallback.hidden,
        showNewBadges: false,
      );
      expect(presentation.isHidden, isTrue);
      expect(presentation.segments, isEmpty);
      expect(presentation.fallbackText, isNull);
    });
  });

  group('deriveBeaconYouEmptyFallback', () {
    test('closed lifecycle returns closed', () {
      final fallback = deriveBeaconYouEmptyFallback(
        input: _input(lifecycle: BeaconStatus.closed),
      );
      expect(fallback, BeaconYouEmptyFallback.closed);
    });

    test('awaitingAuthorReview beats waitingOnOthers', () {
      final fallback = deriveBeaconYouEmptyFallback(
        input: _input(
          othersOpenCount: 4,
          isAwaitingAuthorReview: true,
        ),
      );
      expect(fallback, BeaconYouEmptyFallback.awaitingAuthorReview);
    });

    test('authorReviewOffers beats waitingOnOthers', () {
      final fallback = deriveBeaconYouEmptyFallback(
        input: _input(
          isAuthorOrSteward: true,
          othersOpenCount: 3,
          authorUnreviewedHelpOfferCount: 2,
        ),
      );
      expect(fallback, BeaconYouEmptyFallback.authorReviewOffers);
    });

    test('compact surface without personal obligation returns hidden', () {
      final fallback = deriveBeaconYouEmptyFallback(
        input: _input(compactSurface: true),
      );
      expect(fallback, BeaconYouEmptyFallback.hidden);
    });
  });

  group('viewerAwaitingAuthorHelpOfferReview', () {
    test('true when helper offer has no author response', () {
      expect(
        viewerAwaitingAuthorHelpOfferReview(
          isAuthorOrSteward: false,
          viewerHasActiveHelpOffer: true,
          viewerOfferAuthorResponse: null,
        ),
        isTrue,
      );
    });

    test('false when viewer is author', () {
      expect(
        viewerAwaitingAuthorHelpOfferReview(
          isAuthorOrSteward: true,
          viewerHasActiveHelpOffer: true,
          viewerOfferAuthorResponse: null,
        ),
        isFalse,
      );
    });
  });
}
