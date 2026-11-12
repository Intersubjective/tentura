import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';

import '../../support/fake_user_block_repository.dart';
import '../../support/test_attention_harness.dart';

/// Pins the status-change audience (who, in what order, with which reasons)
/// built by both `requestStatusChanged` and `beaconHierarchyStatusChanged`.
void main() {
  const actor = 'U-actor';
  const blocked = 'U-blocked';

  const context = BeaconNotificationContext(
    beaconAuthorId: 'U-author',
    stewardUserIds: {'U-steward', '', actor},
    admittedUserIds: {'U-admitted', 'U-steward', blocked},
    activeHelpOfferUserIds: {'U-helper', 'U-author'},
    activeRequestParticipantUserIds: {'U-committer'},
    activePlanParticipantUserIds: {'U-planner', 'U-admitted'},
    inboxStanceUserIds: {'U-watcher', 'U-helper'},
  );

  final callers =
      <
        String,
        Future<AttentionDispatchIntent> Function(
          TestAttentionHarness harness,
          String? actorUserId,
        )
      >{
        'requestStatusChanged': (harness, actorUserId) =>
            harness.intents.requestStatusChanged(
              beaconId: 'B-status',
              fromStatus: 'open',
              toStatus: 'closed',
              sourceEventKey: 'request_status:order',
              actorUserId: actorUserId,
            ),
        'beaconHierarchyStatusChanged': (harness, actorUserId) =>
            harness.intents.beaconHierarchyStatusChanged(
              destinationBeaconId: 'B-status',
              messageId: 'R-msg',
              direction: BeaconHierarchyDeliveryDirection.child,
              toStatus: BeaconStatus.closed,
              occurredAt: DateTime.utc(2026, 3, 2),
              sourceEventKey: 'hierarchy:order',
              sourceDeleted: false,
              actorUserId: actorUserId,
            ),
      };

  for (final MapEntry(key: name, value: call) in callers.entries) {
    test('$name audience order, reasons, actor and block filtering', () async {
      final harness = TestAttentionHarness(
        context: context,
        userBlocks: FakeUserBlockRepository()..blockPair(actor, blocked),
      );

      final intent = await call(harness, actor);

      expect(intent.recipients.map((r) => r.recipientId).toList(), [
        'U-author',
        'U-steward',
        'U-admitted',
        'U-helper',
        'U-committer',
        'U-planner',
        'U-watcher',
      ]);
      expect(
        {for (final r in intent.recipients) r.recipientId: r.reasons},
        {
          'U-author': {
            AttentionRecipientReason.authorOfBeacon,
            AttentionRecipientReason.activeParticipant,
          },
          'U-steward': {
            AttentionRecipientReason.roomModeratorOrSteward,
            AttentionRecipientReason.admittedRoomMember,
          },
          'U-admitted': {
            AttentionRecipientReason.admittedRoomMember,
            AttentionRecipientReason.activeParticipant,
          },
          'U-helper': {
            AttentionRecipientReason.activeParticipant,
            AttentionRecipientReason.inboxStanceHolder,
          },
          'U-committer': {AttentionRecipientReason.activeParticipant},
          'U-planner': {AttentionRecipientReason.activeParticipant},
          'U-watcher': {AttentionRecipientReason.inboxStanceHolder},
        },
      );
    });

    test('$name without an actor keeps everyone and skips empty ids', () async {
      final harness = TestAttentionHarness(
        context: context,
        userBlocks: FakeUserBlockRepository()..blockPair(actor, blocked),
      );

      final intent = await call(harness, null);

      expect(intent.recipients.map((r) => r.recipientId).toList(), [
        'U-author',
        'U-steward',
        actor,
        'U-admitted',
        blocked,
        'U-helper',
        'U-committer',
        'U-planner',
        'U-watcher',
      ]);
    });
  }
}
