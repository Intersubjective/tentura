import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/use_case/beacon_plan_case.dart';
import '../bloc/plan_cubit.dart';
import '../bloc/plan_edit_cubit.dart';
import '../bloc/plan_history_cubit.dart';
import '../screen/plan_edit_screen.dart';
import '../screen/plan_history_screen.dart';
import '../util/plan_presenter.dart';

/// A page that opens over the Plan tab of a Request (#220). It lives in the
/// Request's URL (`tab=plan&page=…`), so the browser back gesture closes it
/// and returns to the plan instead of leaving the Request.
enum BeaconPlanPage {
  history,
  edit;

  /// The [kQueryPlanPage] value.
  String get queryValue => switch (this) {
    history => kPlanPageHistory,
    edit => kPlanPageEdit,
  };

  static BeaconPlanPage? tryParse(String? value) => switch (value?.trim()) {
    kPlanPageHistory => history,
    kPlanPageEdit => edit,
    _ => null,
  };
}

/// Opens a [BeaconPlanPage] of the Request on screen; provided by the
/// Request view.
class BeaconPlanPageScope extends InheritedWidget {
  const BeaconPlanPageScope({
    required this.open,
    required super.child,
    super.key,
  });

  /// [revision]: with [BeaconPlanPage.history], the revision to open.
  final void Function(BeaconPlanPage page, {int? revision}) open;

  static BeaconPlanPageScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BeaconPlanPageScope>();

  @override
  bool updateShouldNotify(BeaconPlanPageScope oldWidget) =>
      open != oldWidget.open;
}

/// The open [BeaconPlanPage] over the Request's [PlanCubit]. The host decides
/// where it goes: the whole screen on a phone, the plan pane beside the chat
/// on a wide window.
class BeaconPlanPageView extends StatefulWidget {
  const BeaconPlanPageView({
    required this.page,
    required this.beaconId,
    required this.admitted,
    required this.onClose,
    this.revision,
    this.planCase,
    super.key,
  });

  final BeaconPlanPage page;
  final String beaconId;

  /// People a step may be assigned to (author, stewards, admitted helpers).
  final List<Profile> admitted;

  /// Leaves the page (back to the Plan tab).
  final VoidCallback onClose;

  /// With [BeaconPlanPage.history]: the revision to open once loaded.
  final int? revision;

  /// Test seam; defaults to the DI singleton.
  final BeaconPlanCase? planCase;

  @override
  State<BeaconPlanPageView> createState() => _BeaconPlanPageViewState();
}

class _BeaconPlanPageViewState extends State<BeaconPlanPageView> {
  PlanCubit? _planCubit;
  bool _closeScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _planCubit = context.read<PlanCubit?>();
  }

  @override
  void dispose() {
    // A restore in the history changes the plan.
    final cubit = _planCubit;
    if (widget.page == BeaconPlanPage.history &&
        cubit != null &&
        !cubit.isClosed) {
      unawaited(cubit.refresh());
    }
    super.dispose();
  }

  PlanPeople _people(BeaconPlan? plan) =>
      PlanPeople(admitted: widget.admitted, names: plan?.names);

  void _onSaved(PlanSaveOutcome outcome, PlanPeople people) {
    final cubit = _planCubit;
    if (cubit != null) unawaited(cubit.refresh());
    final l10n = L10n.of(context)!;
    if (outcome.kind == PlanSaveOutcomeKind.merged) {
      final names = [
        for (final id in outcome.theirActorIds) people.nameOf(id, l10n),
      ];
      showSnackBar(
        context,
        text: names.isEmpty
            ? l10n.planMergedAnon(outcome.theirStepIds.length)
            : l10n.planMerged(outcome.theirStepIds.length, names.join(', ')),
      );
    } else if (outcome.kind == PlanSaveOutcomeKind.applied) {
      showSnackBar(context, text: l10n.planSaved);
    }
    _leaveEditor();
  }

  /// Leaving the editor on purpose (saved or discarded) drops its draft; a
  /// page that merely goes away (browser Back) leaves it for the next open.
  void _leaveEditor() {
    _planCubit?.releaseEditor();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = _planCubit;
    return switch (widget.page) {
      BeaconPlanPage.history => BlocProvider(
        key: ValueKey('plan-history-${widget.beaconId}'),
        create: (_) {
          final history = PlanHistoryCubit(
            beaconId: widget.beaconId,
            planCase: widget.planCase,
          );
          unawaited(history.load());
          return history;
        },
        child: cubit == null
            ? _history(null)
            : BlocSelector<PlanCubit, PlanState, BeaconPlan?>(
                bloc: cubit,
                selector: (state) => state.plan,
                builder: (context, plan) => _history(plan),
              ),
      ),
      BeaconPlanPage.edit =>
        cubit == null
            ? _closing()
            : BlocBuilder<PlanCubit, PlanState>(
                bloc: cubit,
                // The draft starts from the plan once; later refreshes reach
                // the editor as a merge on save, not as a reset.
                buildWhen: (p, c) =>
                    p.plan == null || p.isLoading != c.isLoading,
                builder: (context, state) {
                  final plan = state.plan;
                  if (plan == null) {
                    return state.isLoading ? _loading() : _closing();
                  }
                  if (!plan.editable) return _closing();
                  final people = _people(plan);
                  return BlocProvider.value(
                    key: ValueKey('plan-edit-${widget.beaconId}'),
                    value: cubit.editor(
                      () =>
                          PlanEditCubit(plan: plan, planCase: widget.planCase),
                    ),
                    child: PlanEditScreen(
                      people: people,
                      onClose: _leaveEditor,
                      onSaved: (outcome) => _onSaved(outcome, people),
                    ),
                  );
                },
              ),
    };
  }

  Widget _history(BeaconPlan? plan) => PlanHistoryScreen(
    plan: plan,
    people: _people(plan),
    focusSeq: widget.revision,
    onClose: widget.onClose,
  );

  Widget _loading() => const Scaffold(
    body: Center(child: CircularProgressIndicator.adaptive()),
  );

  /// Nothing to edit (no plan, or not the viewer's to edit): back to the plan.
  Widget _closing() {
    if (!_closeScheduled) {
      _closeScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onClose();
      });
    }
    return _loading();
  }
}
