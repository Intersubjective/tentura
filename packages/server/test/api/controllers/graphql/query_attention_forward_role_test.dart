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

  // #665: accepting a bud invitation admits the helper too, and the row read
  // "<budder> accepted your offer". The bool `acceptedInvite` tells the
  // client which sentence to use, so it has to survive the allow-list.
  test('acceptedInvite survives the GraphQL allow-list as a bool', () {
    const invitePayload = {
      'helperStage': 'accepted',
      'actorUserId': 'u-author',
      'acceptedInvite': true,
    };
    final mapped = QueryAttention.mapReceiptForTesting(
      _forwardRow(invitePayload),
    );

    final payload =
        jsonDecode(mapped['presentationPayloadJson']! as String)
            as Map<String, Object?>;
    expect(payload['acceptedInvite'], isTrue);
    expect(payload['helperStage'], 'accepted');
    expect(
      () => QueryAttention.validateAttentionPresentationPayload(invitePayload),
      returnsNormally,
    );
  });

  // #725: a "not interested" row that answered an author invitation reads
  // "You said you can't make it"; the bool has to survive the allow-list.
  test('declinedInvite survives the GraphQL allow-list as a bool', () {
    const declinedPayload = {'declinedInvite': true};
    final mapped = QueryAttention.mapReceiptForTesting(
      _forwardRow(declinedPayload),
    );

    final payload =
        jsonDecode(mapped['presentationPayloadJson']! as String)
            as Map<String, Object?>;
    expect(payload['declinedInvite'], isTrue);
    expect(
      () =>
          QueryAttention.validateAttentionPresentationPayload(declinedPayload),
      returnsNormally,
    );
  });

  // #665 review: the client named the Request's author as the inviter; the
  // row now carries who actually sent the invite.
  test('inviterId survives the GraphQL allow-list', () {
    const invitePayload = {
      'helperStage': 'accepted',
      'acceptedInvite': true,
      'inviterId': 'u-steward',
    };
    final mapped = QueryAttention.mapReceiptForTesting(
      _forwardRow(invitePayload),
    );

    final payload =
        jsonDecode(mapped['presentationPayloadJson']! as String)
            as Map<String, Object?>;
    expect(payload['inviterId'], 'u-steward');
    expect(
      () => QueryAttention.validateAttentionPresentationPayload(invitePayload),
      returnsNormally,
    );
  });

  // #700: offer and invite-answer receipts name the actor at write time, so
  // the client need not parse the English title; the name must reach it.
  test('actorName survives the GraphQL allow-list', () {
    const offerPayload = {
      'eventType': 'offerAccepted',
      'actorUserId': 'u-alice',
      'actorName': 'Alice GQ2',
    };
    final mapped = QueryAttention.mapReceiptForTesting(
      _forwardRow(offerPayload),
    );

    final payload =
        jsonDecode(mapped['presentationPayloadJson']! as String)
            as Map<String, Object?>;
    expect(payload['actorName'], 'Alice GQ2');
    expect(
      () => QueryAttention.validateAttentionPresentationPayload(offerPayload),
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
