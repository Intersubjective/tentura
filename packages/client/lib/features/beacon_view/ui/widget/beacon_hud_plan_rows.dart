import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/coordination/beacon_you_plan_slots.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/ui/util/plan_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_composer.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_table.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

import 'beacon_hud_action_button.dart';

/// What the Request HUD needs to draw the plan (#220 §5.2): the plan as the
/// viewer reads it, the clock and the actions. One fetch per Request — the
/// same `PlanCubit` feeds the Plan tab.
@immutable
class BeaconHudPlanData {
  const BeaconHudPlanData({
    required this.plan,
    required this.viewerId,
    required this.now,
    required this.people,
    this.busyStepIds = const {},
    this.onToggleDone,
    this.onAck,
    this.onCantMake,
    this.onOpenStep,
    this.onOpenPlan,
  });

  final BeaconPlan plan;
  final String viewerId;
  final DateTime now;
  final PlanPeople people;

  /// Steps with a tick in flight (their «Готово» is disabled).
  final Set<String> busyStepIds;

  /// One-tap «Готово»; null when the viewer may not tick.
  final ValueChanged<String>? onToggleDone;

  /// «Понятно».
  final VoidCallback? onAck;

  /// «Не успеваю» on a step of the viewer.
  final ValueChanged<PlanStep>? onCantMake;

  /// Opens the step card.
  final ValueChanged<String>? onOpenStep;

  /// Opens the Plan tab.
  final VoidCallback? onOpenPlan;

  bool get hasSteps => !plan.isEmpty;
}

/// Test keys of the HUD plan rows.
abstract final class BeaconHudPlanKeys {
  static const you = Key('hud-plan-you');
  static const byPlan = Key('hud-plan-by-plan');
  static const next = Key('hud-plan-next');
  static const done = Key('hud-plan-done');
  static const ack = Key('hud-plan-ack');
  static const cantMake = Key('hud-plan-cant-make');
  static const counter = Key('hud-plan-counter');
  static const overdue = Key('hud-plan-overdue');
}

/// The ladder slots for [data] (pure, see [deriveBeaconYouPlanSlots]).
BeaconYouPlanSlots beaconHudPlanSlots(
  BeaconHudPlanData data, {
  required bool systemOccupiesYou,
  required bool requestFinished,
}) => deriveBeaconYouPlanSlots(
  plan: data.plan.viewerYouInput(now: data.now, viewerId: data.viewerId),
  systemOccupiesYou: systemOccupiesYou,
  requestFinished: requestFinished,
  now: data.now,
);

/// HUD rows for the plan: the YOU replacement and BY PLAN / NEXT after it.
BeaconHudPlanRows buildBeaconHudPlanRows(
  BuildContext context,
  BeaconHudPlanData data, {
  required bool systemOccupiesYou,
  required bool requestFinished,
}) {
  final l10n = L10n.of(context)!;
  final slots = beaconHudPlanSlots(
    data,
    systemOccupiesYou: systemOccupiesYou,
    requestFinished: requestFinished,
  );
  BeaconHudMetadataEntry? entry(
    PlanYouSlot? slot, {
    required Key key,
    required IconData icon,
    required String label,
    bool muted = false,
  }) => slot == null
      ? null
      : BeaconHudMetadataEntry(
          icon: icon,
          semanticsLabel: label,
          body: KeyedSubtree(
            key: key,
            child: _PlanSlotBody(
              slot: slot,
              label: label,
              data: data,
              muted: muted,
            ),
          ),
        );
  return (
    you: entry(
      slots.you,
      key: BeaconHudPlanKeys.you,
      icon: BeaconHudRowIcons.you,
      label: l10n.beaconHudYouLabel,
    ),
    after: [
      ?entry(
        slots.byPlan,
        key: BeaconHudPlanKeys.byPlan,
        icon: BeaconHudRowIcons.plan,
        label: l10n.beaconHudByPlanLabel,
      ),
      ?entry(
        slots.next,
        key: BeaconHudPlanKeys.next,
        icon: BeaconHudRowIcons.next,
        label: l10n.beaconHudNextLabel,
        muted: true,
      ),
    ],
  );
}

/// The NOW row when the plan set it: «10:00 Иван: Привезти доски» with
/// «по плану · шаг 3/9». Null when the manual line (or nothing) wins.
({String text, String subline})? beaconHudPlanNowLine({
  required BeaconHudPlanData data,
  required String manualText,
  required DateTime? manualSetAt,
  required bool openFamily,
  required L10n l10n,
}) {
  final now = data.plan.effectiveNow(
    manualText: manualText,
    manualSetAt: manualSetAt,
    openFamily: openFamily,
    now: data.now,
  );
  final step = now.step;
  if (!now.isPlan || step == null) return null;
  final time = planHudTime(step.startAt!, data.now, l10n.localeName);
  final assignee = step.assigneeId;
  return (
    text: assignee == null
        ? l10n.beaconHudNowPlanLineUnassigned(time, step.title)
        : l10n.beaconHudNowPlanLine(
            time,
            data.people.nameOf(assignee, l10n),
            step.title,
          ),
    subline: l10n.beaconHudNowByPlan(now.index, now.count),
  );
}

/// `10:00` today, `сб, 12 окт. 10:00` on another day (viewer's zone).
String planHudTime(DateTime t, DateTime now, String localeName) =>
    PlanDays.isSameDayLocal(t, now)
    ? planTime(t, localeName)
    : planDayTime(t, localeName);

class _PlanSlotBody extends StatelessWidget {
  const _PlanSlotBody({
    required this.slot,
    required this.label,
    required this.data,
    this.muted = false,
  });

  final PlanYouSlot slot;
  final String label;
  final BeaconHudPlanData data;
  final bool muted;

  @override
  Widget build(BuildContext context) => switch (slot.kind) {
    PlanYouSlotKind.pendingAck => _PendingBody(
      label: label,
      data: data,
      slot: slot,
    ),
    PlanYouSlotKind.step => _StepBody(
      label: label,
      data: data,
      slot: slot,
      muted: muted,
    ),
    PlanYouSlotKind.freeUntil => _LabeledText(
      label: label,
      text: L10n.of(context)!.beaconHudFreeUntil(
        planHudTime(slot.freeUntil!, data.now, L10n.of(context)!.localeName),
      ),
      color: context.tt.textMuted,
    ),
  };
}

class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.label,
    required this.data,
    required this.slot,
    required this.muted,
  });

  final String label;
  final BeaconHudPlanData data;
  final PlanYouSlot slot;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final state = slot.step!;
    final step = data.plan.stepById(state.id);
    final overdueBy = slot.overdueBy;
    final overdue = overdueBy != null;
    final loc = l10n.localeName;
    final time = planStepTimeLabel(
      startAt: state.startAt,
      endAt: state.endAt,
      l10n: l10n,
    );
    final color = overdue && !muted
        ? tt.danger
        : muted
        ? tt.textMuted
        : tt.text;

    String? subline;
    if (muted) {
      final start = state.startAt;
      subline = slot.alsoRunning
          ? l10n.beaconHudAlsoRunning
          : start != null && start.isAfter(data.now)
          ? l10n.beaconHudInDuration(
              planDuration(start.difference(data.now), l10n),
            )
          : null;
    } else if (overdue) {
      final boundary = state.overdueBoundary!;
      subline = l10n.beaconHudDueBy(planHudTime(boundary, data.now, loc));
    } else if (step != null && step.description.trim().isNotEmpty) {
      subline = step.description.trim().split('\n').first;
    }

    final onToggle = data.onToggleDone;
    final onCantMake = data.onCantMake;
    final busy = data.busyStepIds.contains(state.id);
    final actions = !slot.actionable || step == null
        ? const <Widget>[]
        : [
            if (onToggle != null && slot.canTick)
              BeaconHudActionButton(
                key: BeaconHudPlanKeys.done,
                icon: Icons.check,
                label: l10n.planActionDone,
                filled: true,
                onPressed: busy ? null : () => onToggle(step.id),
              ),
            if (onCantMake != null)
              BeaconHudActionButton(
                key: BeaconHudPlanKeys.cantMake,
                icon: Icons.schedule,
                label: l10n.planActionCantMake,
                onPressed: () => onCantMake(step),
              ),
          ];

    return _PlanRowFrame(
      onOpen: data.onOpenStep == null ? null : () => data.onOpenStep!(state.id),
      openSemantics: l10n.beaconHudPlanOpenStep(state.title),
      head: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: TenturaText.typeLabel(tt.textMuted),
            ),
            TextSpan(
              text: state.title,
              style: TenturaText.hudBodySmall(color),
            ),
            TextSpan(
              text: '  $time',
              style: TenturaText.withTabular(
                TenturaText.bodySmall(muted ? tt.textMuted : tt.text),
              ),
            ),
            if (overdue && !muted)
              TextSpan(
                text:
                    '  ${l10n.beaconHudOverdueBy(planDuration(overdueBy, l10n))}',
                style: TenturaText.status(tt.danger),
              ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subline: subline,
      sublineColor: overdue && !muted ? tt.danger : tt.textMuted,
      actions: actions,
    );
  }
}

class _PendingBody extends StatelessWidget {
  const _PendingBody({
    required this.label,
    required this.data,
    required this.slot,
  });

  final String label;
  final BeaconHudPlanData data;
  final PlanYouSlot slot;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final plan = data.plan;
    final pending = plan.viewerPending;
    if (pending == null || pending.changes.isEmpty) {
      return const SizedBox.shrink();
    }
    final actor = pending.actorIds.isEmpty
        ? data.people.nameOf(plan.lastEditedById, l10n)
        : [
            for (final id in pending.actorIds) data.people.nameOf(id, l10n),
          ].join(', ');
    final editedAt = plan.lastEditedAt;
    final when = editedAt == null
        ? ''
        : compactRelativeTimeAgo(when: editedAt, now: data.now, l10n: l10n);
    final changedStepIds = plan.viewerPendingStepIds;
    final String text;
    if (changedStepIds.length == 1) {
      final change = pending.changes.first.change;
      text = l10n.planChangeOne(
        actor,
        when,
        change.title,
        planPendingChangeText(
          change,
          data.viewerId,
          (id) => data.people.nameOf(id, l10n),
          l10n,
        ),
      );
    } else {
      text = l10n.planChangeMany(actor, when, changedStepIds.length);
    }

    // «Не успеваю» is offered on a live, open step of the viewer the
    // change touches — the current one first.
    PlanStep? cantMakeStep;
    final current = slot.step;
    for (final id in [?current?.id, ...changedStepIds]) {
      final s = plan.stepById(id);
      if (s != null && s.assigneeId == data.viewerId && !s.isDone) {
        cantMakeStep = s;
        break;
      }
    }
    final onToggle = data.onToggleDone;
    final onAck = data.onAck;
    final onCantMake = data.onCantMake;
    final tickStep = slot.canTick && current != null ? current : null;
    return _PlanRowFrame(
      head: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: TenturaText.typeLabel(tt.textMuted),
            ),
            TextSpan(text: text, style: TenturaText.hudBodySmall(tt.info)),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        if (onAck != null)
          BeaconHudActionButton(
            key: BeaconHudPlanKeys.ack,
            icon: Icons.done_all,
            label: l10n.planActionAck,
            filled: true,
            onPressed: onAck,
          ),
        if (onToggle != null && tickStep != null)
          BeaconHudActionButton(
            key: BeaconHudPlanKeys.done,
            icon: Icons.check,
            label: l10n.planActionDone,
            onPressed: data.busyStepIds.contains(tickStep.id)
                ? null
                : () => onToggle(tickStep.id),
          ),
        if (onCantMake != null && cantMakeStep != null)
          BeaconHudActionButton(
            key: BeaconHudPlanKeys.cantMake,
            icon: Icons.schedule,
            label: l10n.planActionCantMake,
            onPressed: () => onCantMake(cantMakeStep!),
          ),
      ],
    );
  }
}

/// Head line (tappable when [onOpen] is set), optional muted subline and a
/// wrap of actions. Actions stay outside the tap target so each keeps its
/// own semantics.
class _PlanRowFrame extends StatelessWidget {
  const _PlanRowFrame({
    required this.head,
    this.subline,
    this.sublineColor,
    this.actions = const [],
    this.onOpen,
    this.openSemantics,
  });

  final Widget head;
  final String? subline;
  final Color? sublineColor;
  final List<Widget> actions;
  final VoidCallback? onOpen;
  final String? openSemantics;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    Widget text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        head,
        if (subline != null)
          Text(
            subline!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TenturaText.bodySmall(sublineColor ?? tt.textMuted),
          ),
      ],
    );
    if (onOpen != null) {
      text = Semantics(
        button: true,
        hint: openSemantics,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(tt.buttonRadius),
          child: SizedBox(width: double.infinity, child: text),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        text,
        if (actions.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: tt.tightGap),
            child: Wrap(
              spacing: tt.rowGap,
              runSpacing: tt.tightGap,
              children: actions,
            ),
          ),
      ],
    );
  }
}

class _LabeledText extends StatelessWidget {
  const _LabeledText({
    required this.label,
    required this.text,
    required this.color,
  });

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: TenturaText.typeLabel(tt.textMuted),
          ),
          TextSpan(text: text, style: TenturaText.hudBodySmall(color)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
