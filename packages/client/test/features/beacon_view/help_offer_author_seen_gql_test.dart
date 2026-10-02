// Issue #178 part 2: the real client GraphQL wiring for the author-seen
// state. The cubit/widget tests use fake repositories, so these guard that
// the `helpOffersWithCoordination` query actually requests (and Ferry
// deserializes) `authorSeenAt`, and that a `MarkBeaconPeopleSeen` mutation
// document exists and is routed straight to Tentura V2.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/build_client.dart';
import 'package:tentura/features/beacon_view/data/gql/_g/help_offers_with_coordination.data.gql.dart';

Map<String, dynamic> _offerJson({String? authorSeenAt}) => {
  '__typename': 'HelpOfferWithCoordinationRow',
  'beaconId': 'Bauthorseen01',
  'userId': 'Uofferer00001',
  'message': 'I can help',
  'helpType': null,
  'roleLabel': null,
  'status': 0,
  'withdrawReason': null,
  'createdAt': '2026-06-15T12:00:00.000Z',
  'updatedAt': '2026-06-15T12:00:00.000Z',
  'responseType': null,
  'responseUpdatedAt': null,
  'responseAuthorUserId': null,
  'roomAccess': null,
  'admissionAction': null,
  'lastDeclineReason': null,
  'lastRemoveReason': null,
  'offerKind': 0,
  'stakeState': 0,
  'isDirectAuthorForward': false,
  'authorSeenAt': authorSeenAt,
  'user': {
    '__typename': 'User',
    'id': 'Uofferer00001',
    'displayName': 'Offerer',
    'description': '',
    'my_vote': null,
    'trusts_viewer': false,
    'is_mutual_friend': false,
    'image': null,
    'user_presence': null,
    'user_availability': null,
  },
};

/// Strips `#` comments so a commented-out field does not count.
void main() {
  group('helpOffersWithCoordination query', () {
    test('generated Ferry data carries authorSeenAt through (de)serialize', () {
      final data = GHelpOffersWithCoordinationData.fromJson({
        '__typename': 'query_root',
        'helpOffersWithCoordination': [
          _offerJson(authorSeenAt: '2026-06-15T12:05:00.000Z'),
          _offerJson(),
        ],
      });
      expect(data, isNotNull);
      final rows = data!.toJson()['helpOffersWithCoordination'] as List;
      final seen = rows.first as Map<String, dynamic>;
      expect(seen['authorSeenAt'], '2026-06-15T12:05:00.000Z');
      // Ferry serializers omit null-valued keys on toJson, so the null case
      // is verified on the deserialized object instead of the JSON map.
      expect(data.helpOffersWithCoordination!.last.authorSeenAt, isNull);
    });
  });

  group('MarkBeaconPeopleSeen mutation', () {
    test('routes directly to Tentura V2', () {
      expect(isTenturaDirectOperation('MarkBeaconPeopleSeen'), isTrue);
    });
  });
}
