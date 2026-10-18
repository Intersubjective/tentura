import 'dart:convert';

import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_policy.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

/// #381 guard — the author's decline reason already reaches the declined
/// helper's client as the `offerDeclined` receipt's `excerpt`, through the
/// GraphQL allow-list. The fix is client-side (the Activity card); this pins
/// that the wire keeps carrying the reason and that no new key is needed.
void main() {
  const reason = 'Thanks, but we already found a van';

  Map<String, Object?> wirePayload({required bool canRead}) {
    final projection = const AttentionPolicy().project(
      eventType: AttentionEventType.offerDeclined,
      recipientId: 'helper',
      recipientReasons: const {AttentionRecipientReason.affectedParticipant},
      role: AttentionRecipientRoleFacts(
        canReadBeaconContent: canRead,
        beaconId: 'beacon-1',
        targetEntityId: 'helper',
        actorUserId: 'author',
        excerpt: reason,
      ),
    );
    final mapped = QueryAttention.mapReceiptForTesting(
      AttentionReceipt(
        id: 'receipt-1',
        accountId: 'helper',
        category: NotificationCategory.coordination,
        kind: NotificationKind.commitmentDeclined,
        priority: NotificationPriority.normal,
        title: 'Offer declined',
        body: reason,
        actionUrl: '/#/beacon/beacon-1',
        createdAt: DateTime.utc(2026, 10, 14),
        collapsedCount: 1,
        suppressionClass: AttentionSuppressionClass.standard,
        accessPolicy: projection.accessPolicy,
        presentationKey: projection.presentationKey,
        presentationPayload: projection.presentationPayload,
        surface: AttentionSurface.activity,
      ),
    );
    return jsonDecode(mapped['presentationPayloadJson']! as String)
        as Map<String, Object?>;
  }

  test('a helper who could read the Request gets the reason as excerpt', () {
    final payload = wirePayload(canRead: true);
    expect(payload['eventType'], 'offerDeclined');
    expect(payload['actorUserId'], 'author');
    expect(payload['excerpt'], reason);
  });

  test('a recipient-safe decline still carries no words (privacy guard)', () {
    expect(wirePayload(canRead: false)['excerpt'], '');
  });
}
