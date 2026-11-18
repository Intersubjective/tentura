import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/notification_kind.dart';

import '../../support/test_attention_harness.dart';

void main() {
  final intents = TestAttentionHarness().intents;

  test('a first response to a Post links to the message in the Post', () async {
    final requestMessage = await intents.roomMessagePosted(
      beaconId: 'Brequest',
      messageId: 'Mrequest',
      actorUserId: 'responder',
      recipientUserIds: {'author'},
      excerpt: 'I can help',
      sourceEventKey: 'message:Mrequest',
    );
    expect(
      requestMessage.actionUrl,
      '/#/beacon/view/Brequest?tab=threads&thread=general'
      '&entry=deep_link&is_deep_link=true&message=Mrequest',
    );

    final postResponse = await intents.postFirstResponse(
      beaconId: 'Bpost',
      messageId: 'Mresponse',
      actorUserId: 'responder',
      authorUserId: 'author',
      excerpt: 'Count me in',
      sourceEventKey: 'message:Mresponse',
    );
    expect(postResponse.kind, NotificationKind.postFirstResponse);
    expect(
      postResponse.actionUrl,
      '/#/post/view/Bpost?tab=threads&thread=general'
      '&entry=deep_link&is_deep_link=true&message=Mresponse',
    );
  });

  test('a Post expiry warning links to the Post detail', () async {
    final requestStatus = await intents.requestStatusChanged(
      beaconId: 'Brequest',
      fromStatus: 'open',
      toStatus: 'closed',
      sourceEventKey: 'status:Brequest',
    );
    expect(
      requestStatus.actionUrl,
      '/#/beacon/view/Brequest?is_deep_link=true',
    );

    final expiry = await intents.postExpiringSoon(
      beaconId: 'Bpost',
      authorUserId: 'author',
    );
    expect(expiry.kind, NotificationKind.postExpiringSoon);
    expect(expiry.actionUrl, '/#/post/view/Bpost?is_deep_link=true');
  });
}
