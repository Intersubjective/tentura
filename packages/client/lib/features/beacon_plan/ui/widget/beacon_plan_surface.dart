import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/use_case/beacon_plan_case.dart';
import '../bloc/plan_cubit.dart';
import '../screen/plan_edit_screen.dart';
import '../screen/plan_history_screen.dart';
import '../util/plan_presenter.dart';
import 'plan_people_matrix.dart';
import 'plan_step_row.dart';
import 'plan_step_sheet.dart';

/// The Plan tab of a Request («либретто», #220): who does what and when,
/// with the «now» line, filters, the viewer's pending changes and the way
/// into the editor and the history.
class BeaconPlanSurface extends StatelessWidget {
  const BeaconPlanSurface({
    required this.beaconId,
    required this.viewerId,
    required this.admitted,
    this.onOpenDiscussion,
    this.planCase,
    this.cubit,
    super.key,
  });

  final String beaconId;
  final String viewerId;

  /// People a step may be assigned to (author, stewards, admitted helpers).
  final List<Profile> admitted;

  final VoidCallback? onOpenDiscussion;

  /// Test seam; defaults to the DI singleton.
  final BeaconPlanCase? planCase;

  /// The Request's shared plan cubit (also feeding the HUD); when set, the
  /// tab reuses it instead of fetching again.
  final PlanCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final shared = cubit;
    if (shared != null) {
      return BlocProvider.value(
        value: shared,
        child: BeaconPlanView(
          admitted: admitted,
          onOpenDiscussion: onOpenDiscussion,
          planCase: planCase,
        ),
      );
    }
    return _ownCubit();
  }

  Widget _ownCubit() => BlocProvider(
    create: (_) {
      final cubit = PlanCubit(
        beaconId: beaconId,
        viewerId: viewerId,
        planCase: planCase ?? GetIt.I<BeaconPlanCase>(),
      );
      unawaited(cubit.load());
      return cubit;
    },
    child: BeaconPlanView(
      admitted: admitted,
      onOpenDiscussion: onOpenDiscussion,
      planCase: planCase,
    ),
  );
}

/// [BeaconPlanSurface] body over an existing [PlanCubit].
class BeaconPlanView extends StatefulWidget {
  const BeaconPlanView({
    required this.admitted,
    this.onOpenDiscussion,
    this.planCase,
    this.clock,
    super.key,
  });

  final List<Profile> admitted;
  final VoidCallback? onOpenDiscussion;
  final BeaconPlanCase? planCase;

  /// Test seam for «now».
  final DateTime Function()? clock;

  static const emptyKey = Key('plan-empty');
  static const editKey = Key('plan-edit');
  static const historyKey = Key('plan-history');
  static const mineKey = Key('plan-filter-mine');
  static const personFilterKey = Key('plan-filter-person');
  static const ackKey = Key('plan-ack');
  static const viewListKey = Key('plan-view-list');
  static const viewPeopleKey = Key('plan-view-people');

  @override
  State<BeaconPlanView> createState() => _BeaconPlanViewState();
}

class _BeaconPlanViewState extends State<BeaconPlanView> {
  Timer? _ticker;

  /// «По людям» chosen (only offered on panels ≥ [kPlanMatrixMinWidth]).
  bool _matrix = false;
  late DateTime _now = _clock();

  DateTime _clock() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // Moves the «now» line and the overdue marks; no data is refetched.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = _clock());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  PlanPeople _people(BeaconPlan? plan) => PlanPeople(
    admitted: widget.admitted,
    names: plan?.names,
  );

  Future<void> _openEditor(BeaconPlan plan) async {
    final cubit = context.read<PlanCubit>();
    final l10n = L10n.of(context)!;
    final people = _people(plan);
    final outcome = await openPlanEditor(
      context,
      plan: plan,
      people: people,
      planCase: widget.planCase,
    );
    if (!mounted || outcome == null) return;
    unawaited(cubit.refresh());
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
  }

  Future<void> _openHistory(BeaconPlan plan) async {
    final cubit = context.read<PlanCubit>();
    await openPlanHistory(
      context,
      plan: plan,
      people: _people(plan),
      planCase: widget.planCase,
    );
    if (mounted) unawaited(cubit.refresh());
  }

  void _openStep(BeaconPlan plan, String stepId) => unawaited(
    showPlanStepSheet(
      context,
      cubit: context.read<PlanCubit>(),
      stepId: stepId,
      people: _people(plan),
      onEdit: plan.editable ? () => unawaited(_openEditor(plan)) : null,
      onOpenDiscussion: widget.onOpenDiscussion,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocConsumer<PlanCubit, PlanState>(
      listenWhen: (p, c) => p.noticeSeq != c.noticeSeq,
      listener: (context, state) {
        final notice = state.notice;
        if (notice is PlanNoticeError) {
          showSnackBar(
            context,
            isError: true,
            text: notice.tickFailed
                ? l10n.planErrorTickFailed
                : planErrorText(notice.error, l10n),
          );
        }
      },
      builder: (context, state) {
        final plan = state.plan;
        if (plan == null) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          return TenturaEmptyState(
            icon: Icons.error_outline,
            title: l10n.planErrorLoad,
            body: state.loadError == null
                ? null
                : planErrorText(state.loadError!, l10n),
            actionLabel: l10n.planRetry,
            onAction: () => unawaited(context.read<PlanCubit>().load()),
          );
        }
        if (plan.isEmpty) {
          return _PlanEmpty(
            plan: plan,
            onCreate: plan.editable ? () => _openEditor(plan) : null,
            onHistory: () => _openHistory(plan),
          );
        }
        final people = _people(plan);
        final items = buildPlanListItems(
          steps: plan.steps,
          filter: state.filter,
          viewerId: state.viewerId,
          now: _now,
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            // The matrix needs the Plan panel's own width (in the split
            // it is the side pane), not the window's.
            final canMatrix = constraints.maxWidth >= kPlanMatrixMinWidth;
            final matrix = canMatrix && _matrix;
            return RefreshIndicator.adaptive(
              onRefresh: () => context.read<PlanCubit>().refresh(),
              child: ListView(
                padding: EdgeInsets.only(bottom: tt.sectionGap * 2),
                children: [
                  _PlanHeader(plan: plan, now: _now, people: people),
                  _PlanControls(
                    plan: plan,
                    filter: state.filter,
                    people: people,
                    onHistory: () => _openHistory(plan),
                    onEdit: plan.editable ? () => _openEditor(plan) : null,
                  ),
                  if (canMatrix)
                    _PlanViewToggle(
                      matrix: matrix,
                      onChanged: (v) => setState(() => _matrix = v),
                    ),
                  if (plan.hasViewerPending)
                    _PlanPendingCard(plan: plan, people: people),
                  if (matrix)
                    Padding(
                      padding: EdgeInsets.only(top: tt.rowGap),
                      child: PlanPeopleMatrix(
                        plan: plan,
                        people: people,
                        now: _now,
                        onOpenStep: (id) => _openStep(plan, id),
                      ),
                    )
                  else
                    ..._listRows(context, state, plan, people, items),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _listRows(
    BuildContext context,
    PlanState state,
    BeaconPlan plan,
    PlanPeople people,
    List<PlanListItem> items,
  ) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return [
      if (items.isEmpty)
        Padding(
          padding: tt.cardPadding,
          child: Text(
            l10n.planFilterEmpty,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        ),
      for (final item in items)
        switch (item) {
          PlanListDay(:final day) => PlanDayHeader(day: day),
          PlanListNow(:final now) => PlanNowLine(now: now),
          PlanListStep(:final step, :final dimmed) => PlanStepRow(
            step: step,
            people: people,
            now: _now,
            tickable: plan.tickable,
            showAckState: plan.editable,
            dimmed: dimmed,
            busy: state.busyStepIds.contains(step.id),
            onToggleDone: () => unawaited(
              context.read<PlanCubit>().toggleDone(step.id),
            ),
            onTap: () => _openStep(plan, step.id),
          ),
        },
    ];
  }
}

/// «Список / По людям» (plan §5.4); shown only on panels ≥ 600.
class _PlanViewToggle extends StatelessWidget {
  const _PlanViewToggle({required this.matrix, required this.onChanged});

  final bool matrix;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
      ).copyWith(top: tt.tightGap),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TenturaCommandButton(
            key: BeaconPlanView.viewListKey,
            label: l10n.planViewList,
            selected: !matrix,
            onPressed: () => onChanged(false),
          ),
          SizedBox(width: tt.rowGap),
          TenturaCommandButton(
            key: BeaconPlanView.viewPeopleKey,
            label: l10n.planViewPeople,
            selected: matrix,
            onPressed: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _PlanHeader extends StatelessWidget {
  const _PlanHeader({
    required this.plan,
    required this.now,
    required this.people,
  });

  final BeaconPlan plan;
  final DateTime now;
  final PlanPeople people;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final editorId = plan.lastEditedById;
    final editedAt = plan.lastEditedAt;
    final title = editorId != null && editedAt != null
        ? l10n.planHeader(
            plan.doneCount,
            plan.steps.length,
            people.nameOf(editorId, l10n),
            compactRelativeTimeAgo(when: editedAt, now: now, l10n: l10n),
          )
        : l10n.planHeaderShort(plan.doneCount, plan.steps.length);
    final overdue = plan.overdueCount(now);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.sectionGap,
        tt.screenHPadding,
        tt.tightGap,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: TenturaText.typeLabel(tt.textMuted)),
          ),
          if (overdue > 0)
            Semantics(
              label: l10n.planHeaderOverdueSemantics(overdue),
              excludeSemantics: true,
              child: TenturaStatusText(
                l10n.planHeaderOverdue(overdue),
                tone: TenturaTone.danger,
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanControls extends StatelessWidget {
  const _PlanControls({
    required this.plan,
    required this.filter,
    required this.people,
    required this.onHistory,
    this.onEdit,
  });

  final BeaconPlan plan;
  final PlanFilter filter;
  final PlanPeople people;
  final VoidCallback onHistory;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final cubit = context.read<PlanCubit>();
    final assigneeIds = <String>{
      for (final s in plan.steps)
        if (s.assigneeId != null) s.assigneeId!,
    }.toList();
    final hasUnassigned = plan.steps.any((s) => s.assigneeId == null);
    final personLabel = switch (filter.kind) {
      PlanFilterKind.person => people.nameOf(filter.personId, l10n),
      PlanFilterKind.unassigned => l10n.planFilterUnassigned,
      _ => l10n.planFilterAll,
    };
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
      child: Row(
        children: [
          PopupMenuButton<PlanFilter>(
            key: BeaconPlanView.personFilterKey,
            tooltip: l10n.planFilterAll,
            onSelected: cubit.setFilter,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: const PlanFilter.all(),
                child: Text(l10n.planFilterAll),
              ),
              for (final id in assigneeIds)
                PopupMenuItem(
                  value: PlanFilter.person(id),
                  child: Text(people.nameOf(id, l10n)),
                ),
              if (hasUnassigned)
                PopupMenuItem(
                  value: const PlanFilter.unassigned(),
                  child: Text(l10n.planFilterUnassigned),
                ),
            ],
            child: IgnorePointer(
              child: TenturaCommandButton(
                label: '$personLabel ▾',
                selected:
                    filter.kind == PlanFilterKind.person ||
                    filter.kind == PlanFilterKind.unassigned,
                onPressed: () {},
              ),
            ),
          ),
          SizedBox(width: tt.rowGap),
          TenturaCommandButton(
            key: BeaconPlanView.mineKey,
            label: l10n.planFilterMine,
            selected: filter.kind == PlanFilterKind.mine,
            onPressed: () => cubit.setFilter(
              filter.kind == PlanFilterKind.mine
                  ? const PlanFilter.all()
                  : const PlanFilter.mine(),
            ),
          ),
          const Spacer(),
          TenturaTextAction(
            key: BeaconPlanView.historyKey,
            label: l10n.planHistoryAction,
            onPressed: onHistory,
          ),
          if (onEdit != null)
            IconButton(
              key: BeaconPlanView.editKey,
              tooltip: l10n.planEditTitle,
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}

class _PlanPendingCard extends StatelessWidget {
  const _PlanPendingCard({required this.plan, required this.people});

  final BeaconPlan plan;
  final PlanPeople people;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final pending = plan.viewerPending!;
    final viewerId = context.read<PlanCubit>().state.viewerId;
    final actors = [
      for (final id in pending.actorIds) people.nameOf(id, l10n),
    ].join(', ');
    final editedAt = plan.lastEditedAt;
    final when = editedAt == null
        ? ''
        : compactRelativeTimeAgo(
            when: editedAt,
            now: DateTime.now(),
            l10n: l10n,
          );
    final lines = planPendingLines(
      pending: pending,
      viewerId: viewerId,
      nameOf: (id) => people.nameOf(id, l10n),
      actorName: actors,
      when: when,
      l10n: l10n,
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.rowGap,
      ),
      child: TenturaTechCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.planPendingTitle,
              style: TenturaText.typeLabel(tt.info),
            ),
            SizedBox(height: tt.tightGap),
            for (final line in lines)
              Padding(
                padding: EdgeInsets.only(bottom: tt.tightGap),
                child: Text(line, style: TenturaText.body(tt.text)),
              ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                key: BeaconPlanView.ackKey,
                onPressed: () => unawaited(context.read<PlanCubit>().ack()),
                child: Text(l10n.planActionAck),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanEmpty extends StatelessWidget {
  const _PlanEmpty({
    required this.plan,
    required this.onHistory,
    this.onCreate,
  });

  final BeaconPlan plan;
  final VoidCallback? onCreate;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Column(
      key: BeaconPlanView.emptyKey,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: TenturaEmptyState(
            icon: Icons.checklist_outlined,
            title: l10n.planEmptyTitle,
            body: l10n.planEmptyBody,
            actionLabel: onCreate == null ? null : l10n.planEmptyCta,
            onAction: onCreate,
          ),
        ),
        if (plan.hasHistory)
          TenturaTextAction(
            label: l10n.planEmptyHistoryLink,
            onPressed: onHistory,
          ),
      ],
    );
  }
}
