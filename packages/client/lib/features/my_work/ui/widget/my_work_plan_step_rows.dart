import 'package:flutter/material.dart';
import 'package:tentura_root/domain/plan/plan_schedule.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/coordination/beacon_you_plan_slots.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_viewer_slice.dart';
import 'package:tentura/features/beacon_plan/ui/util/plan_presenter.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_plan_rows.dart'
    show planHudTime;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

/// Test keys of the My Work plan rows.
abstract final class MyWorkPlanKeys {
  static const rows = Key('my-work-plan-rows');
  static const pending = Key('my-work-plan-pending');
  static const current = Key('my-work-plan-current');
  static const next = Key('my-work-plan-next');
  static const done = Key('my-work-plan-done');
  static const ack = Key('my-work-plan-ack');
  static const cantMake = Key('my-work-plan-cant-make');
}

/// One plan row of a My Work card (#220 §5.8, mockups §8).
enum MyWorkPlanRowKind { pending, current, next }

/// A row of [MyWorkPlanStepRows], derived from the shared HUD ladder.
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

/// Plan step subcards inside a My Work card's obligation block (#220 §5.8).
///
/// A step of yours that is due is an obligation: it has actions and no ×,
/// because hiding it silently would lie to whoever waits on it.
class MyWorkPlanStepRows extends StatelessWidget {
  const MyWorkPlanStepRows({
    required this.slice,
    required this.now,
    required this.viewerId,
    required this.nameOf,
    this.onDone,
    this.onAck,
    this.onOpenStep,
    super.key,
  });

  final PlanViewerSlice slice;
  final DateTime now;
  final String viewerId;

  /// Display name of a person the plan mentions (actors of a change).
  final String Function(String? userId) nameOf;

  /// «Готово» on a step (by id).
  final ValueChanged<String>? onDone;

  /// «Понятно» up to the slice's head.
  final ValueChanged<int>? onAck;

  /// Opens the step (the Plan tab), also «Не успеваю».
  final ValueChanged<String>? onOpenStep;

  @override
  Widget build(BuildContext context) {
    final rows = deriveMyWorkPlanRows(slice, now);
    if (rows.isEmpty) return const SizedBox.shrink();
    final tt = context.tt;
    return Column(
      key: MyWorkPlanKeys.rows,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) SizedBox(height: tt.tightGap),
          switch (row.kind) {
            MyWorkPlanRowKind.pending => _PendingRow(row: row, parent: this),
            MyWorkPlanRowKind.current => _StepRow(row: row, parent: this),
            MyWorkPlanRowKind.next => _StepRow(row: row, parent: this),
          },
        ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.row, required this.parent});

  final MyWorkPlanRow row;
  final MyWorkPlanStepRows parent;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final step = row.step!;
    final now = parent.now;
    final muted = row.kind == MyWorkPlanRowKind.next;
    final overdueBy = row.overdueBy;
    final overdue = overdueBy != null;
    final start = step.startAt;
    final time = start == null ? '' : planHudTime(start, now, l10n.localeName);
    final titleColor = muted
        ? tt.textMuted
        : overdue
        ? tt.danger
        : tt.text;

    String? subline;
    if (muted) {
      subline = row.alsoRunning
          ? l10n.beaconHudAlsoRunning
          : start != null && start.isAfter(now)
          ? l10n.beaconHudInDuration(planDuration(start.difference(now), l10n))
          : null;
    } else if (overdue) {
      subline = l10n.beaconHudDueBy(
        planHudTime(step.overdueBoundary!, now, l10n.localeName),
      );
    } else {
      final description = parent.slice.stepById(step.id)?.description.trim();
      if (description != null && description.isNotEmpty) {
        subline = description.split('\n').first;
      }
    }

    final onDone = parent.onDone;
    final onOpen = parent.onOpenStep;
    return KeyedSubtree(
      key: muted ? MyWorkPlanKeys.next : MyWorkPlanKeys.current,
      child: _RowFrame(
        icon: muted ? BeaconHudRowIcons.next : BeaconHudRowIcons.plan,
        iconColor: muted ? tt.textMuted : titleColor,
        onTap: onOpen == null ? null : () => onOpen(step.id),
        tapSemantics: l10n.beaconHudPlanOpenStep(step.title),
        head: Text.rich(
          TextSpan(
            children: [
              if (time.isNotEmpty)
                TextSpan(
                  text: '$time  ',
                  style: TenturaText.withTabular(
                    TenturaText.bodySmall(muted ? tt.textMuted : tt.text),
                  ),
                ),
              TextSpan(
                text: step.title,
                style: TenturaText.hudBodySmall(titleColor),
              ),
              if (overdue)
                TextSpan(
                  text:
                      '  ${l10n.beaconHudOverdueBy(planDuration(overdueBy, l10n))}',
                  style: TenturaText.status(tt.danger),
                ),
              if (muted)
                TextSpan(
                  text: '  ${l10n.beaconHudNextLabel}',
                  style: TenturaText.typeLabel(tt.textMuted),
                ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subline: subline,
        sublineColor: overdue ? tt.danger : tt.textMuted,
        actions: muted
            ? const []
            : [
                if (onDone != null)
                  FilledButton.tonal(
                    key: MyWorkPlanKeys.done,
                    onPressed: () => onDone(step.id),
                    style: _buttonStyle(context),
                    child: Text(l10n.planActionDone),
                  ),
                if (onOpen != null)
                  TextButton(
                    key: MyWorkPlanKeys.cantMake,
                    onPressed: () => onOpen(step.id),
                    style: _buttonStyle(context),
                    child: Text(l10n.planActionCantMake),
                  ),
              ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.row, required this.parent});

  final MyWorkPlanRow row;
  final MyWorkPlanStepRows parent;

  @override
  Widget build(BuildContext context) {
    final pending = parent.slice.pendingAck;
    if (pending == null) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final actor = pending.actorIds.isEmpty
        ? l10n.myWorkPlanSomeone
        : [
            for (final id in pending.actorIds)
              pending.actorNames[id] ?? parent.nameOf(id),
          ].join(', ');
    final lastAt = pending.lastAt;
    final when = lastAt == null
        ? ''
        : compactRelativeTimeAgo(when: lastAt, now: parent.now, l10n: l10n);
    final sample = pending.sample;
    final text = pending.stepIds.length <= 1 && sample != null
        ? l10n.planChangeOne(
            actor,
            when,
            sample.title,
            planPendingChangeText(sample, parent.viewerId, parent.nameOf, l10n),
          )
        : l10n.planChangeMany(
            actor,
            when,
            pending.stepIds.isEmpty
                ? pending.changeCount
                : pending.stepIds.length,
          );
    final onAck = parent.onAck;
    final onDone = parent.onDone;
    final tick = row.canTickStep;
    final firstStep = pending.stepIds.isEmpty ? null : pending.stepIds.first;
    final onOpen = parent.onOpenStep;
    return KeyedSubtree(
      key: MyWorkPlanKeys.pending,
      child: _RowFrame(
        icon: Icons.edit_note_outlined,
        iconColor: tt.info,
        onTap: onOpen == null || firstStep == null
            ? null
            : () => onOpen(firstStep),
        tapSemantics: text,
        head: Text(
          text,
          style: TenturaText.hudBodySmall(tt.info),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (onAck != null)
            FilledButton.tonal(
              key: MyWorkPlanKeys.ack,
              onPressed: () => onAck(pending.headSeq),
              style: _buttonStyle(context),
              child: Text(l10n.planActionAck),
            ),
          if (onDone != null && tick != null)
            TextButton(
              key: MyWorkPlanKeys.done,
              onPressed: () => onDone(tick.id),
              style: _buttonStyle(context),
              child: Text(l10n.planActionDone),
            ),
        ],
      ),
    );
  }
}

ButtonStyle _buttonStyle(BuildContext context) {
  final tt = context.tt;
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, tt.buttonHeight)),
    tapTargetSize: MaterialTapTargetSize.padded,
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: tt.rowGap),
    ),
  );
}

/// Icon, a tappable head and subline, then the actions right-aligned below.
class _RowFrame extends StatelessWidget {
  const _RowFrame({
    required this.icon,
    required this.iconColor,
    required this.head,
    required this.tapSemantics,
    this.subline,
    this.sublineColor,
    this.onTap,
    this.actions = const [],
  });

  final IconData icon;
  final Color iconColor;
  final Widget head;
  final String tapSemantics;
  final String? subline;
  final Color? sublineColor;
  final VoidCallback? onTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: tt.iconSize, color: iconColor),
        SizedBox(width: tt.iconTextGap),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              head,
              if (subline case final String line?)
                Text(
                  line,
                  style: TenturaText.bodySmall(sublineColor ?? tt.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onTap == null)
          body
        else
          Semantics(
            button: true,
            label: tapSemantics,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(tt.buttonRadius),
              child: body,
            ),
          ),
        if (actions.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: tt.tightGap,
              runSpacing: tt.tightGap,
              alignment: WrapAlignment.end,
              children: actions,
            ),
          ),
      ],
    );
  }
}
