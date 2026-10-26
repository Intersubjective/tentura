import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.data.gql.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';

void main() {
  group('Constellation Post lifecycle mapping', () {
    for (final status in [0, 6]) {
      test('preserves expiry and status $status from the field response', () {
        final payload = GConstellationFieldFetchData.fromJson({
          '__typename': 'query_root',
          'constellationField': {
            '__typename': 'v2_ConstellationField',
            'loadedAt': '2026-10-26T12:00:00.000Z',
            'context': '',
            'peersCapped': false,
            'requestsCapped': false,
            'directContactIds': <String>[],
            'peers': <dynamic>[],
            'edges': <dynamic>[],
            'requests': <dynamic>[],
            'posts': [
              {
                '__typename': 'v2_ConstellationPost',
                'id': 'Bpost00000001',
                'authorId': 'Uauthor000001',
                'lastActivityAt': '2026-10-25T12:00:00.000Z',
                'rootExcerpt': 'Who has a ladder?',
                'isPinned': true,
                'hiddenReachCount': 0,
                'expiresAt': '2026-10-26T16:00:00+02:00',
                'status': status,
              },
            ],
            'memberWebs': <dynamic>[],
            'anchorProjection': {
              '__typename': 'v2_ConstellationAnchorProjection',
              'revision': '0',
              'anchors': <dynamic>[],
              'pinnedPeers': <dynamic>[],
              'pinnedRequests': <dynamic>[],
              'supportPeers': <dynamic>[],
              'supportEdges': <dynamic>[],
              'serverFilteredBeaconIds': <String>[],
              'serverFilteredBeaconCount': 0,
            },
          },
        })!;
        final post = mapConstellationFieldFromFieldFetch(
          payload.constellationField,
        ).posts.single;

        expect(post.expiresAt, DateTime.utc(2026, 10, 26, 14));
        // Like ConstellationRequest.status, this carries the wire smallint.
        expect(post.status, status);
      });
    }
  });
}
