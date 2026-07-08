import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_channel.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/entity/invite_accepted_notification_intent.dart';
import 'package:tentura_server/domain/notification/notification_preference_gate.dart';
import 'package:tentura_server/domain/port/email_notification_port.dart';
import 'package:tentura_server/domain/port/fcm_batch_queue_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/invite_accepted_notification_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';

@LazySingleton(as: InviteAcceptedNotificationPort)
class InviteAcceptedNotificationService implements InviteAcceptedNotificationPort {
  InviteAcceptedNotificationService(
    this._outbox,
    this._preferences,
    this._fcmTokens,
    this._fcmBatch,
    this._emailNotification,
    this._logger,
  );

  final NotificationOutboxRepositoryPort _outbox;
  final NotificationPreferenceRepositoryPort _preferences;
  final FcmTokenRepositoryPort _fcmTokens;
  final FcmBatchQueuePort _fcmBatch;
  final EmailNotificationPort _emailNotification;
  final Logger _logger;

  static const _gate = NotificationPreferenceGate();

  @override
  Future<void> notifyInviteAccepted(InviteAcceptedNotificationIntent intent) async {
    final inviterId = intent.inviterUserId;
    if (inviterId.isEmpty) {
      return;
    }
    final now = DateTime.timestamp();
    const category = NotificationCategory.connections;
    const kind = NotificationKind.inviteAccepted;
    const priority = NotificationPriority.normal;

    final title = intent.accepterDisplayName.trim().isEmpty
        ? 'Invitation accepted'
        : '${intent.accepterDisplayName} joined via your invitation';
    const body = 'You are now connected on Tentura.';
    final actionUrl = intent.actionUrl;

    final dedupKey = '$inviterId|${category.name}|${intent.accepterUserId}';

    try {
      await _outbox.enqueue(
        accountId: inviterId,
        category: category,
        kind: kind,
        priority: priority,
        title: title,
        body: body,
        actionUrl: actionUrl,
        dedupKey: dedupKey,
        actorUserId: intent.accepterUserId,
      );
    } on Object catch (e, s) {
      _logger.warning('[Center] inviteAccepted outbox write failed for $inviterId', e, s);
    }

    final prefs = await _preferences.getForAccount(inviterId);

    final pushAllowed = _gate.allowsChannel(
      channel: NotificationChannel.push,
      category: category,
      prefs: prefs,
      now: now,
    );
    if (pushAllowed) {
      final tokens = await _fcmTokens.getTokensByUserId(inviterId);
      if (tokens.isNotEmpty) {
        _fcmBatch.enqueue(
          receiverId: inviterId,
          fcmTokens: tokens.map((t) => t.token).toSet(),
          message: FcmNotificationEntity(
            title: title,
            body: body,
            actionUrl: actionUrl,
            kind: kind,
            priority: priority,
          ),
        );
      }
    }

    final emailAllowed = _gate.allowsChannel(
      channel: NotificationChannel.email,
      category: category,
      prefs: prefs,
      now: now,
    );
    if (emailAllowed) {
      unawaited(
        _emailNotification.considerImmediateByCategory(
          recipientUserId: inviterId,
          dedupKey: dedupKey,
          title: title,
          body: body,
          actionUrl: actionUrl,
          categoryScope: category.name,
        ),
      );
    }
  }
}

