import 'attention_event_classification.dart';

/// Request plan («либретто», #220) event types, by `eventType` payload name
/// and by server `presentationKey`.
const _planEventTypes = <String, String>{
  'planStepDue': 'plan_step_due',
  'planStepTurn': 'plan_step_turn',
  'planChangePending': 'plan_change_pending',
  'planStepReminder': 'plan_step_reminder',
  'planStepOverdue': 'plan_step_overdue',
  'planStepLate': 'plan_step_late',
  'planCantMake': 'plan_cant_make',
  'planStepUnassigned': 'plan_step_unassigned',
  'planEdited': 'plan_edited',
  'planStepDone': 'plan_step_done',
};

/// The plan event type (`planStepDue`, …) of a receipt, or null when it is
/// not a Request plan event. The one rule for «is this a plan receipt».
String? planReceiptEventType({
  required String? presentationKey,
  required String presentationPayloadJson,
}) {
  final type = attentionEventTypeOf(presentationPayloadJson);
  if (type != null && _planEventTypes.containsKey(type)) return type;
  for (final MapEntry(:key, :value) in _planEventTypes.entries) {
    if (value == presentationKey) return key;
  }
  return null;
}

/// Whether a receipt is a Request plan event (see [planReceiptEventType]).
bool isPlanReceipt({
  required String? presentationKey,
  required String presentationPayloadJson,
}) =>
    planReceiptEventType(
      presentationKey: presentationKey,
      presentationPayloadJson: presentationPayloadJson,
    ) !=
    null;
