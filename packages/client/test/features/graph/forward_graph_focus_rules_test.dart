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

  group('isolatedHelpOffererPositionHint', () {
    test('keeps default hint 0 unchanged', () {
      expect(isolatedHelpOffererPositionHint(0), 0);
    });

    test('replaces null and non-zero hints with stable north placement', () {
      expect(isolatedHelpOffererPositionHint(null), 4);
      expect(isolatedHelpOffererPositionHint(2), 4);
      expect(isolatedHelpOffererPositionHint(7), 4);
    });

    test('respects custom north hint constant', () {
      expect(isolatedHelpOffererPositionHint(3, northHint: 5), 5);
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
