import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/coordination/viewer_offer_accepted.dart';

void main() {
  group('isViewerOfferAccepted (B077, review of #511)', () {
    final admitted = BeaconAccessReason.admitted.bit;

    test('admitted with an active offer is accepted', () {
      expect(
        isViewerOfferAccepted(hasActiveOffer: true, viewerAccessReasons: admitted),
        isTrue,
      );
    });

    test('not admitted (pending, declined or removed) is not accepted', () {
      expect(
        isViewerOfferAccepted(
          hasActiveOffer: true,
          viewerAccessReasons: BeaconAccessReason.applied.bit,
        ),
        isFalse,
      );
    });

    test('a withdrawn offer is not accepted even while admitted', () {
      expect(
        isViewerOfferAccepted(
          hasActiveOffer: false,
          viewerAccessReasons: admitted,
        ),
        isFalse,
      );
    });
  });
}
