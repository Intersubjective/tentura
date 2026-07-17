import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_policy.dart';

void main() {
  const policy = AttentionPolicy();
  final contract =
      jsonDecode(
            File(
              '../../docs/contracts/updates-event-contract.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final rows = (contract['eventTypes']! as List).cast<Map<String, Object?>>();

  group('compact contract projection policy', () {
    for (final row in rows) {
      final eventName = row['eventType']! as String;
      test('$eventName has a recipient-specific projection', () {
        final fixture = _fixtureFor(eventName);
        final projection = policy.project(
          eventType: attentionEventTypeFromWireName(eventName),
          recipientId: 'recipient',
          recipientReasons: fixture.reasons,
          role: fixture.role,
        );

        expect(
          _matchesMuteability(
            projection.suppressionClass,
            row['muteability']! as String,
          ),
          isTrue,
        );
        expect(
          _matchesDestination(
            projection.destination.kind,
            row['destinationFamily']! as String,
          ),
          isTrue,
        );
        expect(projection.presentationKey, isNotEmpty);
        expect(
          projection.presentationPayload.keys,
          everyElement(
            isIn({
              'eventType',
              'actorUserId',
              'beaconId',
              'coordinationItemId',
              'targetEntityId',
              'messageId',
            }),
          ),
        );
        expect(
          utf8.encode(jsonEncode(projection.presentationPayload)),
          hasLength(lessThanOrEqualTo(2048)),
        );
      });
    }
  });

  test('help offer is mandatory for author and standard for steward', () {
    final author = policy.project(
      eventType: AttentionEventType.helpOfferSubmitted,
      recipientId: 'author',
      recipientReasons: const {AttentionRecipientReason.authorOfBeacon},
      role: _baseRole,
    );
    final steward = policy.project(
      eventType: AttentionEventType.helpOfferSubmitted,
      recipientId: 'steward',
      recipientReasons: const {
        AttentionRecipientReason.roomModeratorOrSteward,
      },
      role: _baseRole,
    );

    expect(author.suppressionClass, AttentionSuppressionClass.mandatory);
    expect(steward.suppressionClass, AttentionSuppressionClass.standard);
  });

  test('active-participant reason wins over noisy inbox stance', () {
    final projection = policy.project(
      eventType: AttentionEventType.requestStatusChanged,
      recipientId: 'recipient',
      recipientReasons: const {
        AttentionRecipientReason.inboxStanceHolder,
        AttentionRecipientReason.activeParticipant,
      },
      role: _baseRole,
    );

    expect(projection.suppressionClass, AttentionSuppressionClass.standard);
    expect(projection.inAppPreferenceClass, isNull);
  });

  test('watcher-only request progress is noisy and mutable', () {
    final projection = policy.project(
      eventType: AttentionEventType.requestStatusChanged,
      recipientId: 'watcher',
      recipientReasons: const {
        AttentionRecipientReason.inboxStanceHolder,
      },
      role: _baseRole,
    );

    expect(projection.suppressionClass, AttentionSuppressionClass.noisy);
    expect(
      projection.inAppPreferenceClass,
      AttentionPreferenceClass.requestProgress,
    );
  });

  test(
    'terminal offer response survives access loss with sanitized policy',
    () {
      final projection = policy.project(
        eventType: AttentionEventType.offerRemoved,
        recipientId: 'removed-helper',
        recipientReasons: const {
          AttentionRecipientReason.affectedParticipant,
        },
        role: _baseRole.copyWith(canReadBeaconContent: false),
      );

      expect(projection.accessPolicy, AttentionAccessPolicy.recipientSafe);
      expect(
        projection.destination.kind,
        AttentionDestinationKind.safeTerminal,
      );
      expect(projection.presentationKey, 'offer_removed');
    },
  );

  test('beacon-scoped attention requires a semantic relationship', () {
    expect(
      () => policy.project(
        eventType: AttentionEventType.roomMessagePosted,
        recipientId: 'recipient',
        recipientReasons: const {AttentionRecipientReason.inviter},
        role: _baseRole,
      ),
      throwsArgumentError,
    );
  });

  test('beacon-scoped attention requires a beacon id', () {
    expect(
      () => policy.project(
        eventType: AttentionEventType.roomMessagePosted,
        recipientId: 'recipient',
        recipientReasons: const {
          AttentionRecipientReason.directedChatTarget,
        },
        role: _baseRole.copyWith(beaconId: null),
      ),
      throwsArgumentError,
    );
  });

  test('social attention remains independent of Beacon involvement', () {
    final projection = policy.project(
      eventType: AttentionEventType.inviteAccepted,
      recipientId: 'recipient',
      recipientReasons: const {AttentionRecipientReason.inviter},
      role: _baseRole.copyWith(beaconId: null),
    );

    expect(projection.destination.kind, AttentionDestinationKind.profile);
  });
}

const _baseRole = AttentionRecipientRoleFacts(
  canReadBeaconContent: true,
  beaconId: 'beacon-1',
  coordinationItemId: 'item-1',
  targetEntityId: 'target-1',
  messageId: 'message-1',
  actorUserId: 'actor-1',
);

({
  Set<AttentionRecipientReason> reasons,
  AttentionRecipientRoleFacts role,
})
_fixtureFor(String eventName) => switch (eventName) {
  'relayReceived' => (
    reasons: const {AttentionRecipientReason.forwardRecipient},
    role: _baseRole,
  ),
  'helpOfferSubmitted' => (
    reasons: const {AttentionRecipientReason.authorOfBeacon},
    role: _baseRole,
  ),
  'offerAccepted' || 'offerDeclined' || 'offerRemoved' => (
    reasons: const {AttentionRecipientReason.affectedParticipant},
    role: _baseRole,
  ),
  'roomMessagePosted' => (
    reasons: const {AttentionRecipientReason.directedChatTarget},
    role: _baseRole,
  ),
  'requestStatusChanged' => (
    reasons: const {AttentionRecipientReason.activeParticipant},
    role: _baseRole,
  ),
  'reviewOpened' => (
    reasons: const {AttentionRecipientReason.reviewParticipant},
    role: _baseRole,
  ),
  'mutualConnectionFormed' => (
    reasons: const {AttentionRecipientReason.reciprocalCounterpart},
    role: _baseRole.copyWith(beaconId: null),
  ),
  'inviteAccepted' => (
    reasons: const {AttentionRecipientReason.inviter},
    role: _baseRole.copyWith(beaconId: null),
  ),
  _ => throw StateError('No policy fixture for $eventName'),
};

bool _matchesMuteability(
  AttentionSuppressionClass suppression,
  String contractValue,
) => switch (contractValue) {
  'mandatory' => suppression == AttentionSuppressionClass.mandatory,
  'standard' => suppression == AttentionSuppressionClass.standard,
  'mandatory_or_standard' => suppression != AttentionSuppressionClass.noisy,
  'standard_or_noisy' => suppression != AttentionSuppressionClass.mandatory,
  _ => false,
};

bool _matchesDestination(
  AttentionDestinationKind destination,
  String contractValue,
) => switch (contractValue) {
  'beacon' => destination == AttentionDestinationKind.beacon,
  'beacon_people_offer' =>
    destination == AttentionDestinationKind.beaconPeopleOffer,
  'beacon_room' => destination == AttentionDestinationKind.beaconRoom,
  'beacon_people_or_safe_terminal' =>
    destination == AttentionDestinationKind.beaconPeopleOffer ||
        destination == AttentionDestinationKind.safeTerminal,
  'beacon_room_message' =>
    destination == AttentionDestinationKind.beaconRoomMessage,
  'review' => destination == AttentionDestinationKind.review,
  'profile' => destination == AttentionDestinationKind.profile,
  _ => false,
};
