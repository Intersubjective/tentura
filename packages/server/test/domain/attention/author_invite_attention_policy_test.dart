import 'package:test/test.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_policy.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';

import '../../support/fake_user_block_repository.dart';
import '../../support/test_attention_harness.dart';

/// Post→Request budding, plan unit C2 (Arch §5.6): the author-invite events.
///
/// * `authorInviteReceived` goes to the invitee: an optional update in
///   Activity, collapsed per Request, push allowed (like `relayReceived`).
/// * `authorInviteAccepted` / `authorInviteDeclined` go to the inviter: an
///   optional update, no push.
///
/// None of them is an obligation.
void main() {
  const policy = AttentionPolicy();
  const beacon = 'Bchild000001';
  const inviter = 'Uinviter0001';
  const invitee = 'Uinvitee0001';
  const inviteId = 'Iinvite00001';
  const role = AttentionRecipientRoleFacts(
    canReadBeaconContent: true,
    beaconId: beacon,
    targetEntityId: invitee,
    actorUserId: inviter,
  );

  const cases = [
    (
      AttentionEventType.authorInviteReceived,
      AttentionRecipientReason.authorInvitee,
    ),
    (
      AttentionEventType.authorInviteAccepted,
      AttentionRecipientReason.authorInviter,
    ),
    (
      AttentionEventType.authorInviteDeclined,
      AttentionRecipientReason.authorInviter,
    ),
  ];

  group('AttentionPolicy', () {
    for (final (eventType, reason) in cases) {
      group(eventType.name, () {
        AttentionReceiptProjection project() => policy.project(
          eventType: eventType,
          recipientId: 'recipient',
          recipientReasons: {reason},
          role: role,
        );

        test('is declared in the catalog', () {
          expect(
            () => AttentionEventTypeCatalog.assertDeclared(eventType),
            returnsNormally,
          );
        });

        test('is an optional update, never an obligation', () {
          final projection = project();
          expect(projection.requiresAction, isFalse);
          expect(projection.attentionThreadKey, isNull);
          expect(
            policy.logicalTaskKey(
              eventType: eventType,
              recipientId: 'recipient',
              recipientReasons: {reason},
              role: role,
            ),
            isNull,
          );
        });

        test('is a standard coordination update on the primary surface', () {
          final projection = project();
          expect(
            projection.suppressionClass,
            AttentionSuppressionClass.standard,
          );
          expect(projection.category, NotificationCategory.coordination);
          expect(projection.accessPolicy, AttentionAccessPolicy.beaconContent);
          expect(policy.placement(eventType), AttentionPlacement.primary);
        });

        test('its reason proves a relationship to the Request', () {
          expect(reason.isBeaconRelationship, isTrue);
          expect(eventType.isBeaconScoped, isTrue);
        });
      });
    }

    test('the invitee lands on the Request', () {
      final projection = policy.project(
        eventType: AttentionEventType.authorInviteReceived,
        recipientId: invitee,
        recipientReasons: const {AttentionRecipientReason.authorInvitee},
        role: role.copyWith(targetEntityId: inviteId),
      );
      expect(projection.destination.kind, AttentionDestinationKind.beacon);
      expect(projection.destination.targetEntityId, beacon);
      expect(projection.presentationKey, 'author_invite_received');
      expect(projection.presentationPayload['targetEntityId'], inviteId);
    });

    for (final (eventType, key) in const [
      (AttentionEventType.authorInviteAccepted, 'author_invite_accepted'),
      (AttentionEventType.authorInviteDeclined, 'author_invite_declined'),
    ]) {
      test('${eventType.name} lands on the invitee in People', () {
        final projection = policy.project(
          eventType: eventType,
          recipientId: inviter,
          recipientReasons: const {AttentionRecipientReason.authorInviter},
          role: role,
        );
        expect(
          projection.destination.kind,
          AttentionDestinationKind.beaconPeopleOffer,
        );
        expect(projection.destination.targetEntityId, invitee);
        expect(projection.presentationKey, key);
      });
    }
  });

  group('AttentionIntentCase', () {
    test('authorInviteReceived: invitee only, push allowed, collapsed per '
        'Request', () async {
      final harness = TestAttentionHarness();
      final intent = await harness.intents.authorInviteReceived(
        beaconId: beacon,
        inviteId: inviteId,
        inviterUserId: inviter,
        inviteeUserId: invitee,
        note: 'You know the area',
        sourceEventKey: 'author_invite:$inviteId',
      );

      expect(intent.eventType, AttentionEventType.authorInviteReceived);
      expect(intent.kind, NotificationKind.authorInviteReceived);
      expect(intent.actorUserId, inviter);
      expect(intent.beaconId, beacon);
      expect(intent.recipients, hasLength(1));
      final recipient = intent.recipients.single;
      expect(recipient.recipientId, invitee);
      expect(recipient.reasons, {AttentionRecipientReason.authorInvitee});
      expect(recipient.channelEligible, isTrue);
      expect(recipient.role.targetEntityId, inviteId);
      expect(recipient.role.excerpt, 'You know the area');
      expect(
        intent.collapseKey,
        AttentionCollapseKey.family('authorInviteReceived', [beacon]),
      );
      expect(intent.actionUrl, contains(beacon));
    });

    test('authorInviteReceived collapses invites on one Request together and '
        'keeps Requests apart', () async {
      final harness = TestAttentionHarness();
      Future<String> key(String beaconId, String id) async =>
          (await harness.intents.authorInviteReceived(
            beaconId: beaconId,
            inviteId: id,
            inviterUserId: inviter,
            inviteeUserId: invitee,
            sourceEventKey: 'author_invite:$id',
          )).collapseKey;

      expect(await key(beacon, 'I1'), await key(beacon, 'I2'));
      expect(await key(beacon, 'I1'), isNot(await key('Bother000001', 'I3')));
    });

    for (final accepted in [true, false]) {
      final name = accepted ? 'authorInviteAccepted' : 'authorInviteDeclined';
      test('$name: inviter only, no push', () async {
        final harness = TestAttentionHarness();
        final intent = accepted
            ? await harness.intents.authorInviteAccepted(
                beaconId: beacon,
                inviterUserId: inviter,
                inviteeUserId: invitee,
                sourceEventKey: '$name:$inviteId',
              )
            : await harness.intents.authorInviteDeclined(
                beaconId: beacon,
                inviterUserId: inviter,
                inviteeUserId: invitee,
                sourceEventKey: '$name:$inviteId',
              );

        expect(intent.eventType.name, name);
        expect(intent.kind.name, name);
        expect(intent.actorUserId, invitee);
        expect(intent.recipients, hasLength(1));
        final recipient = intent.recipients.single;
        expect(recipient.recipientId, inviter);
        expect(recipient.reasons, {AttentionRecipientReason.authorInviter});
        expect(recipient.channelEligible, isFalse);
        expect(recipient.role.targetEntityId, invitee);
      });
    }

    test('a blocked pair gets no receipt', () async {
      final blocks = FakeUserBlockRepository()..blockPair(inviter, invitee);
      final harness = TestAttentionHarness(userBlocks: blocks);

      final received = await harness.intents.authorInviteReceived(
        beaconId: beacon,
        inviteId: inviteId,
        inviterUserId: inviter,
        inviteeUserId: invitee,
        sourceEventKey: 'author_invite:$inviteId',
      );
      final accepted = await harness.intents.authorInviteAccepted(
        beaconId: beacon,
        inviterUserId: inviter,
        inviteeUserId: invitee,
        sourceEventKey: 'author_invite_accepted:$inviteId',
      );

      expect(received.recipients, isEmpty);
      expect(accepted.recipients, isEmpty);
    });

    test('no receipt to oneself', () async {
      final harness = TestAttentionHarness();
      final intent = await harness.intents.authorInviteReceived(
        beaconId: beacon,
        inviteId: inviteId,
        inviterUserId: inviter,
        inviteeUserId: inviter,
        sourceEventKey: 'author_invite:$inviteId',
      );
      expect(intent.recipients, isEmpty);
    });
  });
}
