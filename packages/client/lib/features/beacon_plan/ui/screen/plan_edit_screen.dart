import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/use_case/beacon_plan_case.dart';
import '../bloc/plan_edit_cubit.dart';
import '../util/plan_presenter.dart';
import '../widget/plan_conflict_resolver.dart';
import '../widget/plan_step_edit_sheet.dart';

/// Opens the plan editor over [plan]. Resolves to the save outcome, or null
/// when the user left without saving.
Future<PlanSaveOutcome?> openPlanEditor(
  BuildContext context, {
  required BeaconPlan plan,
  required PlanPeople people,
  BeaconPlanCase? planCase,
}) => Navigator.of(context, rootNavigator: true).push<PlanSaveOutcome>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => BlocProvider(
      create: (_) => PlanEditCubit(plan: plan, planCase: planCase),
      child: PlanEditScreen(people: people),
    ),
  ),
);

/// The plan editor: draft steps (reorder, add, edit, delete), an optional
/// comment and «Сохранить». Nothing is visible to others until saved.
class PlanEditScreen extends StatelessWidget {
  const PlanEditScreen({required this.people, super.key});

  final PlanPeople people;

  static const saveKey = Key('plan-edit-save');
  static const addKey = Key('plan-edit-add');

  String? _validationText(PlanDraftError? e, L10n l10n) => switch (e) {
    null => null,
    PlanDraftError.titleRequired => l10n.planValidationTitleRequired,
    PlanDraftError.titleTooLong => l10n.planValidationTooLong(
      PlanLimits.maxTitleLength,
    ),
    PlanDraftError.descriptionTooLong => l10n.planValidationTooLong(
      PlanLimits.maxDescriptionLength,
    ),
    PlanDraftError.endBeforeStart => l10n.planValidationEndBeforeStart,
    PlanDraftError.tooManySteps => l10n.planValidationTooManySteps,
    PlanDraftError.commentTooLong => l10n.planValidationTooLong(
      PlanLimits.maxCommentLength,
    ),
  };

  Future<void> _editStep(
    BuildContext context,
    PlanStepSnapshot step, {
    required bool isNew,
  }) async {
    final cubit = context.read<PlanEditCubit>();
    final edited = await showPlanStepEditSheet(
      context,
      step: step,
      isNew: isNew,
      people: people.admitted,
    );
    if (edited != null) cubit.putStep(edited);
  }

  Future<bool> _confirmDiscard(BuildContext context) async {
    final l10n = L10n.of(context)!;
    final ok = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.planDiscardTitle,
      content: l10n.planDiscardBody,
      confirmLabel: l10n.planDiscardConfirm,
      cancelLabel: l10n.planDiscardKeep,
      emphasizeCancel: true,
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocConsumer<PlanEditCubit, PlanEditState>(
      listenWhen: (p, c) =>
          p.saved != c.saved ||
          p.errorSeq != c.errorSeq ||
          (p.conflict == null && c.conflict != null),
      listener: (context, state) {
        final saved = state.saved;
        if (saved != null) {
          Navigator.of(context).pop(saved.outcome);
          return;
        }
        final conflict = state.conflict;
        if (conflict != null) {
          unawaited(
            showPlanConflictResolver(
              context,
              cubit: context.read<PlanEditCubit>(),
              people: people,
            ),
          );
          return;
        }
        final error = state.error;
        if (error != null) {
          showSnackBar(
            context,
            isError: true,
            text: planErrorText(error, l10n),
          );
        }
      },
      builder: (context, state) {
        final cubit = context.read<PlanEditCubit>();
        final validation = _validationText(state.validationError, l10n);
        return PopScope(
          canPop: !state.isDirty || state.saved != null,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final navigator = Navigator.of(context);
            if (await _confirmDiscard(context)) navigator.pop();
          },
          child: Scaffold(
            appBar: TenturaTopBar.of(
              context,
              title: Text(l10n.planEditTitle),
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              actions: [
                Padding(
                  padding: EdgeInsets.only(right: tt.screenHPadding),
                  child: FilledButton(
                    key: saveKey,
                    onPressed:
                        state.isSaving || validation != null || !state.isDirty
                        ? null
                        : () => unawaited(cubit.save()),
                    child: Text(l10n.planEditSave),
                  ),
                ),
              ],
              progress: state.isSaving ? const LinearProgressIndicator() : null,
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (validation != null)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: tt.screenHPadding,
                      vertical: tt.rowGap,
                    ),
                    child: TenturaStatusText(
                      validation,
                      tone: TenturaTone.danger,
                      maxLines: null,
                    ),
                  ),
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: state.steps.length,
                    onReorderItem: cubit.reorder,
                    footer: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: tt.screenHPadding,
                        vertical: tt.rowGap,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TenturaTextAction(
                          key: addKey,
                          label: l10n.planEditAddStep,
                          icon: const Icon(Icons.add),
                          flushStart: true,
                          onPressed: state.steps.length >= PlanLimits.maxSteps
                              ? null
                              : () => _editStep(
                                  context,
                                  cubit.newStep(),
                                  isNew: true,
                                ),
                        ),
                      ),
                    ),
                    itemBuilder: (context, i) {
                      final step = state.steps[i];
                      final problem = validatePlanStep(step);
                      return ListTile(
                        key: ValueKey(step.id),
                        leading: ReorderableDragStartListener(
                          index: i,
                          child: Semantics(
                            label: l10n.planEditReorderHandle,
                            child: const Icon(Icons.drag_handle),
                          ),
                        ),
                        title: Text(
                          step.title.trim().isEmpty ? '—' : step.title,
                          style: TenturaText.body(
                            problem == null ? tt.text : tt.danger,
                          ),
                        ),
                        subtitle: Text(
                          [
                            planStepTimeLabel(
                              startAt: step.startAt,
                              endAt: step.endAt,
                              l10n: l10n,
                            ),
                            people.nameOf(step.assigneeId, l10n),
                          ].join(' · '),
                          style: TenturaText.bodySmall(tt.textMuted),
                        ),
                        trailing: IconButton(
                          tooltip: l10n.planEditDeleteStep,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => cubit.removeStep(step.id),
                        ),
                        onTap: () => _editStep(context, step, isNew: false),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.all(tt.screenHPadding),
                    child: TextFormField(
                      initialValue: state.comment,
                      maxLength: PlanLimits.maxCommentLength,
                      decoration: InputDecoration(
                        labelText: l10n.planEditComment,
                      ),
                      onChanged: cubit.setComment,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
