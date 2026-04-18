import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_card_deadline.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_author_subline.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_photo_count.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';
import 'package:tentura/features/home/ui/widget/new_stuff_dot.dart';
import 'package:tentura/features/home/ui/widget/new_stuff_reason_l10n.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

String _truncate(String s, int max) {
  final t = s.trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max - 1)}…';
}

String _formatDateTimeActivityLine(DateTime d) =>
    '${dateFormatYMD(d)} ${timeFormatHm(d)}';

String _myWorkActivityWhenLine(
  L10n l10n,
  MyWorkCardViewModel vm,
  MyWorkCardHighlightKind highlight,
) {
  final b = vm.beacon;
  final at = highlight == MyWorkCardHighlightKind.none
      ? b.updatedAt
      : DateTime.fromMillisecondsSinceEpoch(vm.newStuffActivityEpochMs);
  return l10n.myWorkUpdatedLine(_formatDateTimeActivityLine(at));
}

Widget _myWorkFooterActivityBlock({
  required BuildContext context,
  required MyWorkCardHighlightKind highlight,
  required List<String> reasonLabels,
  required String activityWhenLine,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final style = theme.textTheme.labelSmall?.copyWith(color: scheme.outline);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _myWorkNewStuffDot(context, highlight),
          Expanded(
            child: Text(
              activityWhenLine,
              style: style,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      if (reasonLabels.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in reasonLabels)
                Text(line, style: style),
            ],
          ),
        ),
    ],
  );
}

/// Beacon context for the stats row first column (matches inbox category column).
String _beaconCategoryLabel(Beacon b, L10n l10n) {
  final c = b.context.trim();
  return c.isEmpty ? l10n.inboxCategoryGeneral : c;
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

void _openBeaconCommitmentsTab(BuildContext context, String id) {
  unawaited(
    context.router.pushPath(
      '$kPathBeaconView/$id?$kQueryBeaconViewTab=commitments',
    ),
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
  final String activityWhenLine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = vm.beacon;

    String? attentionLabel(MyWorkAttentionChip c) => switch (c) {
      MyWorkAttentionChip.reviewPending => l10n.myWorkChipReviewPending,
      MyWorkAttentionChip.reviewWindowOpen => l10n.myWorkChipReviewWindowOpen,
      MyWorkAttentionChip.moreHelpNeeded => l10n.myWorkChipMoreHelp,
    };

    final categoryLabel = _beaconCategoryLabel(b, l10n);
    final hoursRemaining = beaconCardDeadlineRemainingMeta(l10n, b.endAt);
    final repo = GetIt.I<BeaconRepository>();
    final evaluationRepo = GetIt.I<EvaluationRepository>();

    return BeaconCardShell(
      onTap: () => _openBeacon(context, b.id),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _myWorkFooterActivityBlock(
                  context: context,
                  highlight: highlight,
                  reasonLabels: newStuffReasonLabels,
                  activityWhenLine: activityWhenLine,
                ),
              ),
              if (vm.showReviewCommitmentsCta)
                FilledButton.tonal(
                  onPressed: () => _openBeaconCommitmentsTab(context, b.id),
                  child: Text(l10n.myWorkReviewCommitmentsCta),
                ),
            ],
          ),
          if (!vm.authorHasForwardedOnce) ...[
            const SizedBox(height: kSpacingSmall),
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
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: b,
            subline: BeaconCardAuthorSubline(author: b.author),
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
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingSmall,
            runSpacing: kSpacingSmall,
            children: [
              BeaconCardPill(label: l10n.myWorkChipAuthor),
              if (vm.attentionChip != null)
                BeaconCardPill(
                  label: attentionLabel(vm.attentionChip!)!,
                  emphasized:
                      vm.attentionChip != MyWorkAttentionChip.reviewPending,
                ),
              if (vm.authorHasForwardedOnce)
                BeaconCardPill(label: l10n.myWorkChipForwarded),
            ],
          ),
          const SizedBox(height: kSpacingSmall),
          Divider(
            height: 1,
            thickness: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingMedium,
            runSpacing: kSpacingSmall,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              BeaconCardMetaItem(
                icon: Icons.topic_outlined,
                child: Text(
                  categoryLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              BeaconCardMetaItem(
                icon: Icons.groups_outlined,
                child: Text(
                  l10n.inboxCommitmentsCount(b.commitmentCount),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hoursRemaining != null)
                BeaconCardMetaItem(
                  icon: Icons.timer_outlined,
                  child: Text(
                    hoursRemaining.text,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hoursRemaining.urgent
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                      fontWeight: hoursRemaining.urgent
                          ? FontWeight.w600
                          : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (b.images.isNotEmpty)
                BeaconCardMetaItem(
                  icon: Icons.photo_library_outlined,
                  child: Text(
                    b.images.length > 99 ? '99+' : '${b.images.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
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
  final String activityWhenLine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = vm.beacon;

    final responseText = vm.authorResponseType == null
        ? l10n.myWorkNoAuthorResponse
        : (coordinationResponseLabel(l10n, vm.authorResponseType) ??
              l10n.myWorkNoAuthorResponse);

    final note = vm.commitMessage.isEmpty
        ? '—'
        : _truncate(vm.commitMessage, 120);

    return BeaconCardShell(
      onTap: () => _openBeacon(context, b.id),
      footer: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _myWorkFooterActivityBlock(
              context: context,
              highlight: highlight,
              reasonLabels: newStuffReasonLabels,
              activityWhenLine: activityWhenLine,
            ),
          ),
          if (b.images.isNotEmpty) BeaconPhotoCount(count: b.images.length),
          if (vm.showReviewCta) ...[
            if (b.images.isNotEmpty) const SizedBox(width: kSpacingSmall),
            FilledButton.tonal(
              onPressed: () => _openReviewContributions(context, b.id),
              child: Text(l10n.myWorkReviewCta),
            ),
          ],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: b,
            subline: BeaconCardAuthorSubline(author: b.author),
            menu: BeaconOverflowMenu(
              beacon: b,
              onForward: () => unawaited(
                context.router.pushPath('$kPathForwardBeacon/${b.id}'),
              ),
              onViewForwards: () => unawaited(
                context.router.pushPath('$kPathBeaconForwards/${b.id}'),
              ),
              onComplaint: () =>
                  context.read<ScreenCubit>().showComplaint(b.id),
            ),
          ),
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingSmall,
            runSpacing: kSpacingSmall,
            children: [
              BeaconCardPill(label: l10n.myWorkChipCommitted),
              if (b.coordinationStatus ==
                  BeaconCoordinationStatus.moreOrDifferentHelpNeeded)
                BeaconCardPill(
                  label: l10n.myWorkChipMoreHelp,
                  emphasized: true,
                ),
              if (vm.showReadyForReviewChip)
                BeaconCardPill(
                  label: l10n.myWorkChipReadyForReview,
                ),
              if (vm.authorHasForwardedOnce)
                BeaconCardPill(label: l10n.myWorkChipForwarded),
            ],
          ),
          if (b.context.trim().isNotEmpty) ...[
            const SizedBox(height: kSpacingSmall),
            BeaconCardMetaItem(
              icon: Icons.topic_outlined,
              mainAxisSize: MainAxisSize.max,
              child: Expanded(
                child: Text(
                  b.context.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: kSpacingSmall),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.myWorkYourNoteLine(note),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.myWorkAuthorResponseLine(responseText),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
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
  final String activityWhenLine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final b = vm.beacon;

    return BeaconCardShell(
      muted: true,
      onTap: () => _openEditDraft(context, b.id),
      footer: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _myWorkFooterActivityBlock(
              context: context,
              highlight: highlight,
              reasonLabels: newStuffReasonLabels,
              activityWhenLine: activityWhenLine,
            ),
          ),
          if (b.images.isNotEmpty) BeaconPhotoCount(count: b.images.length),
          if (b.images.isNotEmpty) const SizedBox(width: kSpacingSmall),
          TextButton(
            onPressed: () => _openEditDraft(context, b.id),
            child: Text(l10n.myWorkEditDraft),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: b,
            subline: BeaconCardAuthorSubline(author: b.author),
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
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingSmall,
            children: [
              BeaconCardPill(label: l10n.myWorkChipAuthor),
              BeaconCardPill(label: l10n.myWorkChipDraft),
            ],
          ),
          if (b.context.trim().isNotEmpty) ...[
            const SizedBox(height: kSpacingSmall),
            BeaconCardMetaItem(
              icon: Icons.topic_outlined,
              mainAxisSize: MainAxisSize.max,
              child: Expanded(
                child: Text(
                  b.context.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: kSpacingSmall),
          Text(
            l10n.myWorkDraftStatusLine(b.commitmentCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
  final String activityWhenLine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final b = vm.beacon;
    final repo = GetIt.I<BeaconRepository>();
    final evaluationRepo = GetIt.I<EvaluationRepository>();
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
            subline: BeaconCardAuthorSubline(author: b.author),
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
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingSmall,
            children: [
              BeaconCardPill(label: l10n.myWorkChipAuthor),
              BeaconCardPill(label: l10n.beaconLifecycleClosed),
              if (vm.authorHasForwardedOnce)
                BeaconCardPill(label: l10n.myWorkChipForwarded),
            ],
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
                  activityWhenLine: activityWhenLine,
                ),
              ),
              if (b.images.isNotEmpty) BeaconPhotoCount(count: b.images.length),
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
  final String activityWhenLine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final b = vm.beacon;
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
            subline: BeaconCardAuthorSubline(author: b.author),
            menu: BeaconOverflowMenu(
              beacon: b,
              onForward: () => unawaited(
                context.router.pushPath('$kPathForwardBeacon/${b.id}'),
              ),
              onViewForwards: () => unawaited(
                context.router.pushPath('$kPathBeaconForwards/${b.id}'),
              ),
              onComplaint: () =>
                  context.read<ScreenCubit>().showComplaint(b.id),
            ),
          ),
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingSmall,
            children: [
              BeaconCardPill(label: l10n.myWorkChipCommitted),
              if (b.coordinationStatus ==
                  BeaconCoordinationStatus.moreOrDifferentHelpNeeded)
                BeaconCardPill(
                  label: l10n.myWorkChipMoreHelp,
                  emphasized: true,
                ),
              BeaconCardPill(label: l10n.beaconLifecycleClosed),
              if (vm.authorHasForwardedOnce)
                BeaconCardPill(label: l10n.myWorkChipForwarded),
            ],
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
                  activityWhenLine: activityWhenLine,
                ),
              ),
              if (b.images.isNotEmpty) BeaconPhotoCount(count: b.images.length),
            ],
          ),
        ],
      ),
    );
  }
}
