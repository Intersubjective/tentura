import 'dart:convert';

import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

/// #367: an accepted helper's Activity forward row stays 'helping' on the
/// wire and carries its stage (`helperStage`) and the role the author gave
/// the offer (`roleLabel`) in the payload. The GraphQL mapper keeps only
/// allow-listed payload keys, so both have to survive it, or the client
/// never sees them.
void main() {
  test('helperStage and roleLabel survive the GraphQL allow-list', () {
    const stagePayload = {'helperStage': 'accepted', 'roleLabel': 'Driver'};
    final mapped = QueryAttention.mapReceiptForTesting(
      _forwardRow(stagePayload),
    );

    final payload =
        jsonDecode(mapped['presentationPayloadJson']! as String)
            as Map<String, Object?>;
    expect(payload['helperStage'], 'accepted');
    expect(payload['roleLabel'], 'Driver');
    // Old clients only know 'helping'; the stage rides the payload.
    expect(mapped['forwardOutcome'], 'helping');
    expect(
      () => QueryAttention.validateAttentionPresentationPayload(stagePayload),
      returnsNormally,
    );
  });
}

AttentionReceipt _forwardRow(Map<String, Object?> presentationPayload) =>
    AttentionReceipt(
      id: 'inbox:beacon-1',
      accountId: 'account-1',
      category: NotificationCategory.coordination,
      kind: NotificationKind.newRelay,
      priority: NotificationPriority.normal,
      title: 'Move the couch',
      body: '',
      actionUrl: '/#/view?id=beacon-1',
      createdAt: DateTime.utc(2026, 10, 14),
      collapsedCount: 0,
      suppressionClass: AttentionSuppressionClass.standard,
      accessPolicy: AttentionAccessPolicy.beaconContent,
      presentationPayload: presentationPayload,
      surface: AttentionSurface.activity,
      itemKind: AttentionItemKind.forward,
      forwardOutcome: 'helping',
      beaconId: 'beacon-1',
    );
