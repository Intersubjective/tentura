import 'package:test/test.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_policy.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';

/// The author of a Post hears about the first response of each member once.
/// The receipt is addressed to the Post author (reason `postAuthor`), opens
/// the response's message, and is an optional, mutable, primary update.
void main() {
  const policy = AttentionPolicy();
  const role = AttentionRecipientRoleFacts(
    canReadBeaconContent: true,
    beaconId: 'beacon-1',
    messageId: 'message-1',
    actorUserId: 'responder-1',
    excerpt: 'Count me in',
  );
  const reasons = {AttentionRecipientReason.postAuthor};

  test('the event type is declared and reachable by its name', () {
    expect(
      attentionEventTypeFromWireName('postFirstResponse'),
      AttentionEventType.postFirstResponse,
    );
    expect(
      () => AttentionEventTypeCatalog.assertDeclared(
        AttentionEventType.postFirstResponse,
      ),
      returnsNormally,
    );
  });

  test('the post-author reason is a relationship to the Beacon', () {
    expect(AttentionRecipientReason.postAuthor.isBeaconRelationship, isTrue);
  });

  group('projection for the Post author', () {
    final projection = policy.project(
      eventType: AttentionEventType.postFirstResponse,
      recipientId: 'author-1',
      recipientReasons: reasons,
      role: role,
    );

    test('is keyed and placed like a primary room update', () {
      expect(projection.presentationKey, 'post_first_response');
      expect(
        policy.placement(AttentionEventType.postFirstResponse).wireName,
        'primary',
      );
      expect(projection.accessPolicy, AttentionAccessPolicy.beaconContent);
    });

    test('can be muted', () {
      expect(projection.suppressionClass, AttentionSuppressionClass.standard);
    });

    test('opens the message of the response', () {
      expect(
        projection.destination.kind,
        AttentionDestinationKind.beaconRoomMessage,
      );
      expect(projection.destination.targetEntityId, 'message-1');
    });

    test('names the responder and shows the words', () {
      expect(projection.presentationPayload['eventType'], 'postFirstResponse');
      expect(projection.presentationPayload['actorUserId'], 'responder-1');
      expect(projection.presentationPayload['excerpt'], 'Count me in');
    });
  });

  test('a recipient with no relationship to the Post is refused', () {
    expect(
      () => policy.project(
        eventType: AttentionEventType.postFirstResponse,
        recipientId: 'someone',
        recipientReasons: const {AttentionRecipientReason.inviter},
        role: role,
      ),
      throwsArgumentError,
    );
  });

  test('the push kind exists and is grouped with coordination updates', () {
    expect(
      categoryOf(NotificationKind.postFirstResponse),
      NotificationCategory.coordination,
    );
  });
}
