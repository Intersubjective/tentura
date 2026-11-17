import 'package:test/test.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_policy.dart';

/// «Take it on together» receipts: the partner invitation and the partner's
/// answer are optional, not obligations, have no logical task and land on
/// the baton message.
void main() {
  const policy = AttentionPolicy();
  const role = AttentionRecipientRoleFacts(
    canReadBeaconContent: true,
    beaconId: 'B1',
    messageId: 'R1',
    actorUserId: 'U1',
    excerpt: 'Can someone take this?',
  );

  AttentionEventType type(String name) =>
      AttentionEventType.values.byName(name);
  AttentionRecipientReason reason(String name) =>
      AttentionRecipientReason.values.byName(name);

  for (final (typeName, reasonName) in [
    ('batonPartnerAsked', 'batonPartner'),
    ('batonPartnerAnswered', 'batonCandidate'),
  ]) {
    group(typeName, () {
      test('is optional and lands on the baton message', () {
        final projection = policy.project(
          eventType: type(typeName),
          recipientId: 'recipient',
          recipientReasons: {reason(reasonName)},
          role: role,
        );
        expect(projection.requiresAction, isFalse);
        expect(
          projection.suppressionClass,
          isNot(AttentionSuppressionClass.mandatory),
        );
        expect(
          projection.destination.kind,
          AttentionDestinationKind.beaconRoomMessage,
        );
        expect(projection.destination.targetEntityId, 'R1');
      });

      test('has no logical task', () {
        expect(
          policy.logicalTaskKey(
            eventType: type(typeName),
            recipientId: 'recipient',
            recipientReasons: {reason(reasonName)},
            role: role,
          ),
          isNull,
        );
      });
    });
  }

  test('a partner invitation is a personal event for the invited partner', () {
    expect(policy.canBePersonal(type('batonPartnerAsked')), isTrue);
    expect(
      AttentionPolicy.personalRecipientReasons,
      contains(reason('batonPartner')),
    );
    expect(
      policy.isPersonal(
        eventType: type('batonPartnerAsked'),
        recipientId: 'X',
        recipientReasons: {reason('batonPartner')},
        actorUserId: 'A',
      ),
      isTrue,
    );
  });
}
