import 'package:test/test.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

// Pins NotificationOutboxItemEntity.accessPolicy as AttentionAccessPolicy:
// the repository decodes `notification_outbox.access_policy` with
// attentionAccessPolicyFromWireName, so a value outside the DB CHECK
// (notification_outbox__access_policy_chk) now throws instead of being kept
// as a raw string.
void main() {
  test('every wire name decodes to its policy', () {
    for (final policy in AttentionAccessPolicy.values) {
      expect(attentionAccessPolicyFromWireName(policy.wireName), policy);
    }
    expect(
      attentionAccessPolicyFromWireName('beacon_content'),
      AttentionAccessPolicy.beaconContent,
    );
  });

  test('an unknown wire name throws StateError', () {
    expect(
      () => attentionAccessPolicyFromWireName('beaconContent'),
      throwsStateError,
    );
  });

  test('the entity default is legacy', () {
    final item = NotificationOutboxItemEntity(
      id: 'N1',
      accountId: 'U1',
      kind: NotificationKind.values.first,
      category: NotificationCategory.values.first,
      priority: NotificationPriority.values.first,
      title: 't',
      body: 'b',
      actionUrl: '/',
      createdAt: DateTime.utc(2026),
      collapsedCount: 1,
    );
    expect(item.accessPolicy, AttentionAccessPolicy.legacy);
    expect(item.accessPolicy.wireName, 'legacy');
  });
}
