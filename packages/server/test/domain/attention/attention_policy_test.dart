@Tags(['repo-files'])
library;

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

  group('#189 personal flag', () {
    Map<String, Object?> payloadFor(
      AttentionEventType eventType,
      Set<AttentionRecipientReason> reasons, {
      String? actor = 'actor',
    }) => policy
        .project(
          eventType: eventType,
          recipientId: 'recipient',
          recipientReasons: reasons,
          role: AttentionRecipientRoleFacts(
            canReadBeaconContent: true,
            beaconId: 'B1',
            actorUserId: actor,
            messageId: 'M1',
            targetEntityId: 'T1',
            coordinationItemId: 'C1',
          ),
        )
        .presentationPayload;

    test('a message addressed to you is personal', () {
      expect(
        payloadFor(
          AttentionEventType.roomMessagePosted,
          {AttentionRecipientReason.directedChatTarget},
        )['personal'],
        isTrue,
      );
    });

    test('a blocker is personal by why you got it, not by its type', () {
      expect(
        payloadFor(
          AttentionEventType.blockerOpened,
          {AttentionRecipientReason.affectedParticipant},
        )['personal'],
        isTrue,
      );
      expect(
        payloadFor(
          AttentionEventType.blockerOpened,
          {AttentionRecipientReason.admittedRoomMember},
        )['personal'],
        isFalse,
      );
    });

    test('an author invite and its answer are personal', () {
      expect(
        payloadFor(
          AttentionEventType.authorInviteReceived,
          {AttentionRecipientReason.authorInvitee},
        )['personal'],
        isTrue,
      );
      for (final answer in [
        AttentionEventType.authorInviteAccepted,
        AttentionEventType.authorInviteDeclined,
      ]) {
        expect(
          payloadFor(answer, {
            AttentionRecipientReason.authorInviter,
          })['personal'],
          isTrue,
          reason: answer.name,
        );
        expect(policy.isStateLike(answer), isFalse, reason: answer.name);
      }
    });

    test('a status change is never personal', () {
      expect(
        payloadFor(
          AttentionEventType.requestStatusChanged,
          {AttentionRecipientReason.affectedParticipant},
        )['personal'],
        isFalse,
      );
    });

    test('no actor, or yourself as the actor, is never personal', () {
      expect(
        payloadFor(
          AttentionEventType.needsMe,
          {AttentionRecipientReason.targetOfAsk},
          actor: null,
        )['personal'],
        isFalse,
      );
      expect(
        payloadFor(
          AttentionEventType.needsMe,
          {AttentionRecipientReason.targetOfAsk},
          actor: 'recipient',
        )['personal'],
        isFalse,
      );
    });

    test('own-duty reminders map to their presentation keys', () {
      expect(AttentionPolicy.ownDutyReminderPresentationKeys, {
        'stale_reminder',
        'request_stale',
        'closure_draft_reminder',
        'deadline_reminder',
        // Request plan (#220): obligations and nudges never reach For You.
        'plan_step_due',
        'plan_step_turn',
        'plan_change_pending',
        'plan_step_reminder',
        'plan_step_overdue',
      });
    });
  });

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
              'personal',
              'actorUserId',
              'beaconId',
              'coordinationItemId',
              'targetEntityId',
              'messageId',
              'beaconTitle',
              'inviteOrigin',
              'excerpt',
              'toStatus',
              'withdrawReason',
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

  // #700: the client named the actor by parsing the English title when the
  // profile was not loaded; the receipt now carries the name itself.
  group('#700 actorName', () {
    Map<String, Object?> payloadFor(
      AttentionEventType eventType, {
      String? actorDisplayName = 'Alice GQ2',
    }) => policy
        .project(
          eventType: eventType,
          recipientId: 'recipient',
          recipientReasons: const {AttentionRecipientReason.authorOfBeacon},
          role: const AttentionRecipientRoleFacts(
            canReadBeaconContent: true,
            beaconId: 'B1',
            actorUserId: 'actor',
            targetEntityId: 'T1',
          ),
          actorDisplayName: actorDisplayName,
        )
        .presentationPayload;

    test('offer and invite-answer receipts carry the actor name', () {
      for (final eventType in [
        AttentionEventType.offerAccepted,
        AttentionEventType.helpOfferSubmitted,
        AttentionEventType.authorInviteAccepted,
        AttentionEventType.authorInviteDeclined,
      ]) {
        final payload = payloadFor(eventType);
        expect(payload['actorName'], 'Alice GQ2', reason: eventType.name);
        expect(payload['actorUserId'], 'actor', reason: eventType.name);
      }
    });

    test('the name is trimmed, and a blank name is left out', () {
      expect(
        payloadFor(
          AttentionEventType.offerAccepted,
          actorDisplayName: '  Bob  ',
        )['actorName'],
        'Bob',
      );
      for (final blank in [null, '', '   ']) {
        expect(
          payloadFor(
            AttentionEventType.offerAccepted,
            actorDisplayName: blank,
          ).containsKey('actorName'),
          isFalse,
          reason: '$blank',
        );
      }
    });

    test('other events do not carry it', () {
      expect(
        payloadFor(AttentionEventType.roomMessagePosted).containsKey(
          'actorName',
        ),
        isFalse,
      );
    });
  });

  group('excerpt and toStatus', () {
    test('the excerpt is always present, and only the words', () {
      final withWords = policy.project(
        eventType: AttentionEventType.roomMessagePosted,
        recipientId: 'r',
        recipientReasons: const {AttentionRecipientReason.authorOfBeacon},
        role: _baseRole.copyWith(excerpt: '  see you at 9  '),
      );
      final without = policy.project(
        eventType: AttentionEventType.roomMessagePosted,
        recipientId: 'r',
        recipientReasons: const {AttentionRecipientReason.authorOfBeacon},
        role: _baseRole,
      );

      expect(withWords.presentationPayload['excerpt'], 'see you at 9');
      // Present but empty: "no words", not "written before the field".
      expect(without.presentationPayload['excerpt'], '');
    });

    test('an unreadable Request shows none of its text', () {
      final projection = policy.project(
        eventType: AttentionEventType.roomMessagePosted,
        recipientId: 'r',
        recipientReasons: const {AttentionRecipientReason.authorOfBeacon},
        role: _baseRole.copyWith(
          canReadBeaconContent: false,
          excerpt: 'secret',
        ),
      );

      expect(projection.presentationPayload['excerpt'], '');
      expect(
        projection.presentationPayload.containsKey('beaconTitle'),
        isFalse,
      );
    });

    test('toStatus carries a real status name only', () {
      Map<String, Object?> payload(String status) => policy
          .project(
            eventType: AttentionEventType.requestStatusChanged,
            recipientId: 'r',
            recipientReasons: const {AttentionRecipientReason.authorOfBeacon},
            role: _baseRole.copyWith(toStatus: status),
          )
          .presentationPayload;

      expect(payload('reviewOpen')['toStatus'], 'reviewOpen');
      expect(payload('bogus').containsKey('toStatus'), isFalse);
    });

    test('a withdrawal carries the reason key only, and only when the '
        'Request is readable (#685)', () {
      Map<String, Object?> payload(String? reason, {bool readable = true}) =>
          policy
              .project(
                eventType: AttentionEventType.helpWithdrawn,
                recipientId: 'r',
                recipientReasons: const {
                  AttentionRecipientReason.authorOfBeacon,
                },
                role: _baseRole.copyWith(
                  canReadBeaconContent: readable,
                  withdrawReason: reason,
                ),
              )
              .presentationPayload;

      expect(payload('timing')['withdrawReason'], 'timing');
      expect(payload(' wrong_fit ')['withdrawReason'], 'wrong_fit');
      expect(payload('free text').containsKey('withdrawReason'), isFalse);
      expect(payload(null).containsKey('withdrawReason'), isFalse);
      expect(
        payload('timing', readable: false).containsKey('withdrawReason'),
        isFalse,
      );
    });
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
        role: _baseRole.copyWith(
          canReadBeaconContent: false,
          beaconTitle: 'Secret request name',
        ),
      );

      expect(projection.accessPolicy, AttentionAccessPolicy.recipientSafe);
      expect(
        projection.destination.kind,
        AttentionDestinationKind.safeTerminal,
      );
      expect(projection.presentationKey, 'offer_removed');
      expect(projection.presentationPayload, isNot(contains('beaconTitle')));
    },
  );

  test(
    'beaconTitle is included only when recipient can read beacon content',
    () {
      final entitled = policy.project(
        eventType: AttentionEventType.commitmentAccepted,
        recipientId: 'recipient',
        recipientReasons: const {AttentionRecipientReason.targetOfAsk},
        role: _baseRole.copyWith(beaconTitle: 'Garden cleanup'),
      );
      final restricted = policy.project(
        eventType: AttentionEventType.offerDeclined,
        recipientId: 'removed-helper',
        recipientReasons: const {
          AttentionRecipientReason.affectedParticipant,
        },
        role: _baseRole.copyWith(
          canReadBeaconContent: false,
          beaconTitle: 'Garden cleanup',
        ),
      );

      expect(entitled.presentationPayload['beaconTitle'], 'Garden cleanup');
      expect(restricted.presentationPayload, isNot(contains('beaconTitle')));
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
  'offerAccepted' ||
  'offerDeclined' ||
  'offerRemoved' ||
  'commitmentReleased' => (
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
  'obligationEnded' => (
    reasons: const {AttentionRecipientReason.activeParticipant},
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
  'closureOpened' ||
  'closureDraftReminder' ||
  'closureFinalized' ||
  'closureCancelled' => (
    reasons: const {AttentionRecipientReason.activeParticipant},
    role: _baseRole,
  ),
  'requestStale' => (
    reasons: const {AttentionRecipientReason.authorOfBeacon},
    role: _baseRole,
  ),
  'postFirstResponse' => (
    reasons: const {AttentionRecipientReason.postAuthor},
    role: _baseRole,
  ),
  'batonAsked' => (
    reasons: const {AttentionRecipientReason.batonCandidate},
    role: _baseRole,
  ),
  'batonTaken' => (
    reasons: const {AttentionRecipientReason.batonTaker},
    role: _baseRole,
  ),
  'batonAllAnswered' => (
    reasons: const {AttentionRecipientReason.batonAuthor},
    role: _baseRole,
  ),
  'authorInviteReceived' => (
    reasons: const {AttentionRecipientReason.authorInvitee},
    role: _baseRole,
  ),
  'authorInviteAccepted' || 'authorInviteDeclined' => (
    reasons: const {AttentionRecipientReason.authorInviter},
    role: _baseRole,
  ),
  'planStepDue' ||
  'planStepTurn' ||
  'planChangePending' ||
  'planStepReminder' ||
  'planStepOverdue' => (
    reasons: const {AttentionRecipientReason.planStepAssignee},
    role: _baseRole,
  ),
  'planStepLate' || 'planCantMake' || 'planStepUnassigned' => (
    reasons: const {AttentionRecipientReason.authorOfBeacon},
    role: _baseRole,
  ),
  'planEdited' || 'planStepDone' => (
    reasons: const {AttentionRecipientReason.admittedRoomMember},
    role: _baseRole,
  ),
  'helpWithdrawn' || 'forwardDeclined' => (
    reasons: const {AttentionRecipientReason.authorOfBeacon},
    role: _baseRole,
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
