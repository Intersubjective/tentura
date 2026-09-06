import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';

import '../../support/fake_user_block_repository.dart';
import '../../support/test_attention_harness.dart';

void main() {
  const beaconId = 'B-audience';
  const actor = 'U-actor';
  const author = 'U-author';
  const helper = 'U-helper';
  const committer = 'U-committer';
  const planner = 'U-planner';
  const watcher = 'U-watcher';

  final audienceContext = BeaconNotificationContext(
    beaconAuthorId: author,
    admittedUserIds: {'U-admitted'},
    stewardUserIds: {'U-steward'},
    activeHelpOfferUserIds: {helper},
    activeRequestParticipantUserIds: {committer},
    activePlanParticipantUserIds: {planner},
    inboxStanceUserIds: {watcher},
  );

  test('status audience facts expose retained participation sets', () {
    expect(audienceContext.activeHelpOfferUserIds, {helper});
    expect(audienceContext.activeRequestParticipantUserIds, {committer});
    expect(audienceContext.activePlanParticipantUserIds, {planner});
  });

  test('requestStatusChanged keeps watcher, actor suppression, and block behavior', () async {
    final harness = TestAttentionHarness(
      context: audienceContext,
      userBlocks: FakeUserBlockRepository(),
    );

    final intent = await harness.intents.requestStatusChanged(
      beaconId: beaconId,
      fromStatus: 'open',
      toStatus: 'closed',
      actorUserId: actor,
      sourceEventKey: 'request_status:audience',
    );

    final recipientIds = intent.recipients.map((r) => r.recipientId).toSet();
    expect(recipientIds, contains(author));
    expect(recipientIds, contains('U-steward'));
    expect(recipientIds, contains('U-admitted'));
    expect(recipientIds, contains(helper));
    expect(recipientIds, contains(committer));
    expect(recipientIds, contains(planner));
    expect(recipientIds, isNot(contains(actor)));

    final watcherRecipient = intent.recipients.singleWhere(
      (r) => r.recipientId == watcher,
    );
    expect(
      watcherRecipient.reasons,
      {AttentionRecipientReason.inboxStanceHolder},
    );
    expect(watcherRecipient.channelEligible, isFalse);
    expect(watcherRecipient.collapseKey, isNotNull);
  });

  test('requestStatusChanged excludes blocked peers of the actor', () async {
    final blocks = FakeUserBlockRepository();
    blocks.blockPair(actor, committer);
    final harness = TestAttentionHarness(
      context: audienceContext,
      userBlocks: blocks,
    );

    final intent = await harness.intents.requestStatusChanged(
      beaconId: beaconId,
      fromStatus: 'open',
      toStatus: 'closed',
      actorUserId: actor,
      sourceEventKey: 'request_status:blocked',
    );

    expect(
      intent.recipients.map((r) => r.recipientId),
      isNot(contains(committer)),
    );
  });

  test('plan participant projection only includes published active plans', () {
    const openPlanStatus = coordinationItemStatusOpen;
    const acceptedPlanStatus = coordinationItemStatusAccepted;
    const planKind = coordinationItemKindPlan;

    expect(openPlanStatus, isNot(equals(coordinationItemStatusResolved)));
    expect(acceptedPlanStatus, isNot(equals(coordinationItemStatusCancelled)));
    expect(planKind, coordinationItemKindPlan);
  });

  test('help offer projection uses active offers only', () {
    final active = HelpOfferEntity(
      beaconId: beaconId,
      userId: helper,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      status: 0,
    );
    final withdrawn = active.copyWith(status: 1);
    expect(active.status, 0);
    expect(withdrawn.status, 1);
  });

  test('acknowledged participation uses current stake, not retired ask rows', () {
    expect(CommitmentEventKind.acknowledged, isNot(CommitmentEventKind.offered));
  });
}
