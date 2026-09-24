import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/invite_accepted_notification_intent.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';

import '../../support/test_attention_harness.dart';
import '../../support/fake_user_block_repository.dart';

void main() {
  const actor = 'actor';
  const target = 'target';
  const author = 'author';
  const beacon = 'beacon';
  const item = 'item';
  const eventKey = 'source:event';

  final harness = TestAttentionHarness(
    context: const BeaconNotificationContext(
      beaconAuthorId: author,
      admittedUserIds: {'member', target},
      stewardUserIds: {'steward'},
      activeHelpOfferUserIds: {'active'},
      activeRequestParticipantUserIds: {target},
      activePlanParticipantUserIds: const {},
      inboxStanceUserIds: {'watcher', 'member'},
    ),
  );

  final fixtures =
      <
        ({
          AttentionEventType eventType,
          String legacyKind,
          String recipient,
          Future<AttentionDispatchIntent> Function(
            AttentionIntentCase intents,
          )
          build,
        })
      >[
        (
          eventType: AttentionEventType.relayReceived,
          legacyKind: 'newRelay',
          recipient: target,
          build: (intents) => intents.relayReceived(
            beaconId: beacon,
            senderId: actor,
            beaconAuthorId: author,
            recipientIds: const [target],
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.helpOfferSubmitted,
          legacyKind: 'commitmentEvent',
          recipient: author,
          build: (intents) => intents.helpOfferSubmitted(
            beaconId: beacon,
            helpOffererId: actor,
            authorId: author,
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.offerAccepted,
          legacyKind: 'roomAccess',
          recipient: target,
          build: (intents) => intents.offerAccepted(
            receiverId: target,
            beaconId: beacon,
            actorUserId: actor,
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.offerDeclined,
          legacyKind: 'commitmentDeclined',
          recipient: target,
          build: (intents) => intents.offerDeclined(
            receiverId: target,
            beaconId: beacon,
            actorUserId: actor,
            reason: 'Not now',
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.offerRemoved,
          legacyKind: 'commitmentRemoved',
          recipient: target,
          build: (intents) => intents.offerRemoved(
            receiverId: target,
            beaconId: beacon,
            actorUserId: actor,
            reason: 'Scope changed',
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.commitmentReleased,
          legacyKind: 'commitmentReleased',
          recipient: target,
          build: (intents) => intents.commitmentReleased(
            receiverId: target,
            beaconId: beacon,
            actorUserId: actor,
            reason: 'Participation ended',
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.roomMessagePosted,
          legacyKind: 'roomActivityLowPriority',
          recipient: target,
          build: (intents) => intents.roomMessagePosted(
            beaconId: beacon,
            messageId: 'message',
            actorUserId: actor,
            recipientUserIds: const {target},
            excerpt: 'Directed message',
            threadItemId: item,
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.requestStatusChanged,
          legacyKind: 'roomActivityLowPriority',
          recipient: 'watcher',
          build: (intents) => intents.requestStatusChanged(
            beaconId: beacon,
            fromStatus: 'open',
            toStatus: 'closed',
            actorUserId: actor,
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.reviewOpened,
          legacyKind: 'reviewReady',
          recipient: target,
          build: (intents) => intents.reviewOpened(
            beaconId: beacon,
            beaconTitle: 'Request title',
            recipientUserIds: const {target},
            actorUserId: actor,
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.reviewAllPackagesIn,
          legacyKind: 'reviewReady',
          recipient: actor,
          build: (intents) => intents.reviewAllPackagesIn(
            beaconId: beacon,
            beaconTitle: 'Request title',
            authorUserId: actor,
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.reviewWindowCancelled,
          legacyKind: 'reviewReady',
          recipient: target,
          build: (intents) => intents.reviewWindowCancelled(
            beaconId: beacon,
            beaconTitle: 'Request title',
            recipientUserIds: const {target},
            actorUserId: actor,
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.obligationEnded,
          legacyKind: 'reviewReady',
          recipient: target,
          build: (intents) => intents.reviewObligationEnded(
            beaconId: beacon,
            beaconTitle: 'Request title',
            recipientUserIds: const {target},
            reason: AttentionObligationEndReason.reviewWindowExpired,
            actorUserId: actor,
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.mutualConnectionFormed,
          legacyKind: 'inviteAccepted',
          recipient: target,
          build: (intents) => intents.mutualConnectionFormed(
            actorUserId: actor,
            counterpartUserId: target,
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.trustGivenChanged,
          legacyKind: 'reviewReady',
          recipient: actor,
          build: (intents) => intents.trustGivenChanged(
            beaconId: beacon,
            beaconTitle: 'Request title',
            evaluatorId: actor,
            evaluatedUserId: target,
            bin: TrustBin.good,
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.trustReceivedChanged,
          legacyKind: 'reviewReady',
          recipient: target,
          build: (intents) => intents.trustReceivedChanged(
            beaconId: beacon,
            beaconTitle: 'Request title',
            evaluatorId: actor,
            evaluatedUserId: target,
            bin: TrustBin.good,
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.inviteAccepted,
          legacyKind: 'inviteAccepted',
          recipient: author,
          build: (intents) async => intents.inviteAccepted(
            notification: const InviteAcceptedNotificationIntent(
              inviterUserId: author,
              accepterUserId: actor,
              accepterDisplayName: 'Actor',
              actionUrl: '/#/profile/view/$actor',
              inviteOrigin: 'existing_account',
            ),
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.promiseMade,
          legacyKind: 'promiseMade',
          recipient: target,
          build: (intents) => intents.promiseChanged(
            beaconId: beacon,
            actorUserId: actor,
            excerpt: 'I will do it',
            targetPersonId: target,
            coordinationItemId: item,
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.promiseWithdrawn,
          legacyKind: 'promiseMade',
          recipient: target,
          build: (intents) => intents.promiseChanged(
            beaconId: beacon,
            actorUserId: actor,
            excerpt: 'Cannot do it',
            targetPersonId: target,
            coordinationItemId: item,
            withdrawn: true,
            sourceEventKey: eventKey,
          ),
        ),
        (
          eventType: AttentionEventType.coordinationChanged,
          legacyKind: 'coordinationChanged',
          recipient: 'member',
          build: (intents) => intents.coordinationChanged(
            beaconId: beacon,
            actorUserId: actor,
            planExcerpt: 'Next step',
            admittedUserIds: const ['member'],
            sourceEventKey: eventKey,
          ),
        ),
      ];

  group('migrated producer intent projection', () {
    for (final fixture in fixtures) {
      test(fixture.eventType.name, () async {
        final intent = await fixture.build(harness.intents);

        expect(intent.eventType, fixture.eventType);
        expect(intent.kind.name, fixture.legacyKind);
        expect(intent.sourceEventKey, eventKey);
        expect(
          intent.actorUserId,
          switch (fixture.eventType) {
            AttentionEventType.trustGivenChanged => target,
            _ => actor,
          },
        );
        expect(intent.title, isNotEmpty);
        expect(intent.body, isNotEmpty);
        expect(intent.actionUrl, isNotEmpty);
        expect(
          intent.recipients.map((recipient) => recipient.recipientId),
          contains(fixture.recipient),
        );
        expect(
          intent.collapseKey,
          switch (fixture.eventType) {
            AttentionEventType.coordinationChanged => startsWith(
              'v1|coordination_changed|',
            ),
            AttentionEventType.trustGivenChanged => startsWith(
              'v1|trust_given|',
            ),
            AttentionEventType.trustReceivedChanged => startsWith(
              'v1|trust_received|',
            ),
            // One explanation per Request per reason — the family is the
            // dedup unit, not the source event id.
            AttentionEventType.obligationEnded => startsWith(
              'v1|obligation_ended|',
            ),
            _ => startsWith('v1|none|'),
          },
        );
      });
    }
  });

  test('every non-pending compact-contract type has a migrated fixture', () {
    final contract =
        jsonDecode(
              File(
                '../../docs/contracts/updates-event-contract.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final pending = (contract['pendingProducerEventTypes']! as List).toSet();
    final required = (contract['eventTypes']! as List)
        .cast<Map<String, Object?>>()
        .map((row) => row['eventType']! as String)
        .where((eventType) => !pending.contains(eventType))
        .toSet();

    expect(
      fixtures.map((fixture) => fixture.eventType.name).toSet(),
      containsAll(required),
    );
  });

  test(
    'request status watcher collapse and channel policy is recipient-specific',
    () async {
      final intent = await harness.intents.requestStatusChanged(
        beaconId: beacon,
        fromStatus: 'open',
        toStatus: 'closed',
        actorUserId: actor,
        sourceEventKey: eventKey,
      );

      final watcher = intent.recipients.singleWhere(
        (recipient) => recipient.recipientId == 'watcher',
      );
      expect(watcher.channelEligible, isFalse);
      expect(watcher.collapseKey, startsWith('v1|request_status|'));

      final activeWatcher = intent.recipients.singleWhere(
        (recipient) => recipient.recipientId == 'member',
      );
      expect(activeWatcher.channelEligible, isTrue);
      expect(activeWatcher.collapseKey, isNull);
      expect(
        activeWatcher.reasons,
        containsAll({
          AttentionRecipientReason.admittedRoomMember,
          AttentionRecipientReason.inboxStanceHolder,
        }),
      );
    },
  );

  test('actor-null status transition keeps a null receipt actor', () async {
    final intent = await harness.intents.requestStatusChanged(
      beaconId: beacon,
      fromStatus: 'reviewOpen',
      toStatus: 'closed',
      sourceEventKey: eventKey,
    );

    expect(intent.actorUserId, isNull);
    expect(intent.body, contains('Request moved'));
  });

  group('E8 attention recipient block filtering', () {
    const unrelated = 'member';

    Future<Set<String>> recipientIds(AttentionDispatchIntent intent) async =>
        intent.recipients.map((recipient) => recipient.recipientId).toSet();

    group('fromBeaconNotification hub', () {
      Future<AttentionDispatchIntent> buildIntent(
        TestAttentionHarness harness,
      ) => harness.intents.reviewOpened(
        beaconId: beacon,
        beaconTitle: 'Request title',
        recipientUserIds: {target, unrelated},
        actorUserId: actor,
        sourceEventKey: eventKey,
      );

      test('excludes candidate when actor blocked them', () async {
        final blocks = FakeUserBlockRepository();
        blocks.blockPair(actor, target);
        final harness = TestAttentionHarness(userBlocks: blocks);

        final intent = await buildIntent(harness);

        expect(await recipientIds(intent), isNot(contains(target)));
        expect(await recipientIds(intent), contains(unrelated));
      });

      test('excludes candidate when they blocked actor', () async {
        final blocks = FakeUserBlockRepository();
        blocks.blockPair(target, actor);
        final harness = TestAttentionHarness(userBlocks: blocks);

        final intent = await buildIntent(harness);

        expect(await recipientIds(intent), isNot(contains(target)));
        expect(await recipientIds(intent), contains(unrelated));
      });
    });

    group('_directedRoomMessage', () {
      Future<AttentionDispatchIntent> buildIntent(
        TestAttentionHarness harness,
      ) => harness.intents.roomMessagePosted(
        beaconId: beacon,
        messageId: 'message',
        actorUserId: actor,
        recipientUserIds: {target, unrelated},
        excerpt: 'Directed message',
        threadItemId: item,
        sourceEventKey: eventKey,
      );

      test('excludes candidate when actor blocked them', () async {
        final blocks = FakeUserBlockRepository();
        blocks.blockPair(actor, target);
        final harness = TestAttentionHarness(userBlocks: blocks);

        final intent = await buildIntent(harness);

        expect(await recipientIds(intent), isNot(contains(target)));
        expect(await recipientIds(intent), contains(unrelated));
      });

      test('excludes candidate when they blocked actor', () async {
        final blocks = FakeUserBlockRepository();
        blocks.blockPair(target, actor);
        final harness = TestAttentionHarness(userBlocks: blocks);

        final intent = await buildIntent(harness);

        expect(await recipientIds(intent), isNot(contains(target)));
        expect(await recipientIds(intent), contains(unrelated));
      });
    });

    group('requestStatusChanged', () {
      final blockContext = const BeaconNotificationContext(
        admittedUserIds: {unrelated, target},
        activeRequestParticipantUserIds: {target},
      );

      Future<AttentionDispatchIntent> buildIntent(
        TestAttentionHarness harness,
      ) => harness.intents.requestStatusChanged(
        beaconId: beacon,
        fromStatus: 'open',
        toStatus: 'closed',
        actorUserId: actor,
        sourceEventKey: eventKey,
      );

      test('excludes candidate when actor blocked them', () async {
        final blocks = FakeUserBlockRepository();
        blocks.blockPair(actor, target);
        final harness = TestAttentionHarness(
          context: blockContext,
          userBlocks: blocks,
        );

        final intent = await buildIntent(harness);

        expect(await recipientIds(intent), isNot(contains(target)));
        expect(await recipientIds(intent), contains(unrelated));
      });

      test('excludes candidate when they blocked actor', () async {
        final blocks = FakeUserBlockRepository();
        blocks.blockPair(target, actor);
        final harness = TestAttentionHarness(
          context: blockContext,
          userBlocks: blocks,
        );

        final intent = await buildIntent(harness);

        expect(await recipientIds(intent), isNot(contains(target)));
        expect(await recipientIds(intent), contains(unrelated));
      });
    });

    group('mutualConnectionFormed', () {
      test('excludes counterpart when actor blocked them', () async {
        final blocks = FakeUserBlockRepository();
        blocks.blockPair(actor, target);
        final harness = TestAttentionHarness(userBlocks: blocks);

        final intent = await harness.intents.mutualConnectionFormed(
          actorUserId: actor,
          counterpartUserId: target,
          sourceEventKey: eventKey,
        );

        expect(intent.recipients, isEmpty);
      });

      test('excludes counterpart when they blocked actor', () async {
        final blocks = FakeUserBlockRepository();
        blocks.blockPair(target, actor);
        final harness = TestAttentionHarness(userBlocks: blocks);

        final intent = await harness.intents.mutualConnectionFormed(
          actorUserId: actor,
          counterpartUserId: target,
          sourceEventKey: eventKey,
        );

        expect(intent.recipients, isEmpty);
      });
    });

    group('inviteAccepted', () {
      Future<AttentionDispatchIntent> buildIntent(
        TestAttentionHarness harness,
      ) => harness.intents.inviteAccepted(
        notification: const InviteAcceptedNotificationIntent(
          inviterUserId: author,
          accepterUserId: actor,
          accepterDisplayName: 'Actor',
          actionUrl: '/#/profile/view/$actor',
          inviteOrigin: 'existing_account',
        ),
        sourceEventKey: eventKey,
      );

      test('excludes inviter when accepter blocked them', () async {
        final blocks = FakeUserBlockRepository();
        blocks.blockPair(actor, author);
        final harness = TestAttentionHarness(userBlocks: blocks);

        final intent = await buildIntent(harness);

        expect(intent.recipients, isEmpty);
      });

      test('excludes inviter when they blocked accepter', () async {
        final blocks = FakeUserBlockRepository();
        blocks.blockPair(author, actor);
        final harness = TestAttentionHarness(userBlocks: blocks);

        final intent = await buildIntent(harness);

        expect(intent.recipients, isEmpty);
      });

      test('stores public canonical title and new-account body', () async {
        final intent = await harness.intents.inviteAccepted(
          notification: const InviteAcceptedNotificationIntent(
            inviterUserId: author,
            accepterUserId: actor,
            accepterDisplayName: 'Alice',
            accepterHandle: 'alice',
            actionUrl: '/#/profile/view/$actor',
            inviteOrigin: 'new_account',
          ),
          sourceEventKey: eventKey,
        );

        expect(intent.title, 'Alice · @alice');
        expect(
          intent.body,
          'Created an account via your invitation. You are now connected.',
        );
        expect(
          intent.recipients.single.role.inviteOrigin,
          'new_account',
        );
      });

      test('stores existing-account body and handle-only title', () async {
        final intent = await harness.intents.inviteAccepted(
          notification: const InviteAcceptedNotificationIntent(
            inviterUserId: author,
            accepterUserId: actor,
            accepterDisplayName: '',
            accepterHandle: 'alice',
            actionUrl: '/#/profile/view/$actor',
            inviteOrigin: 'existing_account',
          ),
          sourceEventKey: eventKey,
        );

        expect(intent.title, '@alice');
        expect(
          intent.body,
          'Already had a Tentura account. You are now connected.',
        );
      });

      test('stores Invitation accepted when public parts are empty', () async {
        final intent = await harness.intents.inviteAccepted(
          notification: const InviteAcceptedNotificationIntent(
            inviterUserId: author,
            accepterUserId: actor,
            accepterDisplayName: '  ',
            actionUrl: '/#/profile/view/$actor',
            inviteOrigin: 'new_account',
          ),
          sourceEventKey: eventKey,
        );

        expect(intent.title, 'Invitation accepted');
      });
    });
  });

}
