import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

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
    this._logger,
  );

  final FcmBatchQueuePort _fcmBatch;
  final FcmTokenRepositoryPort _fcmTokens;
  final FcmRemoteRepositoryPort _fcmRemote;
  final UserRepositoryPort _users;
  final BeaconRoomNotificationContextPort _context;
  final NotificationPreferenceRepositoryPort _preferences;
  final NotificationOutboxRepositoryPort _outbox;
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

    // Honor per-recipient preferences (category opt-out, quiet hours, snooze,
    // per-beacon mute) before any push leaves the server.
    final gated = await _filterByPushPreference(intent, resolved);
    if (gated.isEmpty) {
      _logger.fine(
        '[FCM] push suppressed by preferences kind=${intent.kind.name} '
        'beaconId=${intent.beaconId}',
      );
      return;
    }

    // Privacy-safe variant for recipients who enabled lock-screen redaction.
    final safeCopy = _copyBuilder.lockScreenSafe(intent);

    if (intent.kind == NotificationKind.reviewReady) {
      await _sendDirect(
        intent: intent,
        gated: gated,
        fullCopy: fullCopy,
        safeCopy: safeCopy,
      );
      return;
    }

    for (final g in gated) {
      await _enqueue(
        receiverId: g.recipient.userId,
        intent: intent,
        priority: g.recipient.priority,
        copy: g.lockScreenSafe ? safeCopy : fullCopy,
        reason: g.recipient.reason.name,
      );
    }
  }

  Future<void> _sendDirect({
    required BeaconNotificationIntent intent,
    required List<_GatedRecipient> gated,
    required BeaconNotificationCopy fullCopy,
    required BeaconNotificationCopy safeCopy,
  }) async {
    for (final g in gated) {
      final r = g.recipient;
      final copy = g.lockScreenSafe ? safeCopy : fullCopy;
      final tokens = await _fcmTokens.getTokensByUserId(r.userId);
      if (tokens.isEmpty) {
        _logger.info(
          '[FCM] review_ready skipped: no tokens receiverId=${r.userId} '
          'beaconId=${intent.beaconId}',
        );
        continue;
      }
      final message = FcmNotificationEntity(
        title: copy.title,
        body: copy.body,
        actionUrl: copy.actionUrl,
        beaconId: intent.beaconId,
        coordinationItemId: intent.coordinationItemId,
        kind: intent.kind,
        priority: intent.priority,
      );
      _logDispatch(
        intent: intent,
        receiverUserId: r.userId,
        actorUserId: intent.actorUserId,
        reason: r.reason.name,
        hasToken: true,
        queuedOrDirect: 'direct',
        coalescedCount: 1,
      );
      unawaited(
        _fcmRemote.sendChatNotification(
          fcmTokens: tokens.map((t) => t.token).toSet(),
          message: message,
        ),
      );
    }
  }

  Future<void> _enqueue({
    required String receiverId,
    required BeaconNotificationIntent intent,
    required NotificationPriority priority,
    required BeaconNotificationCopy copy,
    required String reason,
  }) async {
    if (receiverId.isEmpty) {
      return;
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
      return;
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
      final dedupKey =
          '${r.userId}|${category.name}|${beaconId ?? ''}|${itemId ?? ''}';
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

  /// Drops recipients who have opted out of push for this category, are within
  /// quiet hours, globally snoozed, or have muted this beacon. Surviving
  /// recipients carry their lock-screen-safe preference for copy selection.
  Future<List<_GatedRecipient>> _filterByPushPreference(
    BeaconNotificationIntent intent,
    List<BeaconNotificationRecipient> recipients,
  ) async {
    final now = DateTime.timestamp();
    final category = categoryOf(intent.kind);
    final beaconId = intent.beaconId.isEmpty ? null : intent.beaconId;
    final allowed = <_GatedRecipient>[];
    for (final r in recipients) {
      final prefs = await _preferences.getForAccount(r.userId);
      final muted = beaconId == null
          ? const <String>{}
          : await _preferences.getMutedBeaconIds(r.userId, now);
      final ok = _gate.allowsChannel(
        channel: NotificationChannel.push,
        category: category,
        prefs: prefs,
        now: now,
        beaconId: beaconId,
        mutedBeaconIds: muted,
      );
      if (ok) {
        allowed.add(
          (recipient: r, lockScreenSafe: prefs.lockScreenSafe),
        );
      } else {
        _logger.fine(
          '[FCM] push suppressed by prefs receiverId=${r.userId} '
          'category=${category.name} kind=${intent.kind.name}',
        );
      }
    }
    return allowed;
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

/// A recipient that passed the push-preference gate, plus their lock-screen
/// redaction preference (chooses full vs privacy-safe copy).
typedef _GatedRecipient = ({
  BeaconNotificationRecipient recipient,
  bool lockScreenSafe,
});
