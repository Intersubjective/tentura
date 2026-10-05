import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/beacon_plan.dart';
import '../bloc/plan_cubit.dart';
import '../util/plan_presenter.dart';
import 'plan_datetime_field.dart';
import 'plan_person_picker.dart';

/// Step card (tap on a row): details, tick / untick, «Не успеваю», edit and
/// a way into the discussion.
Future<void> showPlanStepSheet(
  BuildContext context, {
  required PlanCubit cubit,
  required String stepId,
  required PlanPeople people,
  VoidCallback? onEdit,
  VoidCallback? onOpenDiscussion,
}) => showTenturaAdaptiveSheet<void>(
  context: context,
  useRootNavigator: true,
  builder: (ctx) => BlocProvider.value(
    value: cubit,
    child: PlanStepSheet(
      stepId: stepId,
      people: people,
      onEdit: onEdit,
      onOpenDiscussion: onOpenDiscussion,
    ),
  ),
);

class PlanStepSheet extends StatelessWidget {
  const PlanStepSheet({
    required this.stepId,
    required this.people,
    this.onEdit,
    this.onOpenDiscussion,
    super.key,
  });

  final String stepId;
  final PlanPeople people;
  final VoidCallback? onEdit;
  final VoidCallback? onOpenDiscussion;

  void _toggle(BuildContext context) {
    unawaited(context.read<PlanCubit>().toggleDone(stepId));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocBuilder<PlanCubit, PlanState>(
      builder: (context, state) {
        final plan = state.plan;
        final step = plan?.stepById(stepId);
        if (plan == null || step == null) {
          return Padding(
            padding: tt.cardPadding,
            child: Text(l10n.planErrorStepNotFound),
          );
        }
        final now = DateTime.now();
        final overdue = step.overdueBy(now);
        final assigneeId = step.assigneeId;
        final isMine = assigneeId == state.viewerId;
        final member = assigneeId == null ? null : plan.memberOf(assigneeId);
        final ackedAt = member?.ackedAt;
        final peopleNamed = people.withNames(plan.names);
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: tt.screenHPadding,
              vertical: tt.rowGap,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.planStepOf(step.index, plan.steps.length),
                  style: TenturaText.typeLabel(tt.textMuted),
                ),
                SizedBox(height: tt.tightGap),
                Text(step.title, style: TenturaText.titleSmall(tt.text)),
                if (step.description.trim().isNotEmpty) ...[
                  SizedBox(height: tt.tightGap),
                  Text(step.description, style: TenturaText.body(tt.text)),
                ],
                SizedBox(height: tt.rowGap),
                Row(
                  children: [
                    if (assigneeId == null)
                      Icon(Icons.person_off_outlined, color: tt.warn)
                    else
                      TenturaAvatar(
                        profile: peopleNamed.profileOf(assigneeId, l10n),
                        sizeBucket: TenturaAvatarSize.tiny,
                      ),
                    SizedBox(width: tt.avatarTextGap),
                    Expanded(
                      child: Text(
                        peopleNamed.nameOf(assigneeId, l10n),
                        style: TenturaText.body(
                          assigneeId == null ? tt.warn : tt.text,
                        ),
                      ),
                    ),
                    Text(
                      planStepWhenLabel(
                        startAt: step.startAt,
                        endAt: step.endAt,
                        l10n: l10n,
                      ),
                      style: TenturaText.bodySmall(tt.textMuted),
                    ),
                  ],
                ),
                if (overdue != null) ...[
                  SizedBox(height: tt.tightGap),
                  TenturaStatusText(
                    '⏰ ${l10n.planStepLate(planDuration(overdue, l10n))}',
                    tone: TenturaTone.danger,
                  ),
                ],
                if (assigneeId != null && step.assigneeAckPending)
                  TenturaStatusText(
                    l10n.planStepNotAcked,
                    tone: TenturaTone.info,
                  )
                else if (assigneeId != null && ackedAt != null)
                  TenturaStatusText(
                    l10n.planStepAcked(planTime(ackedAt, l10n.localeName)),
                  ),
                if (step.isDone && step.doneById != null)
                  TenturaStatusText(
                    l10n.planDoneBy(peopleNamed.nameOf(step.doneById, l10n)),
                    tone: TenturaTone.good,
                  ),
                const TenturaHairlineDivider(),
                SizedBox(height: tt.rowGap),
                Wrap(
                  spacing: tt.rowGap,
                  runSpacing: tt.rowGap,
                  children: [
                    if (plan.tickable && step.isDone)
                      OutlinedButton(
                        onPressed: () => _toggle(context),
                        child: Text(l10n.planActionUndone),
                      ),
                    if (plan.tickable && !step.isDone)
                      FilledButton(
                        onPressed: () => _toggle(context),
                        child: Text(l10n.planActionDone),
                      ),
                    if (isMine && !step.isDone && plan.tickable)
                      OutlinedButton(
                        onPressed: () => showPlanCantMakeSheet(
                          context,
                          cubit: context.read<PlanCubit>(),
                          step: step,
                          people: peopleNamed,
                          onOpenDiscussion: onOpenDiscussion,
                        ),
                        child: Text(l10n.planActionCantMake),
                      ),
                    if (plan.editable && onEdit != null)
                      OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onEdit!();
                        },
                        child: Text(l10n.planActionEdit),
                      ),
                  ],
                ),
                if (onOpenDiscussion != null)
                  TenturaTextAction(
                    label: l10n.planDiscuss,
                    flushStart: true,
                    onPressed: () {
                      Navigator.of(context).pop();
                      onOpenDiscussion!();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// «Не успеваю»: move the step, hand it to an admitted person, or write in
/// the discussion. Every option is recorded in the plan history.
Future<void> showPlanCantMakeSheet(
  BuildContext context, {
  required PlanCubit cubit,
  required PlanStep step,
  required PlanPeople people,
  VoidCallback? onOpenDiscussion,
}) => showTenturaAdaptiveSheet<void>(
  context: context,
  useRootNavigator: true,
  builder: (ctx) {
    final l10n = L10n.of(ctx)!;
    final tt = ctx.tt;
    final navigator = Navigator.of(ctx);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tt.screenHPadding,
              vertical: tt.rowGap,
            ),
            child: Text(
              '${l10n.planActionCantMake} · ${step.title}',
              style: TenturaText.titleSmall(tt.text),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(l10n.planCantMakeReschedule),
            onTap: () async {
              final moved = await showTenturaAdaptiveSheet<_Reschedule>(
                context: ctx,
                useRootNavigator: true,
                builder: (_) => _RescheduleSheet(step: step),
              );
              if (moved == null) return;
              final ok = await cubit.cantMake(
                stepId: step.id,
                option: PlanCantMakeOption.reschedule,
                newStartAt: moved.startAt,
                newEndAt: moved.endAt,
              );
              if (ok && navigator.mounted) navigator.pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(l10n.planCantMakeHandover),
            onTap: () async {
              final candidates = [
                for (final p in people.admitted)
                  if (p.id != cubit.state.viewerId) p,
              ];
              final pick = await showPlanPersonPicker(
                ctx,
                title: l10n.planHandoverPickerTitle,
                people: candidates,
                emptyText: l10n.planHandoverNobody,
              );
              final to = pick?.userId;
              if (to == null) return;
              final ok = await cubit.cantMake(
                stepId: step.id,
                option: PlanCantMakeOption.handover,
                toUserId: to,
              );
              if (ok && navigator.mounted) navigator.pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: Text(l10n.planCantMakeChat),
            onTap: () async {
              final ok = await cubit.cantMake(
                stepId: step.id,
                option: PlanCantMakeOption.chat,
              );
              if (!ok) return;
              if (navigator.mounted) navigator.pop();
              onOpenDiscussion?.call();
            },
          ),
          SizedBox(height: tt.rowGap),
        ],
      ),
    );
  },
);

typedef _Reschedule = ({DateTime? startAt, DateTime? endAt});

class _RescheduleSheet extends StatefulWidget {
  const _RescheduleSheet({required this.step});

  final PlanStep step;

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  late DateTime? _start = widget.step.startAt;
  late DateTime? _end = widget.step.endAt;

  bool get _valid {
    final s = _start;
    final e = _end;
    if (s == null && e == null) return false;
    return s == null || e == null || !e.isBefore(s);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final s = _start;
    final e = _end;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tt.screenHPadding,
          vertical: tt.rowGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.planCantMakeReschedule,
              style: TenturaText.titleSmall(tt.text),
            ),
            SizedBox(height: tt.rowGap),
            PlanDateTimeField(
              label: l10n.planFieldStart,
              value: s,
              onChanged: (v) => setState(() => _start = v),
            ),
            SizedBox(height: tt.rowGap),
            PlanDateTimeField(
              label: l10n.planFieldEnd,
              value: e,
              fallbackDay: s,
              onChanged: (v) => setState(() => _end = v),
            ),
            if (s == null && e == null)
              TenturaStatusText(
                l10n.planCantMakeNeedTime,
                tone: TenturaTone.warn,
              )
            else if (!_valid)
              TenturaStatusText(
                l10n.planValidationEndBeforeStart,
                tone: TenturaTone.danger,
              ),
            SizedBox(height: tt.rowGap),
            FilledButton(
              onPressed: _valid
                  ? () => Navigator.of(context).pop((startAt: s, endAt: e))
                  : null,
              child: Text(l10n.planActionReschedule),
            ),
          ],
        ),
      ),
    );
  }
}
