import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';

import '../../support/test_attention_harness.dart';

void main() {
  const actor = 'actor';
  const target = 'target';
  const author = 'author';
  const beacon = 'beacon';
  const eventKey = 'source:event';

  final harness = TestAttentionHarness();

  Future<String> relayBody(
    AttentionIntentCase intents, {
    BeaconKind? beaconKind,
  }) async {
    final intent = beaconKind == null
        ? await intents.relayReceived(
            beaconId: beacon,
            senderId: actor,
            beaconAuthorId: author,
            recipientIds: const [target],
            sourceEventKey: eventKey,
          )
        : await intents.relayReceived(
            beaconId: beacon,
            senderId: actor,
            beaconAuthorId: author,
            recipientIds: const [target],
            sourceEventKey: eventKey,
            beaconKind: beaconKind,
          );
    expect(intent.kind, NotificationKind.newRelay);
    expect(intent.recipients.map((r) => r.recipientId), [target]);
    return intent.body;
  }

  group('relay attention intent copy', () {
    test('a Post arrival says a post was shared with the recipient', () async {
      expect(
        await relayBody(harness.intents, beaconKind: BeaconKind.post),
        'Actor shared a post with you',
      );
    });

    test('a Request arrival says a request was forwarded', () async {
      expect(
        await relayBody(harness.intents, beaconKind: BeaconKind.request),
        'Actor forwarded a request to you',
      );
    });

    test('an arrival without a stated kind is a Request', () async {
      expect(
        await relayBody(harness.intents),
        'Actor forwarded a request to you',
      );
    });
  });

  group('first response attention intent copy', () {
    Future<String> firstResponseBody(String excerpt) async {
      final intent = await harness.intents.postFirstResponse(
        beaconId: beacon,
        messageId: 'message',
        actorUserId: actor,
        authorUserId: author,
        excerpt: excerpt,
        sourceEventKey: eventKey,
      );
      expect(intent.kind, NotificationKind.postFirstResponse);
      return intent.body;
    }

    test('without text says the actor replied to the post', () async {
      expect(await firstResponseBody(''), 'Actor replied to your post');
    });

    test('with text shows the text', () async {
      expect(await firstResponseBody('Count me in'), 'Count me in');
    });
  });
}
