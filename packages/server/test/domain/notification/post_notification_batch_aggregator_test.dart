import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/notification/beacon_notification_batch_aggregator.dart';

void main() {
  const aggregator = BeaconNotificationBatchAggregator();

  ({String title, String body}) collapse({
    required Map<NotificationKind, int> kindCounts,
    BeaconKind? beaconKind,
    String latestBody = '',
  }) {
    final count = kindCounts.values.fold(0, (a, b) => a + b);
    return aggregator.collapsed(
      count: count,
      locale: 'en',
      entityLabel: null,
      latestSentence: latestBody,
      kindCounts: kindCounts,
      beaconKind: beaconKind ?? BeaconKind.request,
    );
  }

  group('Post batches', () {
    test('two Post arrivals read as posts shared with you', () {
      final copy = collapse(
        kindCounts: {NotificationKind.newRelay: 2},
        beaconKind: BeaconKind.post,
      );

      expect(copy.body, '2 posts shared with you');
    });

    test('keeps the latest text after the Post arrival count', () {
      final copy = collapse(
        kindCounts: {NotificationKind.newRelay: 2},
        beaconKind: BeaconKind.post,
        latestBody: 'Alice shared a post with you',
      );

      expect(
        copy.body,
        '2 posts shared with you, including: Alice shared a post with you',
      );
    });

    test('first responses read as replies to your posts', () {
      final copy = collapse(
        kindCounts: {NotificationKind.postFirstResponse: 3},
        beaconKind: BeaconKind.post,
      );

      expect(copy.body, '3 replies to your posts');
    });

    test('a kind without specific wording falls back to post updates', () {
      final copy = collapse(
        kindCounts: {NotificationKind.roomActivityLowPriority: 2},
        beaconKind: BeaconKind.post,
      );

      expect(copy.body, '2 post updates');
    });
  });

  group('Request batches', () {
    test('Request arrivals still read as requests forwarded to you', () {
      expect(
        collapse(kindCounts: {NotificationKind.newRelay: 2}).body,
        '2 requests forwarded to you',
      );
      expect(
        collapse(
          kindCounts: {NotificationKind.newRelay: 2},
          beaconKind: BeaconKind.request,
        ).body,
        '2 requests forwarded to you',
      );
    });

    test('a kind without specific wording keeps request updates', () {
      expect(
        collapse(
          kindCounts: {NotificationKind.roomActivityLowPriority: 2},
          beaconKind: BeaconKind.request,
        ).body,
        '2 request updates',
      );
    });
  });
}
