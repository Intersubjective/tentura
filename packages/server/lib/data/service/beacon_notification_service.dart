import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/beacon_notification_recipient.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/beacon_notification_copy_builder.dart';
import 'package:tentura_server/domain/notification/beacon_notification_recipient_resolver.dart';
import 'package:tentura_server/domain/port/beacon_notification_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';
import 'package:tentura_server/domain/port/fcm_batch_queue_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';

@LazySingleton(as: BeaconNotificationPort)
class BeaconNotificationService implements BeaconNotificationPort {
  BeaconNotificationService(
    this._fcmBatch,
    this._fcmTokens,
    this._fcmRemote,
    this._users,
    this._context,
    this._logger,
  );

  final FcmBatchQueuePort _fcmBatch;
  final FcmTokenRepositoryPort _fcmTokens;
  final FcmRemoteRepositoryPort _fcmRemote;
  final UserRepositoryPort _users;
  final BeaconRoomNotificationContextPort _context;
  final Logger _logger;

  static const _resolver = BeaconNotificationRecipientResolver();
  static const _copyBuilder = BeaconNotificationCopyBuilder();

  @override
  Future<void> dispatch(BeaconNotificationIntent intent) async {
    final ctx = await _loadContext(intent);
    final recipients = _resolver.resolveRecipients(intent: intent, ctx: ctx);
    if (recipients.isEmpty) {
      _logger.fine(
        '[FCM] dispatch skipped: no recipients kind=${intent.kind.name} '
        'beaconId=${intent.beaconId}',
      );
      return;
    }

    final actor = await _users.getById(intent.actorUserId);
    final copy = _copyBuilder.build(
      intent: intent,
      actorDisplayName: actor.title,
    );

    if (intent.kind == NotificationKind.reviewReady) {
      await _sendDirect(
        intent: intent,
        recipients: recipients,
        copy: copy,
      );
      return;
    }

    for (final r in recipients) {
      await _enqueue(
        receiverId: r.userId,
        intent: intent,
        priority: r.priority,
        copy: copy,
        reason: r.reason.name,
      );
    }
  }

  Future<void> _sendDirect({
    required BeaconNotificationIntent intent,
    required List<BeaconNotificationRecipient> recipients,
    required BeaconNotificationCopy copy,
  }) async {
    for (final r in recipients) {
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
