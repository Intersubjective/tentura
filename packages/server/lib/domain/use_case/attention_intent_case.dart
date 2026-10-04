import 'package:injectable/injectable.dart';
import 'package:tentura_root/consts.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
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
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/policy/beacon_hierarchy_notice_copy.dart';

/// Builds the immutable, recipient-specific snapshot recorded by an attention
/// producer. Call this inside the producer's unit of work.
@Singleton(order: 1)
class AttentionIntentCase {
  const AttentionIntentCase(
    this._context,
    this._users,
    this._accessGuard,
    this._userBlocks,
  );

  final BeaconRoomNotificationContextPort _context;
  final UserRepositoryPort _users;
  final BeaconAccessGuard _accessGuard;
  final UserBlockRepositoryPort _userBlocks;

  static const _resolver = BeaconNotificationRecipientResolver();
  static const _copyBuilder = BeaconNotificationCopyBuilder();

  Future<AttentionDispatchIntent> relayReceived({
    required String beaconId,
    required String senderId,
    required String beaconAuthorId,
    required List<String> recipientIds,
    required String sourceEventKey,
    BeaconKind beaconKind = BeaconKind.request,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.newRelay,
      priority: NotificationPriority.low,
      beaconId: beaconId,
      actorUserId: senderId,
      forwardRecipientIds: recipientIds
          .where((id) => id != senderId && id != beaconAuthorId)
          .toList(),
      beaconKind: beaconKind,
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
    bool isBackupOffer = false,
    String message = '',
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.commitmentEvent,
      priority: NotificationPriority.normal,
      beaconId: beaconId,
      actorUserId: helpOffererId,
      targetPersonId: authorId,
      moderatorUserIds: moderatorUserIds,
      isBackupOffer: isBackupOffer,
      bodyExcerpt: notificationExcerpt(message),
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
    String bodyExcerpt = '',
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.roomAccess,
      priority: NotificationPriority.normal,
      beaconId: beaconId,
      actorUserId: actorUserId,
      targetPersonId: receiverId,
      bodyExcerpt: bodyExcerpt,
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

  Future<AttentionDispatchIntent> commitmentReleased({
    required String receiverId,
    required String beaconId,
    required String actorUserId,
    required String reason,
    required String sourceEventKey,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.commitmentReleased,
      priority: NotificationPriority.normal,
      beaconId: beaconId,
      actorUserId: actorUserId,
      targetPersonId: receiverId,
      bodyExcerpt: notificationExcerpt(reason),
    ),
    eventType: AttentionEventType.commitmentReleased,
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
    String beaconTitle = '',
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
      beaconTitle: beaconTitle,
      promiseWithdrawn: withdrawn,
    ),
    eventType: withdrawn
        ? AttentionEventType.promiseWithdrawn
        : AttentionEventType.promiseMade,
    sourceEventKey: sourceEventKey,
  );

  Future<AttentionDispatchIntent> coordinationChanged({
    required String beaconId,
    required String actorUserId,
    required String planExcerpt,
    required String sourceEventKey,
    List<String> admittedUserIds = const [],
    String beaconTitle = '',
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.coordinationChanged,
      priority: NotificationPriority.normal,
      beaconId: beaconId,
      actorUserId: actorUserId,
      bodyExcerpt: notificationExcerpt(planExcerpt),
      admittedUserIds: admittedUserIds,
      beaconTitle: beaconTitle,
    ),
    eventType: AttentionEventType.coordinationChanged,
    sourceEventKey: sourceEventKey,
    collapseKey: AttentionCollapseKey.family(
      'coordination_changed',
      [beaconId],
    ),
  );

  /// A deadline event is deliberately directed to the current committed
  /// participants.  Do not derive this from the room context: admission and a
  /// commitment are different facts, and the author must never receive it.
  Future<AttentionDispatchIntent> deadlineChanged({
    required String beaconId,
    required String actorUserId,
    required Set<String> participantUserIds,
    required DateTime? oldEndAt,
    required DateTime? newEndAt,
    required String sourceEventKey,
  }) => _deadlineIntent(
    beaconId: beaconId,
    actorUserId: actorUserId,
    participantUserIds: participantUserIds,
    oldEndAt: oldEndAt,
    newEndAt: newEndAt,
    sourceEventKey: sourceEventKey,
    reminder: false,
  );

  Future<AttentionDispatchIntent> deadlineReminder({
    required String beaconId,
    required Set<String> participantUserIds,
    required DateTime deadline,
    required String sourceEventKey,
  }) => _deadlineIntent(
    beaconId: beaconId,
    actorUserId: '',
    participantUserIds: participantUserIds,
    oldEndAt: null,
    newEndAt: deadline,
    sourceEventKey: sourceEventKey,
    reminder: true,
  );

  Future<AttentionDispatchIntent> _deadlineIntent({
    required String beaconId,
    required String actorUserId,
    required Set<String> participantUserIds,
    required DateTime? oldEndAt,
    required DateTime? newEndAt,
    required String sourceEventKey,
    required bool reminder,
  }) async {
    final oldValue = oldEndAt?.toUtc().toIso8601String() ?? 'none';
    final newValue = newEndAt?.toUtc().toIso8601String() ?? 'none';
    final recipients = participantUserIds
        .where((id) => id.isNotEmpty && id != actorUserId)
        .map(
          (id) => AttentionRecipientSnapshot(
            recipientId: id,
            reasons: const {AttentionRecipientReason.activeParticipant},
            role: AttentionRecipientRoleFacts(
              beaconId: beaconId,
              actorUserId: actorUserId.isEmpty ? null : actorUserId,
              canReadBeaconContent: true,
            ),
          ),
        )
        .toList();
    final deadlineText = newEndAt == null ? 'removed' : newValue;
    return AttentionDispatchIntent(
      eventType: reminder
          ? AttentionEventType.deadlineReminder
          : AttentionEventType.deadlineChanged,
      sourceEventKey: sourceEventKey,
      actorUserId: actorUserId.isEmpty ? null : actorUserId,
      priority: reminder
          ? NotificationPriority.high
          : NotificationPriority.normal,
      kind: reminder
          ? NotificationKind.deadlineReminder
          : NotificationKind.deadlineChanged,
      title: reminder ? 'Deadline reminder' : 'Deadline changed',
      // The values are immutable occurrence facts as well as user-facing copy.
      body: reminder
          ? 'Deadline: $deadlineText'
          : 'Deadline changed from $oldValue to $deadlineText',
      actionUrl:
          '/#$kPathBeaconView/${Uri.encodeQueryComponent(beaconId)}'
          '?is_deep_link=true',
      collapseKey: AttentionCollapseKey.none(sourceEventKey),
      beaconId: beaconId,
      recipients: recipients,
    );
  }

  Future<AttentionDispatchIntent> roomMessagePosted({
    required String beaconId,
    required String messageId,
    required String actorUserId,
    required Set<String> recipientUserIds,
    required String excerpt,
    required String sourceEventKey,
    String? threadItemId,
  }) => _directedRoomMessage(
    beaconId: beaconId,
    messageId: messageId,
    actorUserId: actorUserId,
    recipientUserIds: recipientUserIds,
    excerpt: excerpt,
    sourceEventKey: sourceEventKey,
    threadItemId: threadItemId,
    kind: NotificationKind.roomActivityLowPriority,
    emptyTitle: 'New thread message',
    emptyBody: 'New thread message',
  );

  /// The first response of [actorUserId] in a Post room, told to the Post
  /// author ([authorUserId]) once per member.
  Future<AttentionDispatchIntent> postFirstResponse({
    required String beaconId,
    required String messageId,
    required String actorUserId,
    required String authorUserId,
    required String excerpt,
    required String sourceEventKey,
  }) => _directedRoomMessage(
    beaconId: beaconId,
    messageId: messageId,
    actorUserId: actorUserId,
    recipientUserIds: {authorUserId},
    excerpt: excerpt,
    sourceEventKey: sourceEventKey,
    kind: NotificationKind.postFirstResponse,
    emptyTitle: 'New response',
    emptyBody: 'replied to your post',
    bodyPrefixedWithActor: true,
    eventType: AttentionEventType.postFirstResponse,
    reason: AttentionRecipientReason.postAuthor,
  );

  /// «Who'll take it?» (baton) — plan §2.2/B3
  /// (`docs/plans/baton-who-takes-it-plan.md`). All three carry only the
  /// source message's excerpt and never name other candidates (D3/D10).

  /// A candidate is asked to help on [actorUserId]'s baton.
  Future<AttentionDispatchIntent> batonAsked({
    required String beaconId,
    required String messageId,
    required String actorUserId,
    required String recipientId,
    required String excerpt,
    required String sourceEventKey,
  }) => _directedRoomMessage(
    beaconId: beaconId,
    messageId: messageId,
    actorUserId: actorUserId,
    recipientUserIds: {recipientId},
    excerpt: excerpt,
    sourceEventKey: sourceEventKey,
    kind: NotificationKind.batonAsked,
    emptyTitle: "Who'll take it?",
    emptyBody: 'asks if you can help',
    bodyPrefixedWithActor: true,
    eventType: AttentionEventType.batonAsked,
    reason: AttentionRecipientReason.batonCandidate,
  );

  /// The taker is told they took [actorUserId]'s baton.
  Future<AttentionDispatchIntent> batonTaken({
    required String beaconId,
    required String messageId,
    required String actorUserId,
    required String recipientId,
    required String excerpt,
    required String sourceEventKey,
  }) => _directedRoomMessage(
    beaconId: beaconId,
    messageId: messageId,
    actorUserId: actorUserId,
    recipientUserIds: {recipientId},
    excerpt: excerpt,
    sourceEventKey: sourceEventKey,
    kind: NotificationKind.batonTaken,
    emptyTitle: 'You took it',
    emptyBody: 'You took it',
    titleIsActorName: false,
    eventType: AttentionEventType.batonTaken,
    reason: AttentionRecipientReason.batonTaker,
  );

  /// The author ([recipientId]) is told everyone answered their baton.
  /// Dispatched once per baton (guarded by `all_answered_notified_at`, B4).
  Future<AttentionDispatchIntent> batonAllAnswered({
    required String beaconId,
    required String messageId,
    required String actorUserId,
    required String recipientId,
    required String excerpt,
    required String sourceEventKey,
  }) => _directedRoomMessage(
    beaconId: beaconId,
    messageId: messageId,
    actorUserId: actorUserId,
    recipientUserIds: {recipientId},
    excerpt: excerpt,
    sourceEventKey: sourceEventKey,
    kind: NotificationKind.batonAllAnswered,
    emptyTitle: 'Everyone answered',
    emptyBody: "Everyone answered your «Who'll take it?»",
    titleIsActorName: false,
    eventType: AttentionEventType.batonAllAnswered,
    reason: AttentionRecipientReason.batonAuthor,
  );

  /// Personal `@handle` mention — same Updates event as [roomMessagePosted],
  /// but [NotificationKind.roomMention] (coordination) for push/email.
  Future<AttentionDispatchIntent> roomMentioned({
    required String beaconId,
    required String messageId,
    required String actorUserId,
    required Set<String> recipientUserIds,
    required String excerpt,
    required String sourceEventKey,
    String? threadItemId,
  }) => _directedRoomMessage(
    beaconId: beaconId,
    messageId: messageId,
    actorUserId: actorUserId,
    recipientUserIds: recipientUserIds,
    excerpt: excerpt,
    sourceEventKey: sourceEventKey,
    threadItemId: threadItemId,
    kind: NotificationKind.roomMention,
    emptyTitle: 'New mention',
    emptyBody: 'mentioned you',
    titleIsActorName: true,
    bodyPrefixedWithActor: true,
  );

  // DORMANT(item-threads): threadItemId scopes attention deep links; always null in production (General is thread_item_id IS NULL).
  // Rooms are General-only (guard: beacon_room_message_general_only_guard, DiscussionScopeDisabledException); thread_item_id is always NULL for new rows. Do not design for this path. See #192.
  Future<AttentionDispatchIntent> _directedRoomMessage({
    required String beaconId,
    required String messageId,
    required String actorUserId,
    required Set<String> recipientUserIds,
    required String excerpt,
    required String sourceEventKey,
    required NotificationKind kind,
    required String emptyTitle,
    required String emptyBody,
    String? threadItemId,
    bool titleIsActorName = true,
    bool bodyPrefixedWithActor = false,
    AttentionEventType eventType = AttentionEventType.roomMessagePosted,
    AttentionRecipientReason reason =
        AttentionRecipientReason.directedChatTarget,
  }) async {
    final actor = await _users.getById(actorUserId);
    final actorName = actor.displayName.trim();
    final candidateIds = recipientUserIds
        .where((id) => id.isNotEmpty && id != actorUserId)
        .toList();
    final hiddenPeerIds = await _userBlocks.hiddenPeerIds(
      viewerId: actorUserId,
      peerIds: candidateIds,
    );
    final recipients = <AttentionRecipientSnapshot>[];
    for (final recipientId in candidateIds) {
      if (hiddenPeerIds.contains(recipientId)) continue;
      recipients.add(
        AttentionRecipientSnapshot(
          recipientId: recipientId,
          reasons: {reason},
          role: AttentionRecipientRoleFacts(
            canReadBeaconContent: await _accessGuard.canReadContent(
              beaconId: beaconId,
              viewerId: recipientId,
            ),
            beaconId: beaconId,
            coordinationItemId: threadItemId,
            messageId: messageId,
            actorUserId: actorUserId,
            excerpt:
                eventType == AttentionEventType.postFirstResponse ||
                    eventType == AttentionEventType.batonAsked ||
                    eventType == AttentionEventType.batonTaken ||
                    eventType == AttentionEventType.batonAllAnswered
                ? excerpt
                : null,
          ),
        ),
      );
    }
    final encodedBeacon = Uri.encodeQueryComponent(beaconId);
    final encodedMessage = Uri.encodeQueryComponent(messageId);
    final encodedThread = Uri.encodeQueryComponent(
      threadItemId != null && threadItemId.isNotEmpty
          ? threadItemId
          : 'general',
    );
    final safeExcerpt = notificationExcerpt(excerpt);
    final title = titleIsActorName && actorName.isNotEmpty
        ? actorName
        : emptyTitle;
    final body = safeExcerpt.isNotEmpty
        ? safeExcerpt
        : (bodyPrefixedWithActor && actorName.isNotEmpty
              ? '$actorName $emptyBody'
              : emptyBody);
    return AttentionDispatchIntent(
      eventType: eventType,
      sourceEventKey: sourceEventKey,
      actorUserId: actorUserId,
      priority: NotificationPriority.normal,
      kind: kind,
      title: title,
      body: body,
      actionUrl:
          '/#$kPathBeaconView/$encodedBeacon?tab=threads&thread=$encodedThread'
          '&entry=deep_link&is_deep_link=true&message=$encodedMessage',
      collapseKey: AttentionCollapseKey.none(sourceEventKey),
      recipients: recipients,
      beaconId: beaconId,
      coordinationItemId: threadItemId,
      messageId: messageId,
      beaconKind: kind == NotificationKind.postFirstResponse
          ? BeaconKind.post
          : BeaconKind.request,
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
      context.activeHelpOfferUserIds,
      AttentionRecipientReason.activeParticipant,
    );
    addReasons(
      context.activeRequestParticipantUserIds,
      AttentionRecipientReason.activeParticipant,
    );
    addReasons(
      context.activePlanParticipantUserIds,
      AttentionRecipientReason.activeParticipant,
    );
    addReasons(
      context.inboxStanceUserIds,
      AttentionRecipientReason.inboxStanceHolder,
    );

    if (actorUserId != null) {
      final hiddenPeerIds = await _userBlocks.hiddenPeerIds(
        viewerId: actorUserId,
        peerIds: reasonsByRecipient.keys,
      );
      for (final hiddenId in hiddenPeerIds) {
        reasonsByRecipient.remove(hiddenId);
      }
    }

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
            toStatus: toStatus,
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
      actionUrl:
          '/#$kPathBeaconView/${Uri.encodeQueryComponent(beaconId)}'
          '?is_deep_link=true',
      collapseKey: AttentionCollapseKey.none(sourceEventKey),
      recipients: recipients,
      beaconId: beaconId,
    );
  }

  Future<AttentionDispatchIntent> beaconHierarchyStatusChanged({
    required String destinationBeaconId,
    required String messageId,
    required BeaconHierarchyDeliveryDirection direction,
    required BeaconStatus toStatus,
    required DateTime occurredAt,
    required String sourceEventKey,
    required bool sourceDeleted,
    String? actorUserId,
  }) async {
    final context = await _context.loadContextForBeacon(destinationBeaconId);
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
      context.activeHelpOfferUserIds,
      AttentionRecipientReason.activeParticipant,
    );
    addReasons(
      context.activeRequestParticipantUserIds,
      AttentionRecipientReason.activeParticipant,
    );
    addReasons(
      context.activePlanParticipantUserIds,
      AttentionRecipientReason.activeParticipant,
    );
    addReasons(
      context.inboxStanceUserIds,
      AttentionRecipientReason.inboxStanceHolder,
    );

    if (actorUserId != null) {
      final hiddenPeerIds = await _userBlocks.hiddenPeerIds(
        viewerId: actorUserId,
        peerIds: reasonsByRecipient.keys,
      );
      for (final hiddenId in hiddenPeerIds) {
        reasonsByRecipient.remove(hiddenId);
      }
    }

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
              ? AttentionCollapseKey.family(
                  'request_status',
                  [destinationBeaconId],
                )
              : null,
          channelEligible: !watcherOnly,
          role: AttentionRecipientRoleFacts(
            canReadBeaconContent: await _accessGuard.canReadContent(
              beaconId: destinationBeaconId,
              viewerId: entry.key,
            ),
            beaconId: destinationBeaconId,
            messageId: messageId,
            actorUserId: actorUserId,
            toStatus: toStatus.name,
          ),
        ),
      );
    }

    final encodedBeacon = Uri.encodeQueryComponent(destinationBeaconId);
    final encodedMessage = Uri.encodeQueryComponent(messageId);
    return AttentionDispatchIntent(
      eventType: AttentionEventType.beaconHierarchyStatusChanged,
      sourceEventKey: sourceEventKey,
      actorUserId: actorUserId,
      priority: NotificationPriority.low,
      kind: NotificationKind.roomActivityLowPriority,
      title: BeaconHierarchyNoticeCopy.attentionTitle(direction: direction),
      body: BeaconHierarchyNoticeCopy.attentionBody(
        direction: direction,
        toStatus: toStatus,
        occurredAt: occurredAt,
        sourceDeleted: sourceDeleted,
      ),
      actionUrl:
          '/#$kPathBeaconView/$encodedBeacon?tab=threads&thread=general'
          '&entry=deep_link&is_deep_link=true&message=$encodedMessage',
      collapseKey: AttentionCollapseKey.none(sourceEventKey),
      recipients: recipients,
      beaconId: destinationBeaconId,
      messageId: messageId,
    );
  }

  Future<AttentionDispatchIntent> mutualConnectionFormed({
    required String actorUserId,
    required String counterpartUserId,
    required String sourceEventKey,
  }) async {
    final actor = await _users.getById(actorUserId);
    final actorName = actor.displayName.trim();
    final blocked = await _userBlocks.isBlockedPair(
      a: actorUserId,
      b: counterpartUserId,
    );
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
      actionUrl: '/#/profile/view/${Uri.encodeQueryComponent(actorUserId)}',
      collapseKey: AttentionCollapseKey.none(sourceEventKey),
      recipients: blocked
          ? const []
          : [
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
    final resolvedRecipients = _resolver.resolveRecipients(
      intent: notification,
      ctx: context,
    );
    final hiddenPeerIds = await _userBlocks.hiddenPeerIds(
      viewerId: notification.actorUserId,
      peerIds: resolvedRecipients.map((recipient) => recipient.userId),
    );
    final recipients = resolvedRecipients
        .where((recipient) => !hiddenPeerIds.contains(recipient.userId))
        .toList();
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
              beaconTitle: notification.beaconTitle.trim().isEmpty
                  ? null
                  : notification.beaconTitle.trim(),
              excerpt: copy.excerpt,
            ),
          ),
      ],
      beaconId: notification.beaconId.isEmpty ? null : notification.beaconId,
      coordinationItemId: notification.coordinationItemId,
      targetEntityId: targetEntityId ?? notification.targetPersonId,
      beaconKind: notification.beaconKind,
    );
  }

  Future<AttentionDispatchIntent> inviteAccepted({
    required InviteAcceptedNotificationIntent notification,
    required String sourceEventKey,
  }) async {
    final accepterName = notification.accepterDisplayName.trim();
    final handle = notification.accepterHandle.trim();
    final titleParts = <String>[
      if (accepterName.isNotEmpty) accepterName,
      if (handle.isNotEmpty) '@$handle',
    ];
    final title = titleParts.isEmpty
        ? 'Invitation accepted'
        : titleParts.join(' · ');
    final body = switch (notification.inviteOrigin) {
      'new_account' =>
        'Created an account via your invitation. You are now connected.',
      'existing_account' =>
        'Already had a Tentura account. You are now connected.',
      _ => 'You are now connected on Tentura.',
    };
    final blocked = await _userBlocks.isBlockedPair(
      a: notification.accepterUserId,
      b: notification.inviterUserId,
    );
    return AttentionDispatchIntent(
      eventType: AttentionEventType.inviteAccepted,
      sourceEventKey: sourceEventKey,
      actorUserId: notification.accepterUserId,
      priority: NotificationPriority.normal,
      kind: NotificationKind.inviteAccepted,
      title: title,
      body: body,
      actionUrl: notification.actionUrl,
      collapseKey: AttentionCollapseKey.none(sourceEventKey),
      recipients: blocked
          ? const []
          : [
              AttentionRecipientSnapshot(
                recipientId: notification.inviterUserId,
                reasons: const {AttentionRecipientReason.inviter},
                role: AttentionRecipientRoleFacts(
                  targetEntityId: notification.accepterUserId,
                  actorUserId: notification.accepterUserId,
                  inviteOrigin: notification.inviteOrigin,
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
  };
}
