import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/invite_accepted_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/entity/notification_recipient_reason.dart';
import 'package:tentura_server/domain/notification/beacon_notification_copy_builder.dart';
import 'package:tentura_server/domain/notification/beacon_notification_recipient_resolver.dart';
import 'package:tentura_server/domain/notification/notification_excerpt.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';

/// Builds the immutable, recipient-specific snapshot recorded by an attention
/// producer. Call this inside the producer's unit of work.
@Singleton(order: 1)
class AttentionIntentCase {
  const AttentionIntentCase(
    this._context,
    this._users,
    this._accessGuard,
  );

  final BeaconRoomNotificationContextPort _context;
  final UserRepositoryPort _users;
  final BeaconAccessGuard _accessGuard;

  static const _resolver = BeaconNotificationRecipientResolver();
  static const _copyBuilder = BeaconNotificationCopyBuilder();

  Future<AttentionDispatchIntent> relayReceived({
    required String beaconId,
    required String senderId,
    required String beaconAuthorId,
    required List<String> recipientIds,
    required String sourceEventKey,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.newRelay,
      priority: NotificationPriority.low,
      beaconId: beaconId,
      actorUserId: senderId,
      forwardRecipientIds: recipientIds
          .where((id) => id != senderId && id != beaconAuthorId)
          .toList(),
    ),
    eventType: AttentionEventType.relayReceived,
    sourceEventKey: sourceEventKey,
    resolveContext: false,
  );

  Future<AttentionDispatchIntent> helpOfferSubmitted({
    required String beaconId,
    required String helpOffererId,
    required String authorId,
    required String sourceEventKey,
    List<String> moderatorUserIds = const [],
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.commitmentEvent,
      priority: NotificationPriority.normal,
      beaconId: beaconId,
      actorUserId: helpOffererId,
      targetPersonId: authorId,
      moderatorUserIds: moderatorUserIds,
    ),
    eventType: AttentionEventType.helpOfferSubmitted,
    sourceEventKey: sourceEventKey,
    targetEntityId: helpOffererId,
  );

  Future<AttentionDispatchIntent> helpWithdrawn({
    required String beaconId,
    required String withdrawerUserId,
    required String sourceEventKey,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.commitmentEvent,
      priority: NotificationPriority.normal,
      beaconId: beaconId,
      actorUserId: withdrawerUserId,
      promiseWithdrawn: true,
    ),
    eventType: AttentionEventType.promiseWithdrawn,
    sourceEventKey: sourceEventKey,
  );

  Future<AttentionDispatchIntent> offerAccepted({
    required String receiverId,
    required String beaconId,
    required String actorUserId,
    required String sourceEventKey,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.roomAccess,
      priority: NotificationPriority.normal,
      beaconId: beaconId,
      actorUserId: actorUserId,
      targetPersonId: receiverId,
    ),
    eventType: AttentionEventType.offerAccepted,
    sourceEventKey: sourceEventKey,
    targetEntityId: receiverId,
  );

  Future<AttentionDispatchIntent> offerDeclined({
    required String receiverId,
    required String beaconId,
    required String actorUserId,
    required String reason,
    required String sourceEventKey,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.commitmentDeclined,
      priority: NotificationPriority.normal,
      beaconId: beaconId,
      actorUserId: actorUserId,
      targetPersonId: receiverId,
      bodyExcerpt: notificationExcerpt(reason),
    ),
    eventType: AttentionEventType.offerDeclined,
    sourceEventKey: sourceEventKey,
    targetEntityId: receiverId,
  );

  Future<AttentionDispatchIntent> offerRemoved({
    required String receiverId,
    required String beaconId,
    required String actorUserId,
    required String reason,
    required String sourceEventKey,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.commitmentRemoved,
      priority: NotificationPriority.normal,
      beaconId: beaconId,
      actorUserId: actorUserId,
      targetPersonId: receiverId,
      bodyExcerpt: notificationExcerpt(reason),
    ),
    eventType: AttentionEventType.offerRemoved,
    sourceEventKey: sourceEventKey,
    targetEntityId: receiverId,
  );

  Future<AttentionDispatchIntent> promiseChanged({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    required String sourceEventKey,
    String? targetPersonId,
    String? coordinationItemId,
    bool withdrawn = false,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.promiseMade,
      priority: NotificationPriority.normal,
      beaconId: beaconId,
      actorUserId: actorUserId,
      bodyExcerpt: notificationExcerpt(excerpt),
      targetPersonId: targetPersonId,
      coordinationItemId: coordinationItemId,
      promiseWithdrawn: withdrawn,
    ),
    eventType: withdrawn
        ? AttentionEventType.promiseWithdrawn
        : AttentionEventType.promiseMade,
    sourceEventKey: sourceEventKey,
  );

  Future<AttentionDispatchIntent> blockerChanged({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    required String sourceEventKey,
    required bool resolved,
    String? targetPersonId,
    String? coordinationItemId,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: resolved
          ? NotificationKind.blockerResolved
          : NotificationKind.blockerOpened,
      priority: resolved
          ? NotificationPriority.normal
          : NotificationPriority.high,
      beaconId: beaconId,
      actorUserId: actorUserId,
      bodyExcerpt: notificationExcerpt(excerpt),
      targetPersonId: targetPersonId,
      coordinationItemId: coordinationItemId,
    ),
    eventType: resolved
        ? AttentionEventType.blockerResolved
        : AttentionEventType.blockerOpened,
    sourceEventKey: sourceEventKey,
  );

  Future<AttentionDispatchIntent> needsMe({
    required String beaconId,
    required String actorUserId,
    required String targetUserId,
    required String excerpt,
    required String sourceEventKey,
    String? coordinationItemId,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.needsMe,
      priority: NotificationPriority.high,
      beaconId: beaconId,
      actorUserId: actorUserId,
      targetPersonId: targetUserId,
      bodyExcerpt: notificationExcerpt(excerpt),
      coordinationItemId: coordinationItemId,
    ),
    eventType: AttentionEventType.needsMe,
    sourceEventKey: sourceEventKey,
  );

  Future<AttentionDispatchIntent> coordinationChanged({
    required String beaconId,
    required String actorUserId,
    required String planExcerpt,
    required String sourceEventKey,
    List<String> admittedUserIds = const [],
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.coordinationChanged,
      priority: NotificationPriority.normal,
      beaconId: beaconId,
      actorUserId: actorUserId,
      bodyExcerpt: notificationExcerpt(planExcerpt),
      admittedUserIds: admittedUserIds,
    ),
    eventType: AttentionEventType.coordinationChanged,
    sourceEventKey: sourceEventKey,
    collapseKey: AttentionCollapseKey.family(
      'coordination_changed',
      [beaconId],
    ),
  );

  Future<AttentionDispatchIntent> staleReminder({
    required String beaconId,
    required String actorUserId,
    required String targetPersonId,
    required String excerpt,
    required String sourceEventKey,
    String? coordinationItemId,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.staleRemind,
      priority: NotificationPriority.high,
      beaconId: beaconId,
      actorUserId: actorUserId,
      targetPersonId: targetPersonId,
      bodyExcerpt: notificationExcerpt(excerpt),
      coordinationItemId: coordinationItemId,
    ),
    eventType: AttentionEventType.staleReminder,
    sourceEventKey: sourceEventKey,
  );

  Future<AttentionDispatchIntent> reviewOpened({
    required String beaconId,
    required String beaconTitle,
    required Set<String> recipientUserIds,
    required String actorUserId,
    required String sourceEventKey,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.reviewReady,
      priority: NotificationPriority.high,
      beaconId: beaconId,
      actorUserId: actorUserId,
      beaconTitle: beaconTitle,
      admittedUserIds: recipientUserIds.toList(),
    ),
    eventType: AttentionEventType.reviewOpened,
    sourceEventKey: sourceEventKey,
    resolveContext: false,
  );

  Future<AttentionDispatchIntent> roomMessagePosted({
    required String beaconId,
    required String messageId,
    required String actorUserId,
    required Set<String> recipientUserIds,
    required String excerpt,
    required String sourceEventKey,
    String? threadItemId,
  }) async {
    final actor = await _users.getById(actorUserId);
    final recipients = <AttentionRecipientSnapshot>[];
    for (final recipientId in recipientUserIds) {
      if (recipientId.isEmpty || recipientId == actorUserId) continue;
      recipients.add(
        AttentionRecipientSnapshot(
          recipientId: recipientId,
          reasons: const {AttentionRecipientReason.directedChatTarget},
          role: AttentionRecipientRoleFacts(
            canReadBeaconContent: await _accessGuard.canReadContent(
              beaconId: beaconId,
              viewerId: recipientId,
            ),
            beaconId: beaconId,
            coordinationItemId: threadItemId,
            messageId: messageId,
            actorUserId: actorUserId,
          ),
        ),
      );
    }
    final encodedBeacon = Uri.encodeQueryComponent(beaconId);
    final encodedMessage = Uri.encodeQueryComponent(messageId);
    final itemParam = threadItemId == null || threadItemId.isEmpty
        ? ''
        : '&item=${Uri.encodeQueryComponent(threadItemId)}';
    final safeExcerpt = notificationExcerpt(excerpt);
    return AttentionDispatchIntent(
      eventType: AttentionEventType.roomMessagePosted,
      sourceEventKey: sourceEventKey,
      actorUserId: actorUserId,
      priority: NotificationPriority.normal,
      kind: NotificationKind.roomActivityLowPriority,
      title: actor.displayName.trim().isEmpty
          ? 'New chat message'
          : actor.displayName,
      body: safeExcerpt.isEmpty ? 'New chat message' : safeExcerpt,
      actionUrl:
          '/#/shared/view?id=$encodedBeacon&dest=room&message=$encodedMessage$itemParam',
      collapseKey: AttentionCollapseKey.none(sourceEventKey),
      recipients: recipients,
      beaconId: beaconId,
      coordinationItemId: threadItemId,
      messageId: messageId,
    );
  }

  Future<AttentionDispatchIntent> requestStatusChanged({
    required String beaconId,
    required String fromStatus,
    required String toStatus,
    required String sourceEventKey,
    String? actorUserId,
  }) async {
    final context = await _context.loadContextForBeacon(beaconId);
    final reasonsByRecipient = <String, Set<AttentionRecipientReason>>{};

    void addReasons(
      Iterable<String> userIds,
      AttentionRecipientReason reason,
    ) {
      for (final userId in userIds) {
        if (userId.isEmpty || userId == actorUserId) continue;
        reasonsByRecipient.putIfAbsent(userId, () => {}).add(reason);
      }
    }

    addReasons(
      [context.beaconAuthorId],
      AttentionRecipientReason.authorOfBeacon,
    );
    addReasons(
      context.stewardUserIds,
      AttentionRecipientReason.roomModeratorOrSteward,
    );
    addReasons(
      context.admittedUserIds,
      AttentionRecipientReason.admittedRoomMember,
    );
    addReasons(
      context.usersWithActiveCoordination,
      AttentionRecipientReason.activeParticipant,
    );
    addReasons(
      context.inboxStanceUserIds,
      AttentionRecipientReason.inboxStanceHolder,
    );

    final recipients = <AttentionRecipientSnapshot>[];
    for (final entry in reasonsByRecipient.entries) {
      final watcherOnly =
          entry.value.length == 1 &&
          entry.value.contains(AttentionRecipientReason.inboxStanceHolder);
      recipients.add(
        AttentionRecipientSnapshot(
          recipientId: entry.key,
          reasons: entry.value,
          collapseKey: watcherOnly
              ? AttentionCollapseKey.family('request_status', [beaconId])
              : null,
          channelEligible: !watcherOnly,
          role: AttentionRecipientRoleFacts(
            canReadBeaconContent: await _accessGuard.canReadContent(
              beaconId: beaconId,
              viewerId: entry.key,
            ),
            beaconId: beaconId,
            actorUserId: actorUserId,
          ),
        ),
      );
    }

    final actorName = actorUserId == null
        ? null
        : (await _users.getById(actorUserId)).displayName.trim();
    final transition = '$fromStatus to $toStatus';
    return AttentionDispatchIntent(
      eventType: AttentionEventType.requestStatusChanged,
      sourceEventKey: sourceEventKey,
      actorUserId: actorUserId,
      priority: NotificationPriority.low,
      kind: NotificationKind.roomActivityLowPriority,
      title: 'Request status changed',
      body: actorName == null || actorName.isEmpty
          ? 'Request moved from $transition'
          : '$actorName moved the request from $transition',
      actionUrl: '/#/shared/view?id=${Uri.encodeQueryComponent(beaconId)}',
      collapseKey: AttentionCollapseKey.none(sourceEventKey),
      recipients: recipients,
      beaconId: beaconId,
    );
  }

  Future<AttentionDispatchIntent> mutualConnectionFormed({
    required String actorUserId,
    required String counterpartUserId,
    required String sourceEventKey,
  }) async {
    final actor = await _users.getById(actorUserId);
    final actorName = actor.displayName.trim();
    return AttentionDispatchIntent(
      eventType: AttentionEventType.mutualConnectionFormed,
      sourceEventKey: sourceEventKey,
      actorUserId: actorUserId,
      priority: NotificationPriority.normal,
      kind: NotificationKind.inviteAccepted,
      title: 'New connection',
      body: actorName.isEmpty
          ? 'You are now connected on Tentura.'
          : 'You and $actorName are now connected.',
      actionUrl: '/#/shared/view?id=${Uri.encodeQueryComponent(actorUserId)}',
      collapseKey: AttentionCollapseKey.none(sourceEventKey),
      recipients: [
        AttentionRecipientSnapshot(
          recipientId: counterpartUserId,
          reasons: const {AttentionRecipientReason.reciprocalCounterpart},
          role: AttentionRecipientRoleFacts(
            targetEntityId: actorUserId,
            actorUserId: actorUserId,
          ),
        ),
      ],
      targetEntityId: actorUserId,
    );
  }

  Future<AttentionDispatchIntent> fromBeaconNotification({
    required BeaconNotificationIntent notification,
    required AttentionEventType eventType,
    required String sourceEventKey,
    String? collapseKey,
    String? targetEntityId,
    bool resolveContext = true,
  }) async {
    final context = resolveContext
        ? await _context.loadContextForBeacon(notification.beaconId)
        : const BeaconNotificationContext();
    final recipients = _resolver.resolveRecipients(
      intent: notification,
      ctx: context,
    );
    final actor = await _users.getById(notification.actorUserId);
    final copy = _copyBuilder.build(
      intent: notification,
      actorDisplayName: actor.displayName,
    );

    return AttentionDispatchIntent(
      eventType: eventType,
      sourceEventKey: sourceEventKey,
      actorUserId: notification.actorUserId,
      priority: notification.priority,
      kind: notification.kind,
      title: copy.title,
      body: copy.body,
      actionUrl: copy.actionUrl,
      collapseKey: collapseKey ?? AttentionCollapseKey.none(sourceEventKey),
      recipients: [
        for (final recipient in recipients)
          AttentionRecipientSnapshot(
            recipientId: recipient.userId,
            reasons: recipient.reasons.map(_attentionReason).toSet(),
            role: AttentionRecipientRoleFacts(
              canReadBeaconContent:
                  notification.beaconId.isNotEmpty &&
                  await _accessGuard.canReadContent(
                    beaconId: notification.beaconId,
                    viewerId: recipient.userId,
                  ),
              beaconId: notification.beaconId.isEmpty
                  ? null
                  : notification.beaconId,
              coordinationItemId: notification.coordinationItemId,
              targetEntityId: targetEntityId ?? notification.targetPersonId,
              actorUserId: notification.actorUserId,
            ),
          ),
      ],
      beaconId: notification.beaconId.isEmpty ? null : notification.beaconId,
      coordinationItemId: notification.coordinationItemId,
      targetEntityId: targetEntityId ?? notification.targetPersonId,
    );
  }

  AttentionDispatchIntent inviteAccepted({
    required InviteAcceptedNotificationIntent notification,
    required String sourceEventKey,
  }) {
    final accepterName = notification.accepterDisplayName.trim();
    final title = accepterName.isEmpty
        ? 'Invitation accepted'
        : '$accepterName joined via your invitation';
    return AttentionDispatchIntent(
      eventType: AttentionEventType.inviteAccepted,
      sourceEventKey: sourceEventKey,
      actorUserId: notification.accepterUserId,
      priority: NotificationPriority.normal,
      kind: NotificationKind.inviteAccepted,
      title: title,
      body: 'You are now connected on Tentura.',
      actionUrl: notification.actionUrl,
      collapseKey: AttentionCollapseKey.none(sourceEventKey),
      recipients: [
        AttentionRecipientSnapshot(
          recipientId: notification.inviterUserId,
          reasons: const {AttentionRecipientReason.inviter},
          role: AttentionRecipientRoleFacts(
            targetEntityId: notification.accepterUserId,
            actorUserId: notification.accepterUserId,
          ),
        ),
      ],
      targetEntityId: notification.accepterUserId,
    );
  }

  AttentionRecipientReason _attentionReason(
    NotificationRecipientReason reason,
  ) => switch (reason) {
    NotificationRecipientReason.targetOfAsk =>
      AttentionRecipientReason.targetOfAsk,
    NotificationRecipientReason.authorOfBeacon =>
      AttentionRecipientReason.authorOfBeacon,
    NotificationRecipientReason.activeParticipant =>
      AttentionRecipientReason.activeParticipant,
    NotificationRecipientReason.affectedParticipant =>
      AttentionRecipientReason.affectedParticipant,
    NotificationRecipientReason.roomModeratorOrSteward =>
      AttentionRecipientReason.roomModeratorOrSteward,
    NotificationRecipientReason.admittedRoomMember =>
      AttentionRecipientReason.admittedRoomMember,
    NotificationRecipientReason.forwardRecipient =>
      AttentionRecipientReason.forwardRecipient,
    NotificationRecipientReason.reviewParticipant =>
      AttentionRecipientReason.reviewParticipant,
  };
}
