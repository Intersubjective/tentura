// #1068 real path: server-shaped AttentionFeed and ActivityOffersV2 rows →
// Ferry → AttentionRepository → pinned-zone predicate (no For you header
// when offers and pins are empty).

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_state.dart';
import 'package:tentura/features/inbox/ui/widget/activity_for_you_header_count.dart';

import '../../support/remote_wire_harness.dart';

Map<String, dynamic> _wireStreamReceipt(int i) => {
  '__typename': 'v2_AttentionReceipt',
  'id': 'Nactivity0000$i',
  'category': 'requestProgress',
  'kind': 'relayReceived',
  'priority': 'low',
  'title': 'Long title for layout $i',
  'body': 'Body',
  'actionUrl': '/#/beacon/view/Bstream0000$i',
  'createdAt': DateTime.now().toUtc().toIso8601String(),
  'seenAt': null,
  'collapsedCount': 1,
  'beaconId': 'Bstream0000$i',
  'coordinationItemId': null,
  'actorUserId': 'Uviewer000001',
  'sourceEventKey': 'relay:Bstream0000$i',
  'destinationKind': 'beacon',
  'targetEntityId': null,
  'presentationKey': 'relay_received',
  'presentationPayloadJson': '{}',
  'inAppPreferenceClass': null,
  'requiresAction': false,
  'attentionThreadKey': null,
  'settlementKind': null,
  'settledAt': null,
  'clearedAt': null,
  'clearReason': null,
  'surface': 'activity',
  'itemKind': 'receipt',
  'forwardOutcome': null,
  'forwardCount': null,
  'digestCount': null,
  'eventTotal': null,
  'eventUnseenCount': null,
  'provenanceJson': null,
  'beaconAuthorId': 'Uauthor00000$i',
  'beaconAuthorName': 'Author $i',
  'beaconAuthorImageId': null,
  'beaconImageId': null,
  'beaconEndAt': null,
  'allowsForward': true,
  'beaconTitle': 'Request $i',
  'beaconKind': 0,
  'postRootExcerpt': null,
  'postRootImageId': null,
  'eventsPreview': <Object?>[],
};

Map<String, dynamic> _activityFeed(List<Map<String, dynamic>> items) => {
  '__typename': 'query_root',
  'attentionFeed': {
    '__typename': 'v2_AttentionFeed',
    'summary': {
      '__typename': 'v2_AttentionSummary',
      'unreadTotal': items.length,
      'needsYouTotal': 0,
    },
    'page': {
      '__typename': 'v2_AttentionPage',
      'nextCursor': null,
      'items': items,
    },
  },
};

const _emptyOffers = {
  '__typename': 'query_root',
  'activityOffers': {
    '__typename': 'v2_ActivityOfferPage',
    'totalCount': 0,
    'nextCursor': null,
    'items': <Object?>[],
  },
};

void main() {
  test(
    'wire feed with four stream receipts and no offers is not a pinned zone',
    () async {
      final wireItems = [for (var i = 0; i < 4; i++) _wireStreamReceipt(i)];
      final sent = <WireSent>[];
      await withRemoteWire(
        {
          'AttentionFeed': _activityFeed(wireItems),
          'ActivityOffersV2': _emptyOffers,
        },
        sent,
        (remote) async {
          final repo = AttentionRepository(remote);
          final feed = await repo.fetch(
            view: AttentionView.all,
            surface: AttentionSurface.activity,
          );
          final offers = await repo.activityOffers(limit: 20);
          expect(feed.page.items, hasLength(4));
          expect(offers.items, isEmpty);
          expect(offers.totalCount, 0);
          expect(
            activityForYouPinnedZoneHasRows(
              offersState: const ActivityOffersState(
                hasMore: false,
                totalCount: 0,
              ),
              visiblePinnedCount: 0,
              pinnedPromptRows: false,
              collapsedInvitePrompt: false,
            ),
            isFalse,
          );
        },
      );
      expect(
        sent.map((s) => s.operationName).toSet(),
        {'AttentionFeed', 'ActivityOffersV2'},
      );
    },
  );
}
