import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/data/model/beacon_model.dart';

/// B055 review (#393): `helpOfferCount` merges active help offers and
/// participant-path offers. Before this rule the two lists were added, so an
/// accepted regular offer (active offer row + committed participant row)
/// counted twice.
void main() {
  group('countActiveHelpers', () {
    test('counts a user with an active offer and a participant row once', () {
      expect(
        countActiveHelpers(
          offerUserIds: const ['U1'],
          participantUserIds: const ['U1'],
        ),
        1,
      );
    });

    test('adds distinct helpers from both sources', () {
      expect(
        countActiveHelpers(
          offerUserIds: const ['U1', 'U2'],
          participantUserIds: const ['U2', 'U3'],
        ),
        3,
      );
    });

    test('is zero when nobody is still in', () {
      expect(
        countActiveHelpers(
          offerUserIds: const [],
          participantUserIds: const [],
        ),
        0,
      );
    });
  });
}
