import 'package:injectable/injectable.dart';
import 'package:tentura_root/consts.dart';

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
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';

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
    bool isBackupOffer = false,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.commitmentEvent,
      priority: NotificationPriority.normal,
      beaconId: beaconId,
      actorUserId: helpOffererId,
      targetPersonId: authorId,
      moderatorUserIds: moderatorUserIds,
      isBackupOffer: isBackupOffer,
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

  Future<AttentionDispatchIntent> blockerChanged({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    required String sourceEventKey,
    required bool resolved,
    String? targetPersonId,
    String? coordinationItemId,
    String beaconTitle = '',
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
      beaconTitle: beaconTitle,
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
    String beaconTitle = '',
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.needsMe,
      priority: NotificationPriority.high,
      beaconId: beaconId,
      actorUserId: actorUserId,
      targetPersonId: targetUserId,
      bodyExcerpt: notificationExcerpt(excerpt),
      coordinationItemId: coordinationItemId,
      beaconTitle: beaconTitle,
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

  Future<AttentionDispatchIntent> staleReminder({
    required String beaconId,
    required String actorUserId,
    required String targetPersonId,
    required String excerpt,
    required String sourceEventKey,
    String? coordinationItemId,
    String beaconTitle = '',
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.staleRemind,
      priority: NotificationPriority.high,
      beaconId: beaconId,
      actorUserId: actorUserId,
      targetPersonId: targetPersonId,
      bodyExcerpt: notificationExcerpt(excerpt),
      coordinationItemId: coordinationItemId,
      beaconTitle: beaconTitle,
    ),
    eventType: AttentionEventType.staleReminder,
    sourceEventKey: sourceEventKey,
  );

  Future<AttentionDispatchIntent> commitmentChanged({
    required String beaconId,
    required String actorUserId,
    required String transition,
    required String excerpt,
    required String sourceEventKey,
    String? targetPersonId,
    String? coordinationItemId,
    int? coordinationItemKind,
    String beaconTitle = '',
    String? acceptedById,
    String? creatorId,
  }) {
    final (
      NotificationKind kind,
      AttentionEventType eventType,
      NotificationPriority priority,
    ) = switch (transition) {
      'accepted' => (
        NotificationKind.commitmentAccepted,
        AttentionEventType.commitmentAccepted,
        NotificationPriority.normal,
      ),
      'resolved' => (
        NotificationKind.commitmentResolved,
        AttentionEventType.commitmentResolved,
        NotificationPriority.normal,
      ),
      'cancelled' || 'redirected_from' => (
        NotificationKind.commitmentCancelled,
        AttentionEventType.commitmentCancelled,
        NotificationPriority.normal,
      ),
      'redirected_to' => (
        NotificationKind.commitmentRedirected,
        AttentionEventType.commitmentRedirected,
        NotificationPriority.high,
      ),
      _ => throw ArgumentError.value(transition, 'transition'),
    };
    final extraCreator =
        creatorId != null && creatorId.isNotEmpty && creatorId != actorUserId
        ? [creatorId]
        : const <String>[];
    final extraAccepted = acceptedById != null && acceptedById.isNotEmpty
        ? [acceptedById]
        : const <String>[];
    return fromBeaconNotification(
      notification: BeaconNotificationIntent(
        kind: kind,
        priority: priority,
        beaconId: beaconId,
        actorUserId: actorUserId,
        bodyExcerpt: notificationExcerpt(excerpt),
        targetPersonId: targetPersonId,
        coordinationItemId: coordinationItemId,
        coordinationItemKind: coordinationItemKind,
        beaconTitle: beaconTitle,
        admittedUserIds: extraAccepted,
        moderatorUserIds: extraCreator,
      ),
      eventType: eventType,
      sourceEventKey: sourceEventKey,
      collapseKey: AttentionCollapseKey.none(sourceEventKey),
    );
  }

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

  /// [NotificationKind.reviewReady] — legacy outbox/push plumbing only; Updates
  /// cards dispatch on [AttentionEventType] presentation keys.
  Future<AttentionDispatchIntent> trustGivenChanged({
    required String beaconId,
    required String beaconTitle,
    required String evaluatorId,
    required String evaluatedUserId,
    required TrustBin bin,
    required String sourceEventKey,
  }) async {
    final evaluated = await _users.getById(evaluatedUserId);
    final name = evaluated.displayName.trim();
    final direction = _trustDirectionFor(bin);
    return AttentionDispatchIntent(
      eventType: AttentionEventType.trustGivenChanged,
      sourceEventKey: sourceEventKey,
      actorUserId: evaluatedUserId,
      priority: NotificationPriority.normal,
      kind: NotificationKind.reviewReady,
      title: 'Trust update',
      body: _trustGivenBody(
        name: name,
        beaconTitle: beaconTitle,
        direction: direction,
      ),
      actionUrl: '/#/profile/view/${Uri.encodeQueryComponent(evaluatedUserId)}',
      collapseKey: AttentionCollapseKey.family(
        'trust_given',
        [beaconId, evaluatorId, evaluatedUserId],
      ),
      beaconId: beaconId,
      recipients: [
        AttentionRecipientSnapshot(
          recipientId: evaluatorId,
          reasons: const {AttentionRecipientReason.reviewParticipant},
          role: AttentionRecipientRoleFacts(
            beaconId: beaconId,
            canReadBeaconContent: true,
            beaconTitle: beaconTitle,
            targetEntityId: evaluatedUserId,
            actorUserId: evaluatedUserId,
            trustDirection: direction,
          ),
        ),
      ],
      targetEntityId: evaluatedUserId,
    );
  }

  /// [NotificationKind.reviewReady] — same legacy-kind choice as
  /// [trustGivenChanged].
  Future<AttentionDispatchIntent> trustReceivedChanged({
    required String beaconId,
    required String beaconTitle,
    required String evaluatorId,
    required String evaluatedUserId,
    required TrustBin bin,
    required String sourceEventKey,
  }) async {
    final evaluator = await _users.getById(evaluatorId);
    final name = evaluator.displayName.trim();
    final direction = _trustDirectionFor(bin);
    return AttentionDispatchIntent(
      eventType: AttentionEventType.trustReceivedChanged,
      sourceEventKey: sourceEventKey,
      actorUserId: evaluatorId,
      priority: NotificationPriority.normal,
      kind: NotificationKind.reviewReady,
      title: _trustReceivedTitle(direction),
      body: _trustReceivedBody(
        name: name,
        beaconTitle: beaconTitle,
        direction: direction,
      ),
      actionUrl: '/#$kPathBeaconView/$beaconId',
      collapseKey: AttentionCollapseKey.family(
        'trust_received',
        [beaconId, evaluatorId, evaluatedUserId],
      ),
      beaconId: beaconId,
      recipients: [
        AttentionRecipientSnapshot(
          recipientId: evaluatedUserId,
          reasons: const {AttentionRecipientReason.reviewParticipant},
          role: AttentionRecipientRoleFacts(
            beaconId: beaconId,
            canReadBeaconContent: true,
            beaconTitle: beaconTitle,
            targetEntityId: beaconId,
            actorUserId: evaluatorId,
            trustDirection: direction,
          ),
        ),
      ],
      targetEntityId: beaconId,
    );
  }

  String _trustDirectionFor(TrustBin bin) => switch (bin) {
    TrustBin.veryBad || TrustBin.bad => 'down',
    TrustBin.noEffect => 'noChange',
    TrustBin.good || TrustBin.veryGood => 'up',
  };

  String _trustGivenBody({
    required String name,
    required String beaconTitle,
    required String direction,
  }) {
    final counterpart = name.isEmpty ? 'them' : name;
    return switch (direction) {
      'up' => 'Your trust in $counterpart increased after "$beaconTitle".',
      'down' => 'Your trust in $counterpart decreased after "$beaconTitle".',
      _ =>
        'No significant trust change with $counterpart after "$beaconTitle".',
    };
  }

  String _trustReceivedTitle(String direction) => switch (direction) {
    'up' => 'Someone trusts you more',
    'down' => 'Someone trusts you less',
    _ => 'Someone reviewed you',
  };

  String _trustReceivedBody({
    required String name,
    required String beaconTitle,
    required String direction,
  }) {
    final reviewer = name.isEmpty ? 'Someone' : name;
    return switch (direction) {
      'up' =>
        '$reviewer now trusts you more after "$beaconTitle" — and their network.',
      'down' =>
        '$reviewer now trusts you less after "$beaconTitle" — and their network.',
      _ =>
        'No significant trust change from $reviewer after "$beaconTitle" — and their network.',
    };
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
      eventType: AttentionEventType.roomMessagePosted,
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

    if (actorUserId != null) {
      final hiddenPeerIds = await _userBlocks.hiddenPeerIds(
        viewerId: actorUserId!,
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
            ),
          ),
      ],
      beaconId: notification.beaconId.isEmpty ? null : notification.beaconId,
      coordinationItemId: notification.coordinationItemId,
      targetEntityId: targetEntityId ?? notification.targetPersonId,
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
    NotificationRecipientReason.reviewParticipant =>
      AttentionRecipientReason.reviewParticipant,
  };
}
