import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_policy.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

void main() {
  const fullPayload = {
    'eventType': 'commitmentAccepted',
    'actorUserId': 'actor-1',
    'beaconId': 'beacon-1',
    'coordinationItemId': 'item-1',
    'targetEntityId': 'target-1',
    'messageId': 'message-1',
    'beaconTitle': 'Garden cleanup',
    'inviteOrigin': 'new_account',
  };

  test('maps payload with every allowed key including beaconTitle', () {
    final mapped = QueryAttention.mapReceiptForTesting(_receipt(fullPayload));

    expect(mapped['presentationPayloadJson'], isNotEmpty);
    expect(mapped['id'], 'receipt-1');
    expect(
      () => QueryAttention.validateAttentionPresentationPayload(fullPayload),
      returnsNormally,
    );
  });

  test('policy presentation payload survives GraphQL allow-list', () {
    const policy = AttentionPolicy();
    final projection = policy.project(
      eventType: AttentionEventType.commitmentAccepted,
      recipientId: 'recipient',
      recipientReasons: const {AttentionRecipientReason.targetOfAsk},
      role: const AttentionRecipientRoleFacts(
        canReadBeaconContent: true,
        beaconId: 'beacon-1',
        coordinationItemId: 'item-1',
        targetEntityId: 'target-1',
        messageId: 'message-1',
        actorUserId: 'actor-1',
        beaconTitle: 'Garden cleanup',
      ),
    );

    expect(
      () => QueryAttention.mapReceiptForTesting(
        _receipt(projection.presentationPayload),
      ),
      returnsNormally,
    );
  });

  test('rejects unknown presentation payload keys', () {
    expect(
      () => QueryAttention.validateAttentionPresentationPayload({
        ...fullPayload,
        'junkKey': 'must not leak',
      }),
      throwsA(isA<StateError>()),
    );
    expect(
      () => QueryAttention.mapReceiptForTesting(
        _receipt({...fullPayload, 'junkKey': 'must not leak'}),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects non-string presentation payload values', () {
    expect(
      () => QueryAttention.validateAttentionPresentationPayload({
        ...fullPayload,
        'beaconTitle': 42,
      }),
      throwsA(isA<StateError>()),
    );
    expect(
      () => QueryAttention.mapReceiptForTesting(
        _receipt({...fullPayload, 'beaconTitle': 42}),
      ),
      throwsA(isA<StateError>()),
    );
  });
}

AttentionReceipt _receipt(Map<String, Object?> presentationPayload) =>
    AttentionReceipt(
      id: 'receipt-1',
      accountId: 'account-1',
      category: NotificationCategory.coordination,
      kind: NotificationKind.commitmentAccepted,
      priority: NotificationPriority.normal,
      title: 'Title',
      body: 'Body',
      actionUrl: '/#/beacon/beacon-1',
      createdAt: DateTime.utc(2026, 8, 4),
      collapsedCount: 1,
      suppressionClass: AttentionSuppressionClass.standard,
      accessPolicy: AttentionAccessPolicy.beaconContent,
      presentationPayload: presentationPayload,
    );
