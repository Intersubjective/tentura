import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_card_deadline.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_photo_count.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

import 'compact_forwarder_avatars.dart';

String _truncate(String s, int max) {
  final t = s.trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max - 1)}…';
}

String _updatedWhenText(L10n l10n, Beacon b) {
  final when = dateFormatYMD(b.updatedAt);
  return l10n.myWorkUpdatedLine(when);
}

Widget _myWorkSublineText(BuildContext context, String text) {
  final theme = Theme.of(context);
  return Text(
    text,
    style: theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

/// Beacon context for the stats row first column (matches inbox category column).
String _beaconCategoryLabel(Beacon b, L10n l10n) {
  final c = b.context.trim();
  return c.isEmpty ? l10n.inboxCategoryGeneral : c;
}

class MyWorkCardRouter extends StatelessWidget {
  const MyWorkCardRouter({required this.vm, super.key});

  final MyWorkCardViewModel vm;

  @override
  Widget build(BuildContext context) {
    return switch (vm.kind) {
      MyWorkCardKind.authoredDraft => _DraftAuthoredCard(vm: vm),
      MyWorkCardKind.authoredActive => _AuthoredActiveCard(vm: vm),
      MyWorkCardKind.committedActive => _CommittedActiveCard(vm: vm),
      MyWorkCardKind.authoredClosed => _ClosedAuthoredCard(vm: vm),
      MyWorkCardKind.committedClosed => _ClosedCommittedCard(vm: vm),
    };
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
  const _AuthoredActiveCard({required this.vm});

  final MyWorkCardViewModel vm;

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

    return BeaconCardShell(
      onTap: () => _openBeacon(context, b.id),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _updatedWhenText(l10n, b),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
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
            subline: _myWorkSublineText(context, l10n.myWorkYouAuthor),
            menu: _AuthoredOverflowMenu(beacon: b),
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
  const _CommittedActiveCard({required this.vm});

  final MyWorkCardViewModel vm;

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
        children: [
          if (vm.forwarderSenders.isNotEmpty)
            CompactForwarderAvatars(profiles: vm.forwarderSenders),
          if (vm.forwarderSenders.isNotEmpty)
            const SizedBox(width: kSpacingSmall),
          Expanded(
            child: Text(
              _updatedWhenText(l10n, b),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.outline,
              ),
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
            subline: _myWorkSublineText(
              context,
              b.author.title.isEmpty ? '—' : b.author.title,
            ),
            menu: _CommittedOverflowMenu(beaconId: b.id),
          ),
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingSmall,
            runSpacing: kSpacingSmall,
            children: [
              BeaconCardPill(label: l10n.myWorkChipCommitted),
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
  const _DraftAuthoredCard({required this.vm});

  final MyWorkCardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final b = vm.beacon;

    return BeaconCardShell(
      muted: true,
      onTap: () => _openEditDraft(context, b.id),
      footer: Row(
        children: [
          Expanded(
            child: Text(
              _updatedWhenText(l10n, b),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
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
            subline: _myWorkSublineText(context, l10n.myWorkYouAuthor),
            menu: _DraftOverflowMenu(beacon: b),
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
  const _ClosedAuthoredCard({required this.vm});

  final MyWorkCardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
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
            subline: _myWorkSublineText(context, l10n.myWorkYouAuthor),
            menu: _AuthoredOverflowMenu(beacon: b),
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
            children: [
              Expanded(
                child: Text(
                  _updatedWhenText(l10n, b),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
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
  const _ClosedCommittedCard({required this.vm});

  final MyWorkCardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
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
            subline: _myWorkSublineText(
              context,
              b.author.title.isEmpty ? '—' : b.author.title,
            ),
            menu: _CommittedOverflowMenu(beaconId: b.id),
          ),
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingSmall,
            children: [
              BeaconCardPill(label: l10n.myWorkChipCommitted),
              BeaconCardPill(label: l10n.beaconLifecycleClosed),
              if (vm.authorHasForwardedOnce)
                BeaconCardPill(label: l10n.myWorkChipForwarded),
            ],
          ),
          const SizedBox(height: kSpacingSmall),
          Row(
            children: [
              Expanded(
                child: Text(
                  _updatedWhenText(l10n, b),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
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

class _AuthoredOverflowMenu extends StatelessWidget {
  const _AuthoredOverflowMenu({required this.beacon});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final repo = GetIt.I<BeaconRepository>();
    final evaluationRepo = GetIt.I<EvaluationRepository>();
    return PopupMenuButton<void>(
      icon: const Icon(Icons.more_vert),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          child: Text(beacon.isListed ? l10n.closeBeacon : l10n.openBeacon),
          onTap: () async {
            await Future<void>.delayed(Duration.zero);
            if (!context.mounted) return;
            if (beacon.isListed) {
              if (await BeaconCloseConfirmDialog.show(context) != true) {
                return;
              }
              if (!context.mounted) return;
            }
            try {
              final next = beacon.isListed
                  ? BeaconLifecycle.closed
                  : BeaconLifecycle.open;
              if (next == BeaconLifecycle.closed &&
                  beacon.lifecycle == BeaconLifecycle.open) {
                await evaluationRepo.beaconCloseWithReview(beacon.id);
              } else {
                await repo.setBeaconLifecycle(next, id: beacon.id);
              }
            } catch (e) {
              if (context.mounted) {
                showSnackBar(context, isError: true, text: e.toString());
              }
            }
          },
        ),
        PopupMenuItem<void>(
          child: Text(l10n.labelForward),
          onTap: () async {
            await Future<void>.delayed(Duration.zero);
            if (!context.mounted) return;
            await context.router.pushPath('$kPathForwardBeacon/${beacon.id}');
          },
        ),
        PopupMenuItem<void>(
          child: Text(l10n.deleteBeacon),
          onTap: () async {
            await Future<void>.delayed(Duration.zero);
            if (!context.mounted) return;
            if (await BeaconDeleteDialog.show(context) ?? false) {
              try {
                await repo.delete(beacon.id);
              } catch (e) {
                if (context.mounted) {
                  showSnackBar(context, isError: true, text: e.toString());
                }
              }
            }
          },
        ),
        PopupMenuItem<void>(
          child: Text(l10n.buttonComplaint),
          onTap: () async {
            await Future<void>.delayed(Duration.zero);
            if (!context.mounted) return;
            context.read<ScreenCubit>().showComplaint(beacon.id);
          },
        ),
      ],
    );
  }
}

class _DraftOverflowMenu extends StatelessWidget {
  const _DraftOverflowMenu({required this.beacon});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final repo = GetIt.I<BeaconRepository>();
    return PopupMenuButton<void>(
      icon: const Icon(Icons.more_vert),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          child: Text(l10n.myWorkEditDraft),
          onTap: () async {
            await Future<void>.delayed(Duration.zero);
            if (!context.mounted) return;
            _openEditDraft(context, beacon.id);
          },
        ),
        PopupMenuItem<void>(
          child: Text(l10n.deleteBeacon),
          onTap: () async {
            await Future<void>.delayed(Duration.zero);
            if (!context.mounted) return;
            if (await BeaconDeleteDialog.show(context) ?? false) {
              try {
                await repo.delete(beacon.id);
              } catch (e) {
                if (context.mounted) {
                  showSnackBar(context, isError: true, text: e.toString());
                }
              }
            }
          },
        ),
      ],
    );
  }
}

class _CommittedOverflowMenu extends StatelessWidget {
  const _CommittedOverflowMenu({required this.beaconId});

  final String beaconId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return PopupMenuButton<void>(
      icon: const Icon(Icons.more_vert),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          child: Text(l10n.labelForward),
          onTap: () async {
            await Future<void>.delayed(Duration.zero);
            if (!context.mounted) return;
            await context.router.pushPath('$kPathForwardBeacon/$beaconId');
          },
        ),
        PopupMenuItem<void>(
          child: Text(l10n.buttonComplaint),
          onTap: () async {
            await Future<void>.delayed(Duration.zero);
            if (!context.mounted) return;
            context.read<ScreenCubit>().showComplaint(beaconId);
          },
        ),
      ],
    );
  }
}
