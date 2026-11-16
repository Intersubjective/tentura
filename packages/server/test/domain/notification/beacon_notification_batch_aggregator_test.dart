import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/notification/beacon_notification_batch_aggregator.dart';

void main() {
  const aggregator = BeaconNotificationBatchAggregator();

  test('roomMention is actionable and has a plural body', () {
    final dominant = aggregator.pickDominantKind({
      NotificationKind.roomMention: 2,
      NotificationKind.coordinationChanged: 3,
    });
    expect(dominant, NotificationKind.roomMention);

    final copy = aggregator.collapsed(
      count: 2,
      locale: 'en',
      entityLabel: 'Need help',
      latestSentence: 'hello',
      kindCounts: {NotificationKind.roomMention: 2},
    );
    expect(copy.body, contains('mentions of you'));
    expect(copy.body, contains('hello'));
  });
}
