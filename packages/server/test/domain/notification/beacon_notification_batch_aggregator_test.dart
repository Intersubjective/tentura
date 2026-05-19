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

  test('mixed kinds uses coordination updates fallback', () {
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
    expect(r.body, contains('coordination updates'));
    expect(r.body, isNot(contains('new messages')));
  });
}
