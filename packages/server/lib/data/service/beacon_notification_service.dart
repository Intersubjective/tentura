import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_channel.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/beacon_notification_copy_builder.dart';
import 'package:tentura_server/domain/notification/notification_preference_gate.dart';
import 'package:tentura_server/domain/notification/plan_push_policy.dart';
import 'package:tentura_server/domain/plan/push_action.dart';
import 'package:tentura_server/domain/port/beacon_notification_port.dart';
import 'package:tentura_server/domain/port/beacon_plan_repository_port.dart';
import 'package:tentura_server/domain/port/email_notification_port.dart';
import 'package:tentura_server/domain/port/fcm_batch_queue_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/port/push_action_token_port.dart';

@LazySingleton(as: BeaconNotificationPort)
class BeaconNotificationService implements BeaconNotificationPort {
  BeaconNotificationService(
    this._fcmBatch,
    this._fcmTokens,
    this._fcmRemote,
    this._preferences,
    this._emailNotification,
    this._logger, {
    PushActionTokenPort? pushActionTokens,
    BeaconPlanRepositoryPort? planRepository,
  }) : _pushActionTokens = pushActionTokens,
       _planRepository = planRepository;

  final FcmBatchQueuePort _fcmBatch;
  final FcmTokenRepositoryPort _fcmTokens;
  final FcmRemoteRepositoryPort _fcmRemote;
  final NotificationPreferenceRepositoryPort _preferences;
  final EmailNotificationPort _emailNotification;
  final Logger _logger;

  /// Signs plan push buttons (#220 §5.9); without it plan pushes carry no
  /// buttons and a tap opens the step.
  final PushActionTokenPort? _pushActionTokens;

  /// Reads the plan head a «Понятно» button confirms up to.
  final BeaconPlanRepositoryPort? _planRepository;

  static const _copyBuilder = BeaconNotificationCopyBuilder();
  static const _gate = NotificationPreferenceGate();

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
        beaconKind: decision.beaconKind,
      );
      final preferences = await _preferences.getForAccount(
        decision.recipientId,
      );
      final fullCopy = _localizedCopy(decision, intent, preferences.locale);
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
      if (pushAllowed && isPlanObligationPushKind(decision.kind)) {
        // Plan obligations go out at once, one notification per step, with
        // their own buttons — never coalesced by the batch queue (§5.9).
        pushDelivered = await _sendPlanDirect(
          decision: decision,
          intent: intent,
          copy: preferences.lockScreenSafe
              ? _copyBuilder.lockScreenSafe(intent)
              : fullCopy,
          locale: preferences.locale,
        );
      } else if (pushAllowed) {
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
            channelCollapseKey: decision.dedupKey,
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
            channelCollapseKey: decision.dedupKey,
            title: decision.title,
            body: decision.body,
            actionUrl: decision.actionUrl,
            pushDelivered: pushDelivered,
          ),
        );
      }
    }
  }

  /// The job's stored English copy, or the recipient-language copy of it when
  /// the job carries the builder's own default sentence. Text a person wrote
  /// (an excerpt) is never translated.
  BeaconNotificationCopy _localizedCopy(
    AttentionChannelDecision decision,
    BeaconNotificationIntent intent,
    String locale,
  ) {
    final stored = BeaconNotificationCopy(
      title: decision.title,
      body: decision.body,
      actionUrl: decision.actionUrl,
    );
    if (!locale.toLowerCase().startsWith('ru')) return stored;
    final english = _copyBuilder.build(
      intent: intent,
      actorDisplayName: decision.title,
    );
    if (english.body != decision.body) return stored;
    final russian = _copyBuilder.build(
      intent: intent,
      actorDisplayName: decision.title,
      locale: locale,
    );
    return BeaconNotificationCopy(
      title: decision.title,
      body: russian.body,
      actionUrl: decision.actionUrl,
    );
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

  /// Sends a plan obligation push directly (bypassing [FcmBatchQueuePort])
  /// with its buttons and signed action token. Returns whether a device
  /// token existed.
  Future<bool> _sendPlanDirect({
    required AttentionChannelDecision decision,
    required BeaconNotificationIntent intent,
    required BeaconNotificationCopy copy,
    required String locale,
  }) async {
    final tokens = await _fcmTokens.getTokensByUserId(decision.recipientId);
    if (tokens.isEmpty) {
      _logDispatch(
        intent: intent,
        receiverUserId: decision.recipientId,
        actorUserId: intent.actorUserId,
        reason: decision.reason,
        hasToken: false,
        queuedOrDirect: 'skipped',
        coalescedCount: 0,
      );
      return false;
    }
    final beaconId = decision.beaconId ?? '';
    final stepId = decision.coordinationItemId;
    final buttons = await planPushButtons(
      kind: decision.kind,
      recipientId: decision.recipientId,
      beaconId: beaconId,
      stepId: stepId,
      locale: locale,
      tokens: _pushActionTokens,
      planRepository: _planRepository,
    );
    _logDispatch(
      intent: intent,
      receiverUserId: decision.recipientId,
      actorUserId: intent.actorUserId,
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
          beaconId: beaconId,
          coordinationItemId: stepId,
          kind: decision.kind,
          priority: decision.priority,
          stepId: stepId,
          actions: buttons.actions,
          actionToken: buttons.token,
          actionFeedback: buttons.actions.isEmpty
              ? null
              : planPushFeedback(locale),
          tag: stepId != null && stepId.isNotEmpty
              ? 'plan:$stepId'
              : 'plan:$beaconId',
          ttlSeconds: planPushTtlSeconds(decision.kind),
          urgency: 'high',
        ),
      ),
    );
    return true;
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
        beaconKind: intent.beaconKind,
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
}

/// Buttons of one plan push and the token behind them.
typedef PlanPushButtons = ({
  List<FcmNotificationAction> actions,
  String? token,
});

/// Buttons of a plan push ([planPushActionFor] decides which) and the token
/// that authorizes them; «Понятно» confirms up to the current plan head. No
/// token signer → no buttons.
Future<PlanPushButtons> planPushButtons({
  required NotificationKind kind,
  required String recipientId,
  required String beaconId,
  required String? stepId,
  required String locale,
  required PushActionTokenPort? tokens,
  required BeaconPlanRepositoryPort? planRepository,
}) async {
  const none = (actions: <FcmNotificationAction>[], token: null);
  if (tokens == null || beaconId.isEmpty) return none;
  final action = planPushActionFor(kind: kind, stepId: stepId);
  if (action == null) return none;
  int? seq;
  if (action == PushAction.ack) {
    final head = await planRepository?.getHead(beaconId);
    if (head == null) return none;
    seq = head.revisionSeq;
  }
  return (
    actions: planPushButtonsFor(action, locale),
    token: tokens.sign(
      PushActionClaims(
        accountId: recipientId,
        action: action,
        beaconId: beaconId,
        stepId: action == PushAction.done ? stepId : null,
        seq: seq,
      ),
    ),
  );
}
