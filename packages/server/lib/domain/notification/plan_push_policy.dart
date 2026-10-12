/// Request plan («либретто», #220 §5.9): which plan pushes go out at once
/// with their own buttons, what those buttons do and how long such a push
/// may wait. Pure; `BeaconNotificationService` signs and sends.
library;

import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/plan/push_action.dart';

/// Plan obligations pushed directly with buttons, never coalesced by the
/// batch queue.
bool isPlanObligationPushKind(NotificationKind kind) => switch (kind) {
  NotificationKind.planStepDue ||
  NotificationKind.planStepTurn ||
  NotificationKind.planChangePending ||
  NotificationKind.planStepReminder ||
  NotificationKind.planStepOverdue => true,
  _ => false,
};

/// How long a plan push may wait for delivery: a reminder is useless once
/// the step started.
int planPushTtlSeconds(NotificationKind kind) => switch (kind) {
  NotificationKind.planStepReminder => kPlanReminderLead.inSeconds,
  _ => const Duration(hours: 1).inSeconds,
};

/// What the buttons of a plan push of [kind] do: «Готово» on a step that is
/// due, about to start or overdue; «Понятно» on a change to the person's
/// steps; nothing on «your turn» (a tap opens the step) or without a step.
PushAction? planPushActionFor({
  required NotificationKind kind,
  required String? stepId,
}) => switch (kind) {
  NotificationKind.planStepDue ||
  NotificationKind.planStepReminder ||
  NotificationKind.planStepOverdue when stepId != null && stepId.isNotEmpty =>
    PushAction.done,
  NotificationKind.planChangePending => PushAction.ack,
  _ => null,
};

/// The buttons shown for [action]: «Готово» + «Открыть», or «Понятно».
List<FcmNotificationAction> planPushButtonsFor(
  PushAction action,
  String locale,
) {
  final ru = _isRussian(locale);
  return switch (action) {
    PushAction.done => [
      FcmNotificationAction(id: 'done', title: ru ? 'Готово' : 'Done'),
      FcmNotificationAction(id: 'open', title: ru ? 'Открыть' : 'Open'),
    ],
    PushAction.ack => [
      FcmNotificationAction(id: 'ack', title: ru ? 'Понятно' : 'Got it'),
    ],
  };
}

/// What the service worker says after a button tap.
FcmActionFeedback planPushFeedback(String locale) => _isRussian(locale)
    ? const FcmActionFeedback(
        done: 'Отмечено',
        ack: 'Подтверждено',
        failed: 'Не получилось — откройте шаг',
      )
    : const FcmActionFeedback(
        done: 'Marked done',
        ack: 'Confirmed',
        failed: "Didn't work — open the step",
      );

bool _isRussian(String locale) => locale.toLowerCase().startsWith('ru');
