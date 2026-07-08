import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/beacon_notification_recipient.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/entity/notification_recipient_reason.dart';

/// Pure recipient policy for coordination-item notifications.
class BeaconNotificationRecipientResolver {
  const BeaconNotificationRecipientResolver();

  List<BeaconNotificationRecipient> resolveRecipients({
    required BeaconNotificationIntent intent,
    required BeaconNotificationContext ctx,
  }) {
    final actor = intent.actorUserId;
    final out = <String, BeaconNotificationRecipient>{};

    void add(
      String userId,
      NotificationRecipientReason reason,
      NotificationPriority priority,
    ) {
      if (userId.isEmpty || userId == actor) {
        return;
      }
      final existing = out[userId];
      if (existing == null || priority.index < existing.priority.index) {
        out[userId] = BeaconNotificationRecipient(
          userId: userId,
          reason: reason,
          priority: priority,
        );
      }
    }

    switch (intent.kind) {
      case NotificationKind.needsMe:
        final target = intent.targetPersonId;
        if (target != null && target.isNotEmpty) {
          add(target, NotificationRecipientReason.targetOfAsk, intent.priority);
        }

      case NotificationKind.inviteAccepted:
        // Non-beacon social notification; handled by a dedicated service.
        break;

      case NotificationKind.promiseMade:
        add(
          ctx.beaconAuthorId,
          NotificationRecipientReason.authorOfBeacon,
          intent.priority,
        );
        for (final s in ctx.stewardUserIds) {
          add(
            s,
            NotificationRecipientReason.roomModeratorOrSteward,
            intent.priority,
          );
        }
        final affected = intent.targetPersonId;
        if (affected != null && affected.isNotEmpty) {
          add(
            affected,
            NotificationRecipientReason.affectedParticipant,
            intent.priority,
          );
        }

      case NotificationKind.coordinationChanged:
        add(
          ctx.beaconAuthorId,
          NotificationRecipientReason.authorOfBeacon,
          intent.priority,
        );
        for (final uid in ctx.admittedUserIds) {
          add(uid, NotificationRecipientReason.admittedRoomMember, intent.priority);
        }
        for (final uid in ctx.usersWithActiveCoordination) {
          add(uid, NotificationRecipientReason.activeParticipant, intent.priority);
        }

      case NotificationKind.blockerOpened:
      case NotificationKind.blockerResolved:
        add(
          ctx.beaconAuthorId,
          NotificationRecipientReason.authorOfBeacon,
          intent.priority,
        );
        for (final s in ctx.stewardUserIds) {
          add(
            s,
            NotificationRecipientReason.roomModeratorOrSteward,
            intent.priority,
          );
        }
        final target = intent.targetPersonId;
        if (target != null && target.isNotEmpty) {
          add(
            target,
            NotificationRecipientReason.affectedParticipant,
            intent.priority,
          );
        }

      case NotificationKind.roomAccess:
        final admitted = intent.targetPersonId;
        if (admitted != null && admitted.isNotEmpty) {
          add(
            admitted,
            NotificationRecipientReason.admittedRoomMember,
            intent.priority,
          );
        }

      case NotificationKind.newRelay:
        for (final rid in intent.forwardRecipientIds) {
          add(rid, NotificationRecipientReason.forwardRecipient, intent.priority);
        }

      case NotificationKind.commitmentEvent:
        add(
          ctx.beaconAuthorId,
          NotificationRecipientReason.authorOfBeacon,
          intent.priority,
        );
        for (final s in ctx.stewardUserIds) {
          add(
            s,
            NotificationRecipientReason.roomModeratorOrSteward,
            intent.priority,
          );
        }
        for (final mid in intent.moderatorUserIds) {
          add(
            mid,
            NotificationRecipientReason.roomModeratorOrSteward,
            intent.priority,
          );
        }

      case NotificationKind.reviewReady:
        for (final uid in intent.admittedUserIds) {
          add(uid, NotificationRecipientReason.reviewParticipant, intent.priority);
        }

      case NotificationKind.roomActivityLowPriority:
        for (final uid in ctx.admittedUserIds) {
          add(uid, NotificationRecipientReason.admittedRoomMember, intent.priority);
        }

      case NotificationKind.staleRemind:
        final target = intent.targetPersonId;
        if (target != null && target.isNotEmpty) {
          add(target, NotificationRecipientReason.targetOfAsk, intent.priority);
        }
    }

    return out.values.toList();
  }
}
