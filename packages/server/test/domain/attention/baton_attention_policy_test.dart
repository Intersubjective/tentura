import 'package:test/test.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_policy.dart';

/// «Who'll take it?» (baton) — plan §3/B3
/// (`docs/plans/baton-who-takes-it-plan.md`): each of the three event types
/// is optional (D5), not an obligation, has no logical task, and lands on
/// the source room message.
void main() {
  const policy = AttentionPolicy();
  const role = AttentionRecipientRoleFacts(
    canReadBeaconContent: true,
    beaconId: 'B1',
    messageId: 'R1',
    actorUserId: 'U1',
    excerpt: 'Can someone take this?',
  );

  for (final (eventType, reason) in [
    (AttentionEventType.batonAsked, AttentionRecipientReason.batonCandidate),
    (AttentionEventType.batonTaken, AttentionRecipientReason.batonTaker),
    (
      AttentionEventType.batonAllAnswered,
      AttentionRecipientReason.batonAuthor,
    ),
  ]) {
    group(eventType.name, () {
      final reasons = {reason};

      test('requiresAction is false', () {
        final projection = policy.project(
          eventType: eventType,
          recipientId: 'recipient',
          recipientReasons: reasons,
          role: role,
        );
        expect(projection.requiresAction, isFalse);
      });

      test('logicalTaskKey is null', () {
        expect(
          policy.logicalTaskKey(
            eventType: eventType,
            recipientId: 'recipient',
            recipientReasons: reasons,
            role: role,
          ),
          isNull,
        );
      });

      test('destination is the room message', () {
        final projection = policy.project(
          eventType: eventType,
          recipientId: 'recipient',
          recipientReasons: reasons,
          role: role,
        );
        expect(
          projection.destination.kind,
          AttentionDestinationKind.beaconRoomMessage,
        );
        expect(projection.destination.targetEntityId, role.messageId);
      });

      test('reason is accepted (beacon-scoped relationship satisfied)', () {
        expect(
          () => policy.project(
            eventType: eventType,
            recipientId: 'recipient',
            recipientReasons: reasons,
            role: role,
          ),
          returnsNormally,
        );
      });

      test('is never an obligation and is not suppressed', () {
        final projection = policy.project(
          eventType: eventType,
          recipientId: 'recipient',
          recipientReasons: reasons,
          role: role,
        );
        expect(
          projection.suppressionClass,
          isNot(AttentionSuppressionClass.mandatory),
        );
      });
    });
  }
}
