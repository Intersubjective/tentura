import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/beacon_plan.dart';
import '../util/plan_presenter.dart';

/// One step of the Plan list: tick box, time, assignee avatar, title and the
/// status meta (overdue, «отметка: X», «ждёт подтверждения»).
class PlanStepRow extends StatelessWidget {
  const PlanStepRow({
    required this.step,
    required this.people,
    required this.now,
    required this.tickable,
    required this.showAckState,
    this.dimmed = false,
    this.busy = false,
    this.onToggleDone,
    this.onTap,
    super.key,
  });

  final PlanStep step;
  final PlanPeople people;
  final DateTime now;
  final bool tickable;

  /// Editors see «ждёт подтверждения: X».
  final bool showAckState;
  final bool dimmed;
  final bool busy;
  final VoidCallback? onToggleDone;
  final VoidCallback? onTap;

  static Key keyFor(String stepId) => Key('plan-step-$stepId');

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final overdue = step.overdueBy(now);
    final done = step.isDone;
    final assigneeId = step.assigneeId;
    final start = step.startAt;
    final end = step.endAt;
    final timeLabel = start != null
        ? planTime(start, l10n.localeName)
        : end != null
        ? l10n.planEndOnly(planTime(end, l10n.localeName))
        : l10n.planUntimed;

    final meta = <Widget>[
      if (start != null && end != null)
        TenturaStatusText('–${planTime(end, l10n.localeName)}'),
      if (assigneeId == null)
        TenturaStatusText(l10n.planNoAssignee, tone: TenturaTone.warn)
      else
        TenturaStatusText(people.nameOf(assigneeId, l10n)),
      if (overdue != null)
        Semantics(
          label: l10n.planStepOverdueSemantics(step.title),
          child: TenturaStatusText(
            '⏰ +${planDuration(overdue, l10n)}',
            tone: TenturaTone.danger,
          ),
        ),
      if (done && step.doneById != null && step.doneById != assigneeId)
        TenturaStatusText(l10n.planDoneBy(people.nameOf(step.doneById, l10n))),
      if (showAckState && step.assigneeAckPending && assigneeId != null)
        TenturaStatusText(
          l10n.planAwaitingAck(people.nameOf(assigneeId, l10n)),
          tone: TenturaTone.info,
        ),
    ];

    final textColor = done ? tt.textMuted : tt.text;
    final row = InkWell(
      key: keyFor(step.id),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tt.screenHPadding,
          vertical: tt.tightGap,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: done
                  ? l10n.planStepCheckboxUndone(step.title)
                  : l10n.planStepCheckboxDone(step.title),
              child: Checkbox(
                value: done,
                onChanged: tickable && !busy && onToggleDone != null
                    ? (_) => onToggleDone!()
                    : null,
              ),
            ),
            SizedBox(width: tt.tightGap),
            Padding(
              padding: EdgeInsets.only(top: tt.rowGap + tt.tightGap),
              child: SizedBox(
                width: tt.avatarSize * 1.75,
                child: Semantics(
                  label: step.isUntimed ? l10n.planUntimedSemantics : null,
                  child: Text(
                    timeLabel,
                    style: TenturaText.withTabular(
                      TenturaText.status(
                        overdue != null ? tt.danger : tt.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: tt.rowGap),
              child: assigneeId == null
                  ? Icon(
                      Icons.person_off_outlined,
                      size: tt.avatarTinySize,
                      color: tt.warn,
                    )
                  : TenturaAvatar(
                      profile: people.profileOf(assigneeId, l10n),
                      sizeBucket: TenturaAvatarSize.tiny,
                    ),
            ),
            SizedBox(width: tt.avatarTextGap),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: tt.rowGap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.title, style: TenturaText.body(textColor)),
                    if (meta.isNotEmpty)
                      Wrap(
                        spacing: tt.iconTextGap * 2,
                        runSpacing: tt.tightGap,
                        children: meta,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return dimmed ? Opacity(opacity: 0.5, child: row) : row;
  }
}

/// The red «now» line between past and future steps.
class PlanNowLine extends StatelessWidget {
  const PlanNowLine({required this.now, super.key});

  static const lineKey = Key('plan-now-line');

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Padding(
      key: lineKey,
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.tightGap,
      ),
      child: Row(
        children: [
          Expanded(child: Divider(color: tt.danger)),
          SizedBox(width: tt.iconTextGap),
          Text(
            l10n.planNowLineLabel(planTime(now, l10n.localeName)),
            style: TenturaText.status(tt.danger),
          ),
          SizedBox(width: tt.iconTextGap),
          Expanded(child: Divider(color: tt.danger)),
        ],
      ),
    );
  }
}

/// Day header of the Plan list (viewer's zone).
class PlanDayHeader extends StatelessWidget {
  const PlanDayHeader({required this.day, super.key});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.sectionGap,
        tt.screenHPadding,
        tt.tightGap,
      ),
      child: Text(
        planDayLabel(day, l10n.localeName).toUpperCase(),
        style: TenturaText.typeLabel(tt.textMuted),
      ),
    );
  }
}
