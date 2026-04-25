import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_status_strip.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_status_line.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';
import 'package:tentura/features/home/ui/widget/new_stuff_dot.dart';
import 'package:tentura/features/home/ui/widget/new_stuff_reason_l10n.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

String _formatDateTimeActivityLine(DateTime d) =>
    '${dateFormatYMD(d)} ${timeFormatHm(d)}';

String? _myWorkActivityWhenLine(
  L10n l10n,
  MyWorkCardViewModel vm,
  MyWorkCardHighlightKind highlight,
) {
  final b = vm.beacon;
  if (highlight == MyWorkCardHighlightKind.newBeacon) {
    // Creating a beacon does not count as an "update" for the cards.
    return null;
  }
  if (highlight == MyWorkCardHighlightKind.none && !beaconHasRealUpdate(b)) {
    return null;
  }
  final at = highlight == MyWorkCardHighlightKind.none
      ? b.updatedAt
      : DateTime.fromMillisecondsSinceEpoch(vm.newStuffActivityEpochMs);
  return l10n.myWorkUpdatedLine(_formatDateTimeActivityLine(at));
}

Widget _myWorkFooterActivityBlock({
  required BuildContext context,
  required MyWorkCardHighlightKind highlight,
  required List<String> reasonLabels,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final style = theme.textTheme.labelSmall?.copyWith(color: scheme.outline);
  final showNew = highlight != MyWorkCardHighlightKind.none;
  if (!showNew && reasonLabels.isEmpty) {
    return const SizedBox.shrink();
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showNew) _myWorkNewStuffDot(context, highlight) else const SizedBox.shrink(),
          Expanded(
            child: reasonLabels.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in reasonLabels)
                        Text(
                          line,
                          style: style,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ],
  );
}

Widget _myWorkNewStuffDot(BuildContext context, MyWorkCardHighlightKind kind) {
  if (kind == MyWorkCardHighlightKind.none) {
    return const SizedBox.shrink();
  }
  return const NewStuffDot(padding: EdgeInsets.only(right: 8, top: 2));
}

class MyWorkCardRouter extends StatelessWidget {
  const MyWorkCardRouter({required this.vm, super.key});

  final MyWorkCardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocBuilder<NewStuffCubit, NewStuffState>(
      builder: (context, _) {
        final b = vm.beacon;
        final seen = context.read<NewStuffCubit>().state.myWorkLastSeenMs;
        final highlight = context.read<NewStuffCubit>().myWorkCardHighlight(
              createdAt: b.createdAt,
              activityEpochMs: vm.newStuffActivityEpochMs,
            );
        final reasonLabels =
            l10nMyWorkNewStuffReasons(l10n, vm.newStuffReasons(seen));
        final activityWhenLine = _myWorkActivityWhenLine(l10n, vm, highlight);
        return switch (vm.kind) {
          MyWorkCardKind.authoredDraft => _DraftAuthoredCard(
              vm: vm,
              highlight: highlight,
              newStuffReasonLabels: reasonLabels,
              activityWhenLine: activityWhenLine,
            ),
          MyWorkCardKind.authoredActive => _AuthoredActiveCard(
              vm: vm,
              highlight: highlight,
              newStuffReasonLabels: reasonLabels,
              activityWhenLine: activityWhenLine,
            ),
          MyWorkCardKind.committedActive => _CommittedActiveCard(
              vm: vm,
              highlight: highlight,
              newStuffReasonLabels: reasonLabels,
              activityWhenLine: activityWhenLine,
            ),
          MyWorkCardKind.authoredClosed => _ClosedAuthoredCard(
              vm: vm,
              highlight: highlight,
              newStuffReasonLabels: reasonLabels,
              activityWhenLine: activityWhenLine,
            ),
          MyWorkCardKind.committedClosed => _ClosedCommittedCard(
              vm: vm,
              highlight: highlight,
              newStuffReasonLabels: reasonLabels,
              activityWhenLine: activityWhenLine,
            ),
        };
      },
    );
  }
}

void _openBeacon(BuildContext context, String id) {
  unawaited(context.router.pushPath('$kPathBeaconView/$id'));
}

void _openEditDraft(BuildContext context, String id) {
  unawaited(
    context.router.pushPath('$kPathBeaconNew?$kQueryBeaconDraftId=$id'),
  );
}

void _openReviewContributions(BuildContext context, String id) {
  unawaited(context.router.pushPath('$kPathReviewContributions/$id'));
}

class _AuthoredActiveCard extends StatelessWidget {
  const _AuthoredActiveCard({
    required this.vm,
    required this.highlight,
    required this.newStuffReasonLabels,
    required this.activityWhenLine,
  });

  final MyWorkCardViewModel vm;
  final MyWorkCardHighlightKind highlight;
  final List<String> newStuffReasonLabels;
  final String? activityWhenLine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final b = vm.beacon;

    final repo = GetIt.I<BeaconRepository>();
    final evaluationRepo = GetIt.I<EvaluationRepository>();
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);

    final hasReviewCta = vm.showReviewCommitmentsCta;
    final needsForwardCta = !vm.authorHasForwardedOnce;
    final footerActions = (hasReviewCta || needsForwardCta)
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasReviewCta)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () => _openBeacon(context, b.id),
                    child: Text(l10n.myWorkReviewCommitmentsCta),
                  ),
                ),
              if (hasReviewCta && needsForwardCta)
                const SizedBox(height: kSpacingSmall),
              if (needsForwardCta)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => unawaited(
                      context.router.pushPath('$kPathForwardBeacon/${b.id}'),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_forward,
                          size: 18,
                          color: theme.colorScheme.onPrimary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.inboxCardOpenBeacon,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          )
        : null;

    return BeaconCardShell(
      onTap: () => _openBeacon(context, b.id),
      footer: footerActions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: b,
            menu: BeaconOverflowMenu(
              beacon: b,
              onGraph: b.myVote >= 0
                  ? () => context.read<ScreenCubit>().showGraphFor(b.id)
                  : null,
              onShare: () => unawaited(
                ShareCodeDialog.show(
                  context,
                  link: Uri.parse(kServerName).replace(
                    queryParameters: {'id': b.id},
                    path: kPathAppLinkView,
                  ),
                  header: b.id,
                ),
              ),
              onToggleLifecycle: () async {
                await Future<void>.delayed(Duration.zero);
                if (!context.mounted) return;
                if (b.isListed) {
                  if (await BeaconCloseConfirmDialog.show(context) != true) {
                    return;
                  }
                  if (!context.mounted) return;
                }
                try {
                  final next = b.isListed
                      ? BeaconLifecycle.closed
                      : BeaconLifecycle.open;
                  if (next == BeaconLifecycle.closed &&
                      b.lifecycle == BeaconLifecycle.open) {
                    await evaluationRepo.beaconCloseWithReview(b.id);
                  } else {
                    await repo.setBeaconLifecycle(next, id: b.id);
                  }
                } catch (e) {
                  if (context.mounted) {
                    showSnackBar(context, isError: true, text: e.toString());
                  }
                }
              },
              onEdit: b.lifecycle == BeaconLifecycle.open
                  ? () => unawaited(
                        context.router.pushPath(
                          '$kPathBeaconNew?$kQueryBeaconEditId=${b.id}',
                        ),
                      )
                  : null,
              onForward: () => unawaited(
                context.router.pushPath('$kPathForwardBeacon/${b.id}'),
              ),
              onViewForwards: () => unawaited(
                context.router.pushPath('$kPathBeaconForwards/${b.id}'),
              ),
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(b.id),
              onDelete: () async {
                await Future<void>.delayed(Duration.zero);
                if (!context.mounted) return;
                if (await BeaconDeleteDialog.show(context) ?? false) {
                  try {
                    await repo.delete(b.id);
                  } catch (e) {
                    if (context.mounted) {
                      showSnackBar(context, isError: true, text: e.toString());
                    }
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 6),
          BeaconCardMetadataLine(
            beacon: b,
            updatedLine: activityWhenLine,
          ),
          const SizedBox(height: 6),
          MyWorkCardStatusStrip(
            data: statusLine,
          ),
          const SizedBox(height: kSpacingSmall),
          _myWorkFooterActivityBlock(
            context: context,
            highlight: highlight,
            reasonLabels: newStuffReasonLabels,
          ),
        ],
      ),
    );
  }
}

class _CommittedActiveCard extends StatelessWidget {
  const _CommittedActiveCard({
    required this.vm,
    required this.highlight,
    required this.newStuffReasonLabels,
    required this.activityWhenLine,
  });

  final MyWorkCardViewModel vm;
  final MyWorkCardHighlightKind highlight;
  final List<String> newStuffReasonLabels;
  final String? activityWhenLine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final b = vm.beacon;
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);

    return BeaconCardShell(
      onTap: () => _openBeacon(context, b.id),
      footer: vm.showReviewCta
          ? Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () => _openReviewContributions(context, b.id),
                child: Text(l10n.myWorkReviewCta),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: b,
            menu: BeaconOverflowMenu(
              beacon: b,
              onForward: () => unawaited(
                context.router.pushPath('$kPathForwardBeacon/${b.id}'),
              ),
              onViewForwards: () => unawaited(
                context.router.pushPath('$kPathBeaconForwards/${b.id}'),
              ),
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(b.id),
              onComplaint: () =>
                  context.read<ScreenCubit>().showComplaint(b.id),
            ),
          ),
          const SizedBox(height: 6),
          BeaconCardMetadataLine(
            beacon: b,
            updatedLine: activityWhenLine,
          ),
          const SizedBox(height: 6),
          MyWorkCardStatusStrip(
            data: statusLine,
          ),
          const SizedBox(height: kSpacingSmall),
          _myWorkFooterActivityBlock(
            context: context,
            highlight: highlight,
            reasonLabels: newStuffReasonLabels,
          ),
        ],
      ),
    );
  }
}

class _DraftAuthoredCard extends StatelessWidget {
  const _DraftAuthoredCard({
    required this.vm,
    required this.highlight,
    required this.newStuffReasonLabels,
    required this.activityWhenLine,
  });

  final MyWorkCardViewModel vm;
  final MyWorkCardHighlightKind highlight;
  final List<String> newStuffReasonLabels;
  final String? activityWhenLine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final b = vm.beacon;
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);

    return BeaconCardShell(
      muted: true,
      onTap: () => _openEditDraft(context, b.id),
      footer: Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => _openEditDraft(context, b.id),
          child: Text(l10n.myWorkEditDraft),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: b,
            menu: BeaconOverflowMenu(
              beacon: b,
              editActionLabel: l10n.myWorkEditDraft,
              onEdit: () => _openEditDraft(context, b.id),
              onDelete: () async {
                await Future<void>.delayed(Duration.zero);
                if (!context.mounted) return;
                final repo = GetIt.I<BeaconRepository>();
                if (await BeaconDeleteDialog.show(context) ?? false) {
                  try {
                    await repo.delete(b.id);
                  } catch (e) {
                    if (context.mounted) {
                      showSnackBar(context, isError: true, text: e.toString());
                    }
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 6),
          BeaconCardMetadataLine(
            beacon: b,
            updatedLine: activityWhenLine,
          ),
          const SizedBox(height: 6),
          MyWorkCardStatusStrip(
            data: statusLine,
          ),
          const SizedBox(height: kSpacingSmall),
          Text(
            l10n.myWorkDraftStatusLine(b.commitmentCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: kSpacingSmall),
          _myWorkFooterActivityBlock(
            context: context,
            highlight: highlight,
            reasonLabels: newStuffReasonLabels,
          ),
        ],
      ),
    );
  }
}

class _ClosedAuthoredCard extends StatelessWidget {
  const _ClosedAuthoredCard({
    required this.vm,
    required this.highlight,
    required this.newStuffReasonLabels,
    required this.activityWhenLine,
  });

  final MyWorkCardViewModel vm;
  final MyWorkCardHighlightKind highlight;
  final List<String> newStuffReasonLabels;
  final String? activityWhenLine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final b = vm.beacon;
    final repo = GetIt.I<BeaconRepository>();
    final evaluationRepo = GetIt.I<EvaluationRepository>();
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    return BeaconCardShell(
      muted: true,
      onTap: () => _openBeacon(context, b.id),
      footer: Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => showSnackBar(
            context,
            text: l10n.myWorkArchivePlaceholder,
          ),
          child: Text(l10n.myWorkArchive),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: b,
            menu: BeaconOverflowMenu(
              beacon: b,
              onGraph: b.myVote >= 0
                  ? () => context.read<ScreenCubit>().showGraphFor(b.id)
                  : null,
              onShare: () => unawaited(
                ShareCodeDialog.show(
                  context,
                  link: Uri.parse(kServerName).replace(
                    queryParameters: {'id': b.id},
                    path: kPathAppLinkView,
                  ),
                  header: b.id,
                ),
              ),
              onToggleLifecycle: () async {
                await Future<void>.delayed(Duration.zero);
                if (!context.mounted) return;
                if (b.isListed) {
                  if (await BeaconCloseConfirmDialog.show(context) != true) {
                    return;
                  }
                  if (!context.mounted) return;
                }
                try {
                  final next = b.isListed
                      ? BeaconLifecycle.closed
                      : BeaconLifecycle.open;
                  if (next == BeaconLifecycle.closed &&
                      b.lifecycle == BeaconLifecycle.open) {
                    await evaluationRepo.beaconCloseWithReview(b.id);
                  } else {
                    await repo.setBeaconLifecycle(next, id: b.id);
                  }
                } catch (e) {
                  if (context.mounted) {
                    showSnackBar(context, isError: true, text: e.toString());
                  }
                }
              },
              onEdit: b.lifecycle == BeaconLifecycle.open
                  ? () => unawaited(
                        context.router.pushPath(
                          '$kPathBeaconNew?$kQueryBeaconEditId=${b.id}',
                        ),
                      )
                  : null,
              onForward: () => unawaited(
                context.router.pushPath('$kPathForwardBeacon/${b.id}'),
              ),
              onViewForwards: () => unawaited(
                context.router.pushPath('$kPathBeaconForwards/${b.id}'),
              ),
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(b.id),
              onDelete: () async {
                await Future<void>.delayed(Duration.zero);
                if (!context.mounted) return;
                if (await BeaconDeleteDialog.show(context) ?? false) {
                  try {
                    await repo.delete(b.id);
                  } catch (e) {
                    if (context.mounted) {
                      showSnackBar(context, isError: true, text: e.toString());
                    }
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 6),
          BeaconCardMetadataLine(
            beacon: b,
            updatedLine: activityWhenLine,
          ),
          const SizedBox(height: 6),
          MyWorkCardStatusStrip(
            data: statusLine,
          ),
          const SizedBox(height: kSpacingSmall),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _myWorkFooterActivityBlock(
                  context: context,
                  highlight: highlight,
                  reasonLabels: newStuffReasonLabels,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClosedCommittedCard extends StatelessWidget {
  const _ClosedCommittedCard({
    required this.vm,
    required this.highlight,
    required this.newStuffReasonLabels,
    required this.activityWhenLine,
  });

  final MyWorkCardViewModel vm;
  final MyWorkCardHighlightKind highlight;
  final List<String> newStuffReasonLabels;
  final String? activityWhenLine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final b = vm.beacon;
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    return BeaconCardShell(
      muted: true,
      onTap: () => _openBeacon(context, b.id),
      footer: Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => showSnackBar(
            context,
            text: l10n.myWorkArchivePlaceholder,
          ),
          child: Text(l10n.myWorkArchive),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: b,
            menu: BeaconOverflowMenu(
              beacon: b,
              onForward: () => unawaited(
                context.router.pushPath('$kPathForwardBeacon/${b.id}'),
              ),
              onViewForwards: () => unawaited(
                context.router.pushPath('$kPathBeaconForwards/${b.id}'),
              ),
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(b.id),
              onComplaint: () =>
                  context.read<ScreenCubit>().showComplaint(b.id),
            ),
          ),
          const SizedBox(height: 6),
          BeaconCardMetadataLine(
            beacon: b,
            updatedLine: activityWhenLine,
          ),
          const SizedBox(height: 6),
          MyWorkCardStatusStrip(
            data: statusLine,
          ),
          const SizedBox(height: kSpacingSmall),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _myWorkFooterActivityBlock(
                  context: context,
                  highlight: highlight,
                  reasonLabels: newStuffReasonLabels,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
