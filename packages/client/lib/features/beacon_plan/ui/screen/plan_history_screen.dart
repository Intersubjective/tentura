import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/use_case/beacon_plan_case.dart';
import '../bloc/plan_history_cubit.dart';
import '../util/plan_presenter.dart';

/// Opens the plan history of [plan]'s Request (or of [beaconId] when the
/// caller has no plan at hand, e.g. a chat line). With [focusSeq] the history
/// opens on that revision («История ›» of a chat line).
Future<void> openPlanHistory(
  BuildContext context, {
  required PlanPeople people,
  BeaconPlan? plan,
  String? beaconId,
  int? focusSeq,
  BeaconPlanCase? planCase,
}) {
  final id = plan?.beaconId ?? beaconId ?? '';
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (_) => BlocProvider(
        create: (_) {
          final cubit = PlanHistoryCubit(beaconId: id, planCase: planCase);
          unawaited(cubit.load());
          return cubit;
        },
        child: PlanHistoryScreen(
          plan: plan,
          people: people,
          focusSeq: focusSeq,
        ),
      ),
    ),
  );
}

/// Revisions newest first: who, when, the l10n-rendered changes; tap one to
/// preview it and «Вернуть эту версию».
class PlanHistoryScreen extends StatefulWidget {
  const PlanHistoryScreen({
    required this.people,
    this.plan,
    this.focusSeq,
    super.key,
  });

  final BeaconPlan? plan;
  final PlanPeople people;

  /// Revision to open once the history has loaded.
  final int? focusSeq;

  static Key entryKey(int seq) => Key('plan-history-$seq');
  static const restoreKey = Key('plan-history-restore');

  @override
  State<PlanHistoryScreen> createState() => _PlanHistoryScreenState();
}

class _PlanHistoryScreenState extends State<PlanHistoryScreen> {
  bool _focused = false;

  BeaconPlan? get plan => widget.plan;
  PlanPeople get people => widget.people;

  void _maybeFocus(BuildContext context, PlanHistoryState state) {
    final seq = widget.focusSeq;
    if (_focused || seq == null || state.isLoading || state.items.isEmpty) {
      return;
    }
    _focused = true;
    final index = state.items.indexWhere((e) => e.seq == seq);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openPreview(this.context, seq, index == 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocConsumer<PlanHistoryCubit, PlanHistoryState>(
      listenWhen: (p, c) =>
          p.errorSeq != c.errorSeq ||
          p.restoredSeq != c.restoredSeq ||
          (!_focused && p.items != c.items),
      listener: (context, state) {
        _maybeFocus(context, state);
        if (state.restoredSeq > 0 && state.restoredFromSeq != null) {
          showSnackBar(
            context,
            text: l10n.planHistoryRestoredNotice(state.restoredFromSeq!),
          );
        }
        final error = state.error;
        if (error != null && state.errorSeq > 0) {
          showSnackBar(
            context,
            isError: true,
            text: planErrorText(error, l10n),
          );
        }
      },
      builder: (context, state) {
        final cubit = context.read<PlanHistoryCubit>();
        final named = people.withNames(state.names);
        String nameOf(String? id) => named.nameOf(id, l10n);
        final Widget body;
        if (state.isLoading && state.items.isEmpty) {
          body = const Center(child: CircularProgressIndicator.adaptive());
        } else if (state.loadError != null && state.items.isEmpty) {
          body = TenturaEmptyState(
            icon: Icons.error_outline,
            title: l10n.planErrorLoad,
            actionLabel: l10n.planRetry,
            onAction: () => unawaited(cubit.load()),
          );
        } else if (state.items.isEmpty) {
          body = TenturaEmptyState(
            icon: Icons.history,
            title: l10n.planHistoryEmpty,
          );
        } else {
          body = ListView(
            padding: EdgeInsets.symmetric(vertical: tt.rowGap),
            children: [
              for (final (i, entry) in state.items.indexed)
                InkWell(
                  key: PlanHistoryScreen.entryKey(entry.seq),
                  onTap: () => _openPreview(context, entry.seq, i == 0),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: tt.screenHPadding,
                      vertical: tt.rowGap,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                planRevisionHeadline(
                                  entry: entry,
                                  actorName: nameOf(entry.actorId),
                                  plan: plan,
                                  l10n: l10n,
                                ),
                                style: TenturaText.body(tt.text),
                              ),
                            ),
                            if (i == 0)
                              TenturaStatusText(
                                l10n.planHistoryCurrent,
                                tone: TenturaTone.good,
                              ),
                          ],
                        ),
                        TenturaStatusText(
                          planDayTime(entry.createdAt, l10n.localeName),
                        ),
                        if (entry.comment.trim().isNotEmpty)
                          Text(
                            '«${entry.comment.trim()}»',
                            style: TenturaText.bodySmall(tt.textMuted),
                          ),
                        for (final line in planChangeLines(
                          changes: entry.changes,
                          nameOf: nameOf,
                          l10n: l10n,
                        ))
                          Text(line, style: TenturaText.bodySmall(tt.text)),
                      ],
                    ),
                  ),
                ),
              if (state.nextBeforeSeq != null)
                Center(
                  child: TenturaTextAction(
                    label: l10n.planHistoryLoadMore,
                    onPressed: () => unawaited(cubit.loadMore()),
                  ),
                ),
            ],
          );
        }
        return Scaffold(
          appBar: TenturaTopBar.of(
            context,
            title: Text(l10n.planHistoryTitle),
            progress: state.restoring ? const LinearProgressIndicator() : null,
          ),
          body: body,
        );
      },
    );
  }

  void _openPreview(BuildContext context, int seq, bool isCurrent) {
    final cubit = context.read<PlanHistoryCubit>();
    unawaited(cubit.openPreview(seq));
    unawaited(
      showTenturaAdaptiveSheet<void>(
        context: context,
        useRootNavigator: true,
        builder: (_) => BlocProvider.value(
          value: cubit,
          child: _RevisionPreview(
            seq: seq,
            isCurrent: isCurrent,
            people: people,
          ),
        ),
      ).then((_) => cubit.closePreview()),
    );
  }
}

class _RevisionPreview extends StatelessWidget {
  const _RevisionPreview({
    required this.seq,
    required this.isCurrent,
    required this.people,
  });

  final int seq;
  final bool isCurrent;
  final PlanPeople people;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocBuilder<PlanHistoryCubit, PlanHistoryState>(
      builder: (context, state) {
        final preview = state.preview;
        final named = people.withNames(state.names);
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
                  l10n.planHistoryVersion(seq),
                  style: TenturaText.titleSmall(tt.text),
                ),
              ),
              if (preview == null || preview.seq != seq)
                Padding(
                  padding: tt.cardPadding,
                  child: const Center(
                    child: CircularProgressIndicator.adaptive(),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final s in preview.snapshot.steps)
                        ListTile(
                          dense: true,
                          title: Text(s.title),
                          subtitle: Text(
                            [
                              planStepTimeLabel(
                                startAt: s.startAt,
                                endAt: s.endAt,
                                l10n: l10n,
                              ),
                              named.nameOf(s.assigneeId, l10n),
                            ].join(' · '),
                          ),
                        ),
                    ],
                  ),
                ),
              if (!isCurrent)
                Padding(
                  padding: EdgeInsets.all(tt.screenHPadding),
                  child: FilledButton(
                    key: PlanHistoryScreen.restoreKey,
                    onPressed: preview == null || state.restoring
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            unawaited(
                              context.read<PlanHistoryCubit>().restore(seq),
                            );
                          },
                    child: Text(l10n.planHistoryRestore),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
