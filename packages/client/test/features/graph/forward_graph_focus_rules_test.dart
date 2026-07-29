import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/graph/domain/forward_graph_focus_rules.dart';

void main() {
  group('resolveHelpOffererViewerRole', () {
    test('author when viewer is beacon author', () {
      expect(
        resolveHelpOffererViewerRole(
          viewerId: 'A',
          authorId: 'A',
          helpOffererId: 'H',
        ),
        ForwardsGraphViewerRole.author,
      );
    });

    test('self when viewer is the help offerer', () {
      expect(
        resolveHelpOffererViewerRole(
          viewerId: 'H',
          authorId: 'A',
          helpOffererId: 'H',
        ),
        ForwardsGraphViewerRole.self,
      );
    });

    test('involvedOther for any other viewer on the chain', () {
      expect(
        resolveHelpOffererViewerRole(
          viewerId: 'V',
          authorId: 'A',
          helpOffererId: 'H',
        ),
        ForwardsGraphViewerRole.involvedOther,
      );
    });
  });

  group('deriveHelpOffererGraphFocus', () {
    test('focuses help offerer for author and involved viewers', () {
      expect(
        deriveHelpOffererGraphFocus(
          viewerIsHelpOfferer: false,
          authorId: 'A',
          helpOffererId: 'H',
        ),
        'H',
      );
    });

    test('focuses author when viewer is the help offerer', () {
      expect(
        deriveHelpOffererGraphFocus(
          viewerIsHelpOfferer: true,
          authorId: 'A',
          helpOffererId: 'H',
        ),
        'A',
      );
    });
  });

  group('graphNodeShowsMeritRankRating', () {
    test('hides rating on viewer ego node', () {
      expect(
        graphNodeShowsMeritRankRating(nodeId: 'U1', viewerId: 'U1'),
        isFalse,
      );
    });

    test('shows rating on other user and beacon nodes', () {
      expect(
        graphNodeShowsMeritRankRating(nodeId: 'U2', viewerId: 'U1'),
        isTrue,
      );
      expect(
        graphNodeShowsMeritRankRating(nodeId: 'B1', viewerId: 'U1'),
        isTrue,
      );
    });
  });
}
