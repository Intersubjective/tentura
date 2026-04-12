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
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
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

class _WorkCardShell extends StatelessWidget {
  const _WorkCardShell({
    required this.onCardTap,
    required this.child,
    this.muted = false,
  });

  final bool muted;
  final VoidCallback onCardTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = muted
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.45)
        : scheme.surfaceContainer;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      elevation: muted ? 0 : 0.5,
      shadowColor: scheme.shadow.withValues(alpha: 0.12),
      child: InkWell(
        onTap: onCardTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: kPaddingAllS,
          child: child,
        ),
      ),
    );
  }
}

class _WorkCardPill extends StatelessWidget {
  const _WorkCardPill({
    required this.label,
    this.emphasized = false,
  });

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = emphasized ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final fg = emphasized ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.2,
              color: fg,
            ),
      ),
    );
  }
}

class _ContextMeta extends StatelessWidget {
  const _ContextMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(Icons.topic_outlined, size: 14, color: scheme.outline),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthoredActiveCard extends StatelessWidget {
  const _AuthoredActiveCard({required this.vm});

  final MyWorkCardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final b = vm.beacon;

    String? attentionLabel(MyWorkAttentionChip c) => switch (c) {
          MyWorkAttentionChip.reviewPending => l10n.myWorkChipReviewPending,
          MyWorkAttentionChip.reviewWindowOpen =>
            l10n.myWorkChipReviewWindowOpen,
          MyWorkAttentionChip.moreHelpNeeded => l10n.myWorkChipMoreHelp,
        };

    final stripParts = <String>[
      l10n.myWorkCommitmentsShort(b.commitmentCount),
    ];
    if (b.coordinationStatus != BeaconCoordinationStatus.noCommitmentsYet) {
      stripParts.add(coordinationStatusLabel(l10n, b.coordinationStatus));
    }
    final strip = stripParts.join(' · ');

    return _WorkCardShell(
      onCardTap: () => _openBeacon(context, b.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeaderRow(
            beacon: b,
            subline: l10n.myWorkYouAuthor,
            menu: _AuthoredOverflowMenu(beacon: b),
          ),
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingSmall,
            runSpacing: kSpacingSmall,
            children: [
              _WorkCardPill(label: l10n.myWorkChipAuthor),
              if (vm.attentionChip != null)
                _WorkCardPill(
                  label: attentionLabel(vm.attentionChip!)!,
                  emphasized: true,
                ),
            ],
          ),
          if (b.context.trim().isNotEmpty) ...[
            const SizedBox(height: kSpacingSmall),
            _ContextMeta(label: b.context.trim()),
          ],
          const SizedBox(height: kSpacingSmall),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.insights_outlined, size: 16, color: theme.colorScheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  strip,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (b.images.isNotEmpty) BeaconPhotoCount(count: b.images.length),
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
              if (vm.showReviewCommitmentsCta)
                FilledButton.tonal(
                  onPressed: () => _openBeacon(context, b.id),
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

    return _WorkCardShell(
      onCardTap: () => _openBeacon(context, b.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeaderRow(
            beacon: b,
            subline: b.author.title.isEmpty ? '—' : b.author.title,
            menu: _CommittedOverflowMenu(beaconId: b.id),
          ),
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingSmall,
            runSpacing: kSpacingSmall,
            children: [
              _WorkCardPill(label: l10n.myWorkChipCommitted),
              if (vm.showReadyForReviewChip)
                _WorkCardPill(
                  label: l10n.myWorkChipReadyForReview,
                  emphasized: true,
                ),
            ],
          ),
          if (b.context.trim().isNotEmpty) ...[
            const SizedBox(height: kSpacingSmall),
            _ContextMeta(label: b.context.trim()),
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
          const SizedBox(height: kSpacingSmall),
          Row(
            children: [
              if (vm.forwarderSenders.isNotEmpty)
                CompactForwarderAvatars(profiles: vm.forwarderSenders),
              if (vm.forwarderSenders.isNotEmpty) const SizedBox(width: kSpacingSmall),
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
                  onPressed: () => _openBeacon(context, b.id),
                  child: Text(l10n.myWorkReviewCta),
                ),
              ],
            ],
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

    return _WorkCardShell(
      muted: true,
      onCardTap: () => _openBeacon(context, b.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeaderRow(
            beacon: b,
            subline: l10n.myWorkYouAuthor,
            menu: _DraftOverflowMenu(beacon: b),
          ),
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingSmall,
            children: [
              _WorkCardPill(label: l10n.myWorkChipAuthor),
              _WorkCardPill(label: l10n.myWorkChipDraft),
            ],
          ),
          if (b.context.trim().isNotEmpty) ...[
            const SizedBox(height: kSpacingSmall),
            _ContextMeta(label: b.context.trim()),
          ],
          const SizedBox(height: kSpacingSmall),
          Text(
            l10n.myWorkDraftStatusLine(b.commitmentCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
              if (b.images.isNotEmpty) const SizedBox(width: kSpacingSmall),
              TextButton(
                onPressed: () => _openBeacon(context, b.id),
                child: Text(l10n.myWorkEditDraft),
              ),
            ],
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
    return _WorkCardShell(
      muted: true,
      onCardTap: () => _openBeacon(context, b.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeaderRow(
            beacon: b,
            subline: l10n.myWorkYouAuthor,
            menu: _AuthoredOverflowMenu(beacon: b),
          ),
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingSmall,
            children: [
              _WorkCardPill(label: l10n.myWorkChipAuthor),
              _WorkCardPill(label: l10n.beaconLifecycleClosed),
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
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => showSnackBar(
                context,
                text: l10n.myWorkArchivePlaceholder,
              ),
              child: Text(l10n.myWorkArchive),
            ),
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
    return _WorkCardShell(
      muted: true,
      onCardTap: () => _openBeacon(context, b.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeaderRow(
            beacon: b,
            subline: b.author.title.isEmpty ? '—' : b.author.title,
            menu: _CommittedOverflowMenu(beaconId: b.id),
          ),
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingSmall,
            children: [
              _WorkCardPill(label: l10n.myWorkChipCommitted),
              _WorkCardPill(label: l10n.beaconLifecycleClosed),
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
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => showSnackBar(
                context,
                text: l10n.myWorkArchivePlaceholder,
              ),
              child: Text(l10n.myWorkArchive),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardHeaderRow extends StatelessWidget {
  const _CardHeaderRow({
    required this.beacon,
    required this.subline,
    required this.menu,
  });

  final Beacon beacon;
  final String subline;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BeaconIdentityTile(beacon: beacon),
        const SizedBox(width: kSpacingSmall),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                beacon.title.isEmpty ? '—' : beacon.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subline,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        menu,
      ],
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
              final next =
                  beacon.isListed ? BeaconLifecycle.closed : BeaconLifecycle.open;
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
            _openBeacon(context, beacon.id);
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
