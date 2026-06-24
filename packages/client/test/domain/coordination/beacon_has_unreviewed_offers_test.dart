import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/coordination/beacon_has_unreviewed_offers.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';

Beacon _beacon({
  BeaconStatus status = BeaconStatus.open,
  int helpOfferCount = 0,
}) =>
    Beacon(
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      id: 'b1',
      title: 'Test',
      author: const Profile(id: 'u1'),
      status: status,
      helpOfferCount: helpOfferCount,
    );

void main() {
  test('true when neutral coordination and help offers exist', () {
    expect(
      beaconHasUnreviewedOffers(_beacon(helpOfferCount: 2)),
      isTrue,
    );
  });

  test('false when no help offers', () {
    expect(beaconHasUnreviewedOffers(_beacon()), isFalse);
  });

  test('false when coordination status is not neutral', () {
    expect(
      beaconHasUnreviewedOffers(
        _beacon(
          status: BeaconStatus.enoughHelp,
          helpOfferCount: 3,
        ),
      ),
      isFalse,
    );
  });
}
