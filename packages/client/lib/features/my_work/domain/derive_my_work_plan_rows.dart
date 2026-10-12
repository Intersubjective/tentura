import 'package:meta/meta.dart';
import 'package:tentura_root/domain/plan/plan_schedule.dart';

import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/plan_receipt_event_type.dart';
import 'package:tentura/domain/coordination/beacon_you_plan_slots.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_viewer_slice.dart';

/// One plan row of a My Work card (#220 §5.8, mockups §8).
enum MyWorkPlanRowKind { pending, current, next }

/// A row of the card's plan rows (`MyWorkPlanStepRows`), derived from the
/// shared HUD ladder.
@immutable
final class MyWorkPlanRow {
  const MyWorkPlanRow.pending({this.canTickStep})
    : kind = MyWorkPlanRowKind.pending,
      step = null,
      overdueBy = null,
      alsoRunning = false;

  const MyWorkPlanRow.current(PlanStepState this.step, {this.overdueBy})
    : kind = MyWorkPlanRowKind.current,
      alsoRunning = false,
      canTickStep = null;

  const MyWorkPlanRow.next(PlanStepState this.step, {this.alsoRunning = false})
    : kind = MyWorkPlanRowKind.next,
      overdueBy = null,
      canTickStep = null;

  final MyWorkPlanRowKind kind;
  final PlanStepState? step;
  final Duration? overdueBy;
  final bool alsoRunning;

  /// A pending row that touches the current step also offers its «Готово».
  final PlanStepState? canTickStep;
}

/// The plan rows of a card, at most three: a change waiting for «Понятно»
/// first (it never drops), then the current step with its actions, then a
/// muted «next» line without buttons (like the next piece in Tetris).
///
/// The same [deriveBeaconYouPlanSlots] ladder as the Request HUD, fed by the
/// server's slice instead of the whole plan. A «free until» slot is not a row
/// here: the muted next step already says when.
List<MyWorkPlanRow> deriveMyWorkPlanRows(PlanViewerSlice slice, DateTime now) {
  final slots = deriveBeaconYouPlanSlots(
    plan: slice.youInput(now),
    systemOccupiesYou: false,
    requestFinished: false,
    now: now,
  );
  MyWorkPlanRow? row(PlanYouSlot? slot) {
    if (slot == null) return null;
    final step = slot.step;
    return switch (slot.kind) {
      PlanYouSlotKind.pendingAck => MyWorkPlanRow.pending(
        canTickStep: slot.canTick ? step : null,
      ),
      PlanYouSlotKind.step when step != null && slot.actionable =>
        MyWorkPlanRow.current(step, overdueBy: slot.overdueBy),
      PlanYouSlotKind.step when step != null => MyWorkPlanRow.next(
        step,
        alsoRunning: slot.alsoRunning,
      ),
      _ => null,
    };
  }

  return [?row(slots.you), ?row(slots.byPlan), ?row(slots.next)];
}

/// Plan receipts the card's plan rows already show (#220 §5.8): the viewer's
/// step and change obligations, and the reminder / overdue notices of those
/// same steps. They stay in the card's attention facts (indicators) but not
/// in its event rows.
const _planRowReceiptTypes = {
  'planStepDue',
  'planStepTurn',
  'planChangePending',
  'planStepReminder',
  'planStepOverdue',
};

/// Whether [receipt] is a plan event the plan rows of a card stand for.
bool myWorkReceiptShownAsPlanRow(AttentionReceipt receipt) =>
    _planRowReceiptTypes.contains(
      planReceiptEventType(
        presentationKey: receipt.presentationKey,
        presentationPayloadJson: receipt.presentationPayloadJson,
      ),
    );
