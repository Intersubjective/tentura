import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/notification/beacon_notification_batch_aggregator.dart';

void main() {
  const aggregator = BeaconNotificationBatchAggregator();

  test('single notification passes through title and body', () {
    final r = aggregator.aggregate(
      count: 1,
      dominantKind: NotificationKind.needsMe,
      latestTitle: 'T',
      latestBody: 'B',
      beaconTitle: null,
      kindCounts: {NotificationKind.needsMe: 1},
    );
    expect(r.title, 'T');
    expect(r.body, 'B');
  });

  test('plural body never says new messages', () {
    final r = aggregator.aggregate(
      count: 3,
      dominantKind: NotificationKind.needsMe,
      latestTitle: 'Ask',
      latestBody: 'Fix wiring',
      beaconTitle: 'Beacon A',
      kindCounts: {NotificationKind.needsMe: 3},
    );
    expect(r.body, isNot(contains('new messages')));
    expect(r.body, contains('3 items need you'));
  });

  test('staleRemind plural body', () {
    final r = aggregator.aggregate(
      count: 2,
      dominantKind: NotificationKind.staleRemind,
      latestTitle: 'Ask title',
      latestBody: 'Still open',
      beaconTitle: 'Beacon A',
      kindCounts: {NotificationKind.staleRemind: 2},
    );
    expect(r.body, contains('need attention'));
    expect(r.body, isNot(contains('Overdue')));
  });

  test('single actionable kind in a mixed batch leads with its phrasing', () {
    final r = aggregator.aggregate(
      count: 4,
      dominantKind: NotificationKind.promiseMade,
      latestTitle: 'Latest',
      latestBody: 'detail',
      beaconTitle: 'My beacon',
      kindCounts: {
        NotificationKind.needsMe: 2,
        NotificationKind.promiseMade: 2,
      },
    );
    expect(r.title, 'My beacon');
    // One actionable kind (needsMe) dominates: use its specific phrasing over
    // the whole count rather than a generic "coordination updates" line.
    expect(r.body, '4 items need you, including: detail');
  });

  test('multiple actionable kinds fall back to generic copy', () {
    final r = aggregator.aggregate(
      count: 4,
      dominantKind: NotificationKind.needsMe,
      latestTitle: 'Latest',
      latestBody: 'detail',
      beaconTitle: 'My beacon',
      kindCounts: {
        NotificationKind.needsMe: 2,
        NotificationKind.blockerOpened: 2,
      },
    );
    expect(r.title, 'My beacon');
    expect(r.body, contains('coordination updates'));
  });
}
