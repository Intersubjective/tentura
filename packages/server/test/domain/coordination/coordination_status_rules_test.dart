import 'package:test/test.dart';

import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/coordination/coordination_status_rules.dart';

CoordinationStatusActiveOffer _offer(String userId, {DateTime? createdAt}) =>
    CoordinationStatusActiveOffer(
      userId: userId,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    );

void main() {
  group('deriveBeaconCoordinationStatus', () {
    final cases = <({
      String name,
      List<CoordinationStatusActiveOffer> activeOffers,
      Map<String, int> responses,
      int expected,
    })>[
      (
        name: 'no active offers → neutral',
        activeOffers: [],
        responses: {},
        expected: DerivedBeaconCoordinationStatus.neutral,
      ),
      (
        name: 'one offer without response → waiting for review',
        activeOffers: [_offer('u1')],
        responses: {},
        expected: DerivedBeaconCoordinationStatus.helpOffersWaitingForReview,
      ),
      (
        name: 'multiple offers, one missing response → waiting for review',
        activeOffers: [_offer('u1'), _offer('u2')],
        responses: {
          'u1': CoordinationResponseType.useful.smallintValue,
        },
        expected: DerivedBeaconCoordinationStatus.helpOffersWaitingForReview,
      ),
      (
        name: 'all useful → enough help offered',
        activeOffers: [_offer('u1'), _offer('u2')],
        responses: {
          'u1': CoordinationResponseType.useful.smallintValue,
          'u2': CoordinationResponseType.useful.smallintValue,
        },
        expected: DerivedBeaconCoordinationStatus.enoughHelpOffered,
      ),
      (
        name: 'overlapping response → more or different help needed',
        activeOffers: [_offer('u1')],
        responses: {
          'u1': CoordinationResponseType.overlapping.smallintValue,
        },
        expected: DerivedBeaconCoordinationStatus.moreOrDifferentHelpNeeded,
      ),
      (
        name: 'need different skill → more or different help needed',
        activeOffers: [_offer('u1')],
        responses: {
          'u1': CoordinationResponseType.needDifferentSkill.smallintValue,
        },
        expected: DerivedBeaconCoordinationStatus.moreOrDifferentHelpNeeded,
      ),
      (
        name: 'mixed useful and not suitable → more or different help needed',
        activeOffers: [_offer('u1'), _offer('u2')],
        responses: {
          'u1': CoordinationResponseType.useful.smallintValue,
          'u2': CoordinationResponseType.notSuitable.smallintValue,
        },
        expected: DerivedBeaconCoordinationStatus.moreOrDifferentHelpNeeded,
      ),
    ];

    for (final c in cases) {
      test(c.name, () {
        expect(
          deriveBeaconCoordinationStatus(
            activeOffers: c.activeOffers,
            responseTypeByOfferUserId: c.responses,
          ),
          c.expected,
        );
      });
    }
  });

  group('offerUnreviewedForStaleness (§8 rule 3 / future-arch §8.5)', () {
    final anchor = DateTime.utc(2026, 6, 1);

    test('responded offer is never stale', () {
      expect(
        offerUnreviewedForStaleness(
          offerCreatedAt: DateTime.utc(2026, 6, 10),
          coordinationStatusUpdatedAt: anchor,
          hasAuthorResponse: true,
        ),
        isFalse,
      );
    });

    test('no anchor treats missing response as stale', () {
      expect(
        offerUnreviewedForStaleness(
          offerCreatedAt: DateTime.utc(2026, 5, 1),
          coordinationStatusUpdatedAt: null,
        ),
        isTrue,
      );
    });

    test('offer created after anchor without response is stale', () {
      expect(
        offerUnreviewedForStaleness(
          offerCreatedAt: DateTime.utc(2026, 6, 10),
          coordinationStatusUpdatedAt: anchor,
        ),
        isTrue,
      );
    });

    test('offer created before anchor without response is not stale', () {
      expect(
        offerUnreviewedForStaleness(
          offerCreatedAt: DateTime.utc(2026, 5, 1),
          coordinationStatusUpdatedAt: anchor,
        ),
        isFalse,
      );
    });
  });

  group('staleness vs deriveBeaconCoordinationStatus', () {
    test('derive uses broader rule 2 even when §8.5 would not reset', () {
      final anchor = DateTime.utc(2026, 6, 1);
      final oldUnreviewed = _offer('legacy', createdAt: DateTime.utc(2026, 5, 1));
      final reviewed = _offer('reviewed', createdAt: DateTime.utc(2026, 6, 10));

      expect(
        offerUnreviewedForStaleness(
          offerCreatedAt: oldUnreviewed.createdAt,
          coordinationStatusUpdatedAt: anchor,
        ),
        isFalse,
      );

      expect(
        deriveBeaconCoordinationStatus(
          activeOffers: [oldUnreviewed, reviewed],
          responseTypeByOfferUserId: {
            'reviewed': CoordinationResponseType.useful.smallintValue,
          },
        ),
        DerivedBeaconCoordinationStatus.helpOffersWaitingForReview,
      );
    });
  });
}
