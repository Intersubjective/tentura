import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/focus_flash_highlight.dart';

import '../../domain/use_case/beacon_plan_case.dart';
import '../bloc/plan_edit_cubit.dart';
import '../util/plan_presenter.dart';
import '../widget/plan_step_edit_sheet.dart';
import '../widget/plan_step_row.dart';

/// The plan editor: draft steps (reorder, add, edit, delete), an optional
/// comment and «Сохранить». Nothing is visible to others until saved.
///
/// Shown by `BeaconPlanPageView` over a [PlanEditCubit].
class PlanEditScreen extends StatelessWidget {
  const PlanEditScreen({
    required this.people,
    required this.onClose,
    required this.onSaved,
    super.key,
  });

  final PlanPeople people;

  /// Leaves the editor without saving.
  final VoidCallback onClose;

  /// The draft was saved; the host shows the outcome and leaves.
  final ValueChanged<PlanSaveOutcome> onSaved;

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

  /// Maps a [ReorderableListView] move over [items] (headers included) to
  /// step positions: [newIndex] is the slot after the dragged row is removed.
  void _reorder(
    PlanEditCubit cubit,
    List<Object> items,
    int oldIndex,
    int newIndex,
  ) {
    final rest = [...items]..removeAt(oldIndex);
    cubit.reorder(
      items.take(oldIndex).whereType<PlanEditStep>().length,
      rest.take(newIndex).whereType<PlanEditStep>().length,
    );
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

  Future<void> _close(BuildContext context, {required bool isDirty}) async {
    if (!isDirty || await _confirmDiscard(context)) onClose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocListener<PlanEditCubit, PlanEditState>(
      listenWhen: (p, c) => p.conflictSeq != c.conflictSeq,
      listener: (context, state) => showSnackBar(
        context,
        text: planConflictNoticeText(state.conflictSteps, people, l10n),
      ),
      child: _body(context, l10n, tt),
    );
  }

  Widget _body(BuildContext context, L10n l10n, TenturaTokens tt) {
    return BlocConsumer<PlanEditCubit, PlanEditState>(
      listenWhen: (p, c) => p.saved != c.saved || p.errorSeq != c.errorSeq,
      listener: (context, state) {
        final saved = state.saved;
        if (saved != null) {
          onSaved(saved.outcome);
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
        final items = _withDayAdds(buildPlanEditItems(state.steps));
        final atLimit = state.steps.length >= PlanLimits.maxSteps;
        // Not a route of its own: a system back (Android) closes the editor
        // rather than the Request.
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_close(context, isDirty: state.isDirty));
          },
          child: Scaffold(
            appBar: TenturaTopBar.of(
              context,
              title: Text(l10n.planEditTitle),
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () =>
                    unawaited(_close(context, isDirty: state.isDirty)),
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
            body: TenturaContentColumn(
              child: Column(
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
                    child: _MovedStepScroll(
                      builder: (context, scrollController) =>
                          ReorderableListView.builder(
                            scrollController: scrollController,
                            buildDefaultDragHandles: false,
                            itemCount: items.length,
                            onReorderItem: (o, n) =>
                                _reorder(cubit, items, o, n),
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
                                  onPressed: atLimit
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
                              final item = items[i];
                              if (item is _DayAdd) {
                                return Padding(
                                  key: ValueKey('day-add-$i'),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: tt.screenHPadding,
                                  ),
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: TenturaTextAction(
                                      label: l10n.planEditAddStep,
                                      icon: const Icon(Icons.add),
                                      flushStart: true,
                                      onPressed: atLimit
                                          ? null
                                          : () => _editStep(
                                              context,
                                              cubit.newStep(
                                                startAt: item.day.lastAt,
                                              ),
                                              isNew: true,
                                            ),
                                    ),
                                  ),
                                );
                              }
                              if (item is! PlanEditStep) {
                                return PlanDayHeader(
                                  key: ValueKey('day-$i'),
                                  day: (item as PlanListDay).day,
                                );
                              }
                              final step = item.step;
                              final problem = validatePlanStep(step);
                              final untimed =
                                  step.startAt == null && step.endAt == null;
                              final moved = step.id == state.movedStepId;
                              final tile = ListTile(
                                titleAlignment: ListTileTitleAlignment.top,
                                leading: untimed
                                    ? ReorderableDragStartListener(
                                        index: i,
                                        child: Semantics(
                                          container: true,
                                          label: l10n.planEditReorderHandle,
                                          child: Icon(
                                            Icons.drag_handle,
                                            size: tt.avatarTinySize,
                                          ),
                                        ),
                                      )
                                    : null,
                                title: Text(
                                  step.title.trim().isEmpty ? '—' : step.title,
                                  style: TenturaText.body(
                                    problem == null ? tt.text : tt.danger,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    planStepWhenLabel(
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
                                onTap: () =>
                                    _editStep(context, step, isNew: false),
                              );
                              // A new key per move re-runs the scroll and flash
                              // when the same step moves again.
                              return FocusFlashHighlight(
                                key: ValueKey(
                                  moved
                                      ? '${step.id}#${state.movedSeq}'
                                      : step.id,
                                ),
                                active: moved,
                                // The flash paints a background: give the tile its own
                                // Material so its ink stays visible.
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: tile,
                                ),
                              );
                            },
                          ),
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
          ),
        );
      },
    );
  }
}

/// The add action closing a day group; continues from the day's latest time.
class _DayAdd {
  const _DayAdd(this.day);

  final PlanEditDay day;
}

/// [items] with a [_DayAdd] after the last step of each day.
List<Object> _withDayAdds(List<PlanListItem> items) {
  final rows = <Object>[];
  PlanEditDay? open;
  for (final item in items) {
    if (item is PlanEditDay) {
      if (open != null) rows.add(_DayAdd(open));
      open = item;
    }
    rows.add(item);
  }
  if (open != null) rows.add(_DayAdd(open));
  return rows;
}

/// Hands [builder] a scroll controller and, when the cubit reports a moved
/// step, jumps near its row so the lazy list builds it (the row itself then
/// scrolls precisely into view and flashes).
class _MovedStepScroll extends StatefulWidget {
  const _MovedStepScroll({required this.builder});

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<_MovedStepScroll> createState() => _MovedStepScrollState();
}

class _MovedStepScrollState extends State<_MovedStepScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onMoved(BuildContext context, PlanEditState state) {
    if (!_controller.hasClients) return;
    final rows = _withDayAdds(buildPlanEditItems(state.steps));
    final at = rows.indexWhere(
      (r) => r is PlanEditStep && r.step.id == state.movedStepId,
    );
    if (at < 0) return;
    final position = _controller.position;
    final extent = position.maxScrollExtent + position.viewportDimension;
    _controller.jumpTo(
      (extent * at / rows.length).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<PlanEditCubit, PlanEditState>(
        listenWhen: (p, c) => p.movedSeq != c.movedSeq,
        listener: _onMoved,
        child: widget.builder(context, _controller),
      );
}
