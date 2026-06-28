import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/coordination/beacon_has_unreviewed_offers.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';

Beacon _beacon({
  BeaconStatus status = BeaconStatus.open,
  int helpOfferCount = 0,
  int unansweredHelpOfferCount = 0,
}) => Beacon(
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  id: 'b1',
  title: 'Test',
  author: const Profile(id: 'u1'),
  status: status,
  helpOfferCount: helpOfferCount,
  unansweredHelpOfferCount: unansweredHelpOfferCount,
);

void main() {
  test('true when open-family and unanswered offers exist', () {
    expect(
      beaconHasUnreviewedOffers(
        _beacon(
          status: BeaconStatus.enoughHelp,
          helpOfferCount: 2,
          unansweredHelpOfferCount: 1,
        ),
      ),
      isTrue,
    );
  });

  test(
    'false on enoughHelp when helpOfferCount > 0 but unanswered is 0 '
    '(broken aggregate: all offers reviewed)',
    () {
      expect(
        beaconHasUnreviewedOffers(
          _beacon(
            status: BeaconStatus.enoughHelp,
            helpOfferCount: 2,
            unansweredHelpOfferCount: 0,
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'true on enoughHelp when unanswered count is positive '
    '(fixed aggregate)',
    () {
      expect(
        beaconHasUnreviewedOffers(
          _beacon(
            status: BeaconStatus.enoughHelp,
            helpOfferCount: 2,
            unansweredHelpOfferCount: 1,
          ),
        ),
        isTrue,
      );
    },
  );

  test('false when no unanswered help offers', () {
    expect(beaconHasUnreviewedOffers(_beacon()), isFalse);
  });

  test('false when helpOfferCount exists but all are reviewed', () {
    expect(
      beaconHasUnreviewedOffers(
        _beacon(
          helpOfferCount: 3,
          unansweredHelpOfferCount: 0,
        ),
      ),
      isFalse,
    );
  });

  test('false when lifecycle is not open-family', () {
    expect(
      beaconHasUnreviewedOffers(
        _beacon(
          status: BeaconStatus.reviewOpen,
          helpOfferCount: 3,
          unansweredHelpOfferCount: 2,
        ),
      ),
      isFalse,
    );
  });
}
