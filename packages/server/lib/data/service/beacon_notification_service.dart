import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/beacon_notification_recipient.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_channel.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/beacon_notification_copy_builder.dart';
import 'package:tentura_server/domain/notification/beacon_notification_recipient_resolver.dart';
import 'package:tentura_server/domain/notification/notification_preference_gate.dart';
import 'package:tentura_server/domain/port/beacon_notification_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';
import 'package:tentura_server/domain/port/email_notification_port.dart';
import 'package:tentura_server/domain/port/fcm_batch_queue_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';

@LazySingleton(as: BeaconNotificationPort)
class BeaconNotificationService implements BeaconNotificationPort {
  BeaconNotificationService(
    this._fcmBatch,
    this._fcmTokens,
    this._fcmRemote,
    this._users,
    this._context,
    this._preferences,
    this._outbox,
    this._emailNotification,
    this._logger,
  );

  final FcmBatchQueuePort _fcmBatch;
  final FcmTokenRepositoryPort _fcmTokens;
  final FcmRemoteRepositoryPort _fcmRemote;
  final UserRepositoryPort _users;
  final BeaconRoomNotificationContextPort _context;
  final NotificationPreferenceRepositoryPort _preferences;
  final NotificationOutboxRepositoryPort _outbox;
  final EmailNotificationPort _emailNotification;
  final Logger _logger;

  static const _resolver = BeaconNotificationRecipientResolver();
  static const _copyBuilder = BeaconNotificationCopyBuilder();
  static const _gate = NotificationPreferenceGate();

  @override
  Future<void> dispatch(BeaconNotificationIntent intent) async {
    final ctx = await _loadContext(intent);
    final resolved = _resolver.resolveRecipients(intent: intent, ctx: ctx);
    if (resolved.isEmpty) {
      _logger.fine(
        '[FCM] dispatch skipped: no recipients kind=${intent.kind.name} '
        'beaconId=${intent.beaconId}',
      );
      return;
    }

    final actor = await _users.getById(intent.actorUserId);
    final fullCopy = _copyBuilder.build(
      intent: intent,
      actorDisplayName: actor.displayName,
    );

    // Durable Notification Center is the pull-based ground truth: record the
    // signal for every intended recipient regardless of push/email delivery.
    await _writeOutbox(intent, resolved, fullCopy);

    await handOffChannels([
      for (final recipient in resolved)
        AttentionChannelDecision(
          receiptId: '',
          recipientId: recipient.userId,
          kind: intent.kind,
          priority: recipient.priority,
          title: fullCopy.title,
          body: fullCopy.body,
          actionUrl: fullCopy.actionUrl,
          dedupKey: _dedupKey(intent, recipient.userId),
          actorUserId: intent.actorUserId,
          reason: recipient.reasons.map((reason) => reason.name).join(','),
          beaconId: intent.beaconId.isEmpty ? null : intent.beaconId,
          coordinationItemId: intent.coordinationItemId,
        ),
    ]);
  }

  @override
  Future<void> handOffChannels(
    List<AttentionChannelDecision> decisions,
  ) async {
    final now = DateTime.timestamp();
    for (final decision in decisions) {
      final intent = BeaconNotificationIntent(
        kind: decision.kind,
        priority: decision.priority,
        beaconId: decision.beaconId ?? '',
        actorUserId: decision.actorUserId,
        coordinationItemId: decision.coordinationItemId,
      );
      final fullCopy = BeaconNotificationCopy(
        title: decision.title,
        body: decision.body,
        actionUrl: decision.actionUrl,
      );
      final preferences = await _preferences.getForAccount(
        decision.recipientId,
      );
      final muted = decision.beaconId == null
          ? const <String>{}
          : await _preferences.getMutedBeaconIds(decision.recipientId, now);
      final pushAllowed = _gate.allowsChannel(
        channel: NotificationChannel.push,
        category: categoryOf(decision.kind),
        prefs: preferences,
        now: now,
        beaconId: decision.beaconId,
        mutedBeaconIds: muted,
      );

      if (decision.kind == NotificationKind.reviewReady) {
        if (pushAllowed) {
          await _sendDecisionDirect(
            decision: decision,
            intent: intent,
            copy: preferences.lockScreenSafe
                ? _copyBuilder.lockScreenSafe(intent)
                : fullCopy,
          );
        }
        continue;
      }

      var pushDelivered = false;
      if (pushAllowed) {
        pushDelivered = await _enqueue(
          receiverId: decision.recipientId,
          intent: intent,
          priority: decision.priority,
          copy: preferences.lockScreenSafe
              ? _copyBuilder.lockScreenSafe(intent)
              : fullCopy,
          reason: decision.reason,
        );
      }
      if (decision.kind == NotificationKind.inviteAccepted) {
        unawaited(
          _emailNotification.considerImmediateByCategory(
            recipientUserId: decision.recipientId,
            dedupKey: decision.dedupKey,
            title: decision.title,
            body: decision.body,
            actionUrl: decision.actionUrl,
            categoryScope: NotificationCategory.connections.name,
          ),
        );
      } else {
        unawaited(
          _emailNotification.considerImmediate(
            recipientUserId: decision.recipientId,
            kind: decision.kind,
            beaconId: decision.beaconId ?? '',
            dedupKey: decision.dedupKey,
            title: decision.title,
            body: decision.body,
            actionUrl: decision.actionUrl,
            pushDelivered: pushDelivered,
          ),
        );
      }
    }
  }

  Future<void> _sendDecisionDirect({
    required AttentionChannelDecision decision,
    required BeaconNotificationIntent intent,
    required BeaconNotificationCopy copy,
  }) async {
    final tokens = await _fcmTokens.getTokensByUserId(decision.recipientId);
    if (tokens.isEmpty) {
      _logger.info(
        '[FCM] review_ready skipped: no tokens '
        'receiverId=${decision.recipientId} beaconId=${decision.beaconId}',
      );
      return;
    }
    _logDispatch(
      intent: intent,
      receiverUserId: decision.recipientId,
      actorUserId: decision.actorUserId,
      reason: decision.reason,
      hasToken: true,
      queuedOrDirect: 'direct',
      coalescedCount: 1,
    );
    unawaited(
      _fcmRemote.sendChatNotification(
        fcmTokens: tokens.map((token) => token.token).toSet(),
        message: FcmNotificationEntity(
          title: copy.title,
          body: copy.body,
          actionUrl: copy.actionUrl,
          beaconId: decision.beaconId ?? '',
          coordinationItemId: decision.coordinationItemId,
          kind: decision.kind,
          priority: decision.priority,
        ),
      ),
    );
  }

  String _dedupKey(BeaconNotificationIntent intent, String userId) {
    final category = categoryOf(intent.kind);
    final beaconId = intent.beaconId.isEmpty ? '' : intent.beaconId;
    final itemId = intent.coordinationItemId ?? '';
    return '$userId|${category.name}|$beaconId|$itemId';
  }

  /// Enqueues a push for [receiverId]. Returns whether it was actually
  /// delivered (a device token existed) — used to decide the email fallback.
  Future<bool> _enqueue({
    required String receiverId,
    required BeaconNotificationIntent intent,
    required NotificationPriority priority,
    required BeaconNotificationCopy copy,
    required String reason,
  }) async {
    if (receiverId.isEmpty) {
      return false;
    }
    final tokens = await _fcmTokens.getTokensByUserId(receiverId);
    if (tokens.isEmpty) {
      _logger.info(
        '[FCM] push skipped: no fcm_token rows receiverId=$receiverId '
        'beaconId=${intent.beaconId} kind=${intent.kind.name}',
      );
      _logDispatch(
        intent: intent,
        receiverUserId: receiverId,
        actorUserId: intent.actorUserId,
        reason: reason,
        hasToken: false,
        queuedOrDirect: 'skipped',
        coalescedCount: 0,
      );
      return false;
    }
    final tokenSet = tokens.map((e) => e.token).toSet();
    _logDispatch(
      intent: intent,
      receiverUserId: receiverId,
      actorUserId: intent.actorUserId,
      reason: reason,
      hasToken: true,
      queuedOrDirect: 'queued',
      coalescedCount: 1,
    );
    _fcmBatch.enqueue(
      receiverId: receiverId,
      fcmTokens: tokenSet,
      message: FcmNotificationEntity(
        title: copy.title,
        body: copy.body,
        actionUrl: copy.actionUrl,
        beaconId: intent.beaconId,
        coordinationItemId: intent.coordinationItemId,
        kind: intent.kind,
        priority: priority,
      ),
    );
    return true;
  }

  void _logDispatch({
    required BeaconNotificationIntent intent,
    required String receiverUserId,
    required String actorUserId,
    required String reason,
    required bool hasToken,
    required String queuedOrDirect,
    required int coalescedCount,
  }) {
    _logger.info(
      '[FCM] kind=${intent.kind.name} priority=${intent.priority.name} '
      'beaconId=${intent.beaconId} receiverUserId=$receiverUserId '
      'actorUserId=$actorUserId reason=$reason hasToken=$hasToken '
      'queuedOrDirect=$queuedOrDirect coalescedCount=$coalescedCount',
    );
  }

  /// Records the durable Notification Center row for every intended recipient.
  /// Unread duplicates collapse via the dedup key.
  Future<void> _writeOutbox(
    BeaconNotificationIntent intent,
    List<BeaconNotificationRecipient> recipients,
    BeaconNotificationCopy copy,
  ) async {
    final category = categoryOf(intent.kind);
    final beaconId = intent.beaconId.isEmpty ? null : intent.beaconId;
    final itemId = intent.coordinationItemId;
    for (final r in recipients) {
      final dedupKey = _dedupKey(intent, r.userId);
      try {
        await _outbox.enqueue(
          accountId: r.userId,
          category: category,
          kind: intent.kind,
          priority: r.priority,
          title: copy.title,
          body: copy.body,
          actionUrl: copy.actionUrl,
          dedupKey: dedupKey,
          beaconId: beaconId,
          coordinationItemId: itemId,
          actorUserId: intent.actorUserId,
        );
      } on Object catch (e, s) {
        // The Center is best-effort; a write failure must not block push.
        _logger.warning('[Center] outbox write failed for ${r.userId}', e, s);
      }
    }
  }

  Future<BeaconNotificationContext> _loadContext(
    BeaconNotificationIntent intent,
  ) async {
    if (intent.kind == NotificationKind.newRelay ||
        intent.kind == NotificationKind.reviewReady) {
      return const BeaconNotificationContext();
    }
    return _context.loadContextForBeacon(intent.beaconId);
  }
}
