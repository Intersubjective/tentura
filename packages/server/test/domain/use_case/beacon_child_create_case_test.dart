import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/domain/policy/beacon_promotion_eligibility_policy.dart';

void main() {
  group('BeaconPromotionEligibilityPolicy', () {
    test('accepts ordinary General human message with empty body', () {
      expect(
        BeaconPromotionEligibilityPolicy.isEligible(
          const BeaconPromotionSourceFacts(
            messageId: 'R1',
            beaconId: 'B1',
            authorId: 'U1',
            body: '',
          ),
        ),
        isTrue,
      );
    });

    test('rejects missing author', () {
      expect(
        BeaconPromotionEligibilityPolicy.isEligible(
          const BeaconPromotionSourceFacts(
            messageId: 'R1',
            beaconId: 'B1',
            authorId: null,
            body: 'hello',
          ),
        ),
        isFalse,
      );
    });

    test('rejects non-General thread scope', () {
      expect(
        BeaconPromotionEligibilityPolicy.isEligible(
          const BeaconPromotionSourceFacts(
            messageId: 'R1',
            beaconId: 'B1',
            authorId: 'U1',
            body: 'hello',
            threadItemId: 'Iask',
          ),
        ),
        isFalse,
      );
    });

    test('rejects system messages and semantic markers', () {
      expect(
        BeaconPromotionEligibilityPolicy.isEligible(
          BeaconPromotionSourceFacts(
            messageId: 'R1',
            beaconId: 'B1',
            authorId: 'U1',
            body: 'hello',
            systemMessageKind: BeaconRoomSystemMessageKind.childCreated,
          ),
        ),
        isFalse,
      );
      expect(
        BeaconPromotionEligibilityPolicy.isEligible(
          const BeaconPromotionSourceFacts(
            messageId: 'R1',
            beaconId: 'B1',
            authorId: 'U1',
            body: 'hello',
            semanticMarker: 1,
          ),
        ),
        isFalse,
      );
    });

    test('rejects linked coordination and polling objects', () {
      expect(
        BeaconPromotionEligibilityPolicy.isEligible(
          const BeaconPromotionSourceFacts(
            messageId: 'R1',
            beaconId: 'B1',
            authorId: 'U1',
            body: 'hello',
            linkedItemId: 'Iplan',
          ),
        ),
        isFalse,
      );
      expect(
        BeaconPromotionEligibilityPolicy.isEligible(
          const BeaconPromotionSourceFacts(
            messageId: 'R1',
            beaconId: 'B1',
            authorId: 'U1',
            body: 'hello',
            linkedPollingId: 'P1',
          ),
        ),
        isFalse,
      );
    });
  });
}
