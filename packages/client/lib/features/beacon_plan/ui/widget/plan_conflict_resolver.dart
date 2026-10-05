import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/plan_conflict.dart';
import '../bloc/plan_edit_cubit.dart';
import '../util/plan_presenter.dart';

/// After a save conflict (1330): for each step both sides changed, the user
/// keeps «Моя версия» or takes «Их версия»; then the draft is rebased onto
/// the current plan and saved again. Dismissing keeps the draft.
Future<void> showPlanConflictResolver(
  BuildContext context, {
  required PlanEditCubit cubit,
  required PlanPeople people,
}) async {
  final resolved = await showTenturaAdaptiveSheet<bool>(
    context: context,
    useRootNavigator: true,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: PlanConflictResolver(people: people),
    ),
  );
  if (resolved ?? false) {
    unawaited(cubit.resolveConflict());
  } else {
    cubit.dismissConflict();
  }
}

class PlanConflictResolver extends StatelessWidget {
  const PlanConflictResolver({required this.people, super.key});

  final PlanPeople people;

  static const saveKey = Key('plan-conflict-save');

  static Key choiceKey(String stepId, PlanConflictChoice choice) =>
      Key('plan-conflict-$stepId-${choice.name}');

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocBuilder<PlanEditCubit, PlanEditState>(
      builder: (context, state) {
        final conflict = state.conflict;
        if (conflict == null) return const SizedBox.shrink();
        final mine = conflict.mine.byId;
        final theirs = conflict.theirs.byId;
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.planConflictTitle,
                      style: TenturaText.titleSmall(tt.text),
                    ),
                    SizedBox(height: tt.tightGap),
                    Text(
                      l10n.planConflictBody,
                      style: TenturaText.bodySmall(tt.textMuted),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final id in conflict.stepIds)
                      _ConflictStep(
                        stepId: id,
                        mine: mine[id],
                        theirs: theirs[id],
                        choice: state.choices[id] ?? PlanConflictChoice.mine,
                        people: people,
                        onChoose: (c) =>
                            context.read<PlanEditCubit>().choose(id, c),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(tt.screenHPadding),
                child: FilledButton(
                  key: saveKey,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.planEditSave),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConflictStep extends StatelessWidget {
  const _ConflictStep({
    required this.stepId,
    required this.mine,
    required this.theirs,
    required this.choice,
    required this.people,
    required this.onChoose,
  });

  final String stepId;
  final PlanStepSnapshot? mine;
  final PlanStepSnapshot? theirs;
  final PlanConflictChoice choice;
  final PlanPeople people;
  final ValueChanged<PlanConflictChoice> onChoose;

  String _describe(PlanStepSnapshot? s, L10n l10n) {
    if (s == null) return l10n.planConflictStepRemoved;
    return [
      s.title,
      planStepTimeLabel(startAt: s.startAt, endAt: s.endAt, l10n: l10n),
      people.nameOf(s.assigneeId, l10n),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tt.tightGap),
      child: RadioGroup<PlanConflictChoice>(
        groupValue: choice,
        onChanged: (c) {
          if (c != null) onChoose(c);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
              child: Text(
                (mine ?? theirs)?.title ?? stepId,
                style: TenturaText.body(tt.text),
              ),
            ),
            RadioListTile<PlanConflictChoice>(
              key: PlanConflictResolver.choiceKey(
                stepId,
                PlanConflictChoice.mine,
              ),
              value: PlanConflictChoice.mine,
              title: Text(l10n.planConflictMine),
              subtitle: Text(_describe(mine, l10n)),
            ),
            RadioListTile<PlanConflictChoice>(
              key: PlanConflictResolver.choiceKey(
                stepId,
                PlanConflictChoice.theirs,
              ),
              value: PlanConflictChoice.theirs,
              title: Text(l10n.planConflictTheirs),
              subtitle: Text(_describe(theirs, l10n)),
            ),
          ],
        ),
      ),
    );
  }
}
