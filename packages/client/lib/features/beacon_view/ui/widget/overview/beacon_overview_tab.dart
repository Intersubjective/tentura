import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_info.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import '../../bloc/beacon_view_state.dart';
import '../../util/beacon_chip_derivation.dart';

class BeaconOverviewTab extends StatelessWidget {
  const BeaconOverviewTab({
    required this.state,
    required this.onTapForwardChain,
    required this.onViewAllCommitments,
    required this.onEditTimelineUpdate,
    super.key,
  });

  final BeaconViewState state;
  final VoidCallback onTapForwardChain;
  final VoidCallback onViewAllCommitments;
  final Future<void> Function(TimelineUpdate u) onEditTimelineUpdate;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final beacon = state.beacon;
    final latest = latestTimelineUpdate(state.timeline);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverviewSection(
          storageKey: 'ov-coord-${beacon.id}',
          title: l10n.beaconCoordinationCardTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                coordinationStatusLabel(l10n, beacon.coordinationStatus),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: coordinationStatusColor(
                    theme.colorScheme,
                    beacon.coordinationStatus,
                  ),
                ),
              ),
              const SizedBox(height: kSpacingSmall),
              Wrap(
                spacing: kSpacingSmall,
                runSpacing: kSpacingSmall,
                children: [
                  BeaconCardPill(
                    label: l10n.beaconChipCommitsCount(
                      activeCommitmentCount(state.commitments),
                    ),
                  ),
                  BeaconCardPill(
                    label: l10n.beaconChipUsefulCount(
                      usefulCommitmentCount(state.commitments),
                    ),
                  ),
                  if (withdrawnCommitmentCount(state.commitments) > 0)
                    BeaconCardPill(
                      label: l10n.beaconShowWithdrawn(
                        withdrawnCommitmentCount(state.commitments),
                      ),
                      backgroundColor: theme.colorScheme.surfaceContainerHigh,
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                    ),
                  if (beacon.coordinationStatus ==
                      BeaconCoordinationStatus.moreOrDifferentHelpNeeded)
                    BeaconCardPill(
                      label: l10n.beaconChipMoreHelpNeeded,
                      emphasized: true,
                    ),
                ],
              ),
              const SizedBox(height: kSpacingSmall),
              Row(
                children: [
                  for (final u in state.commitments
                      .where((c) => !c.isWithdrawn)
                      .take(3))
                    Padding(
                      padding: const EdgeInsets.only(right: kSpacingSmall),
                      child: AvatarRated(
                        profile: u.user,
                        size: 28,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    l10n.labelCommitmentCount(
                      activeCommitmentCount(state.commitments),
                    ),
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onViewAllCommitments,
                  child: Text(l10n.beaconViewAllCommitments),
                ),
              ),
              if (latest != null) ...[
                const SizedBox(height: kSpacingSmall),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: BlocBuilder<ProfileCubit, ProfileState>(
                        buildWhen: (p, c) => p.profile.id != c.profile.id,
                        builder: (context, ps) {
                          return Text(
                            '${SelfUserHighlight.displayName(l10n, latest.author, ps.profile.id)} · ${latest.content}',
                            style: theme.textTheme.bodySmall,
                          );
                        },
                      ),
                    ),
                    if (state.isBeaconMine &&
                        beacon.lifecycle == BeaconLifecycle.open &&
                        _authorUpdateEditableNow(latest.createdAt))
                      IconButton(
                        tooltip: l10n.editUpdateCTA,
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () =>
                            unawaited(onEditTimelineUpdate(latest)),
                      ),
                  ],
                ),
                const SizedBox(height: kSpacingSmall),
                Text(
                  '${dateFormatYMD(latest.createdAt.toLocal())} ${timeFormatHm(latest.createdAt.toLocal())}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        _OverviewSection(
          storageKey: 'ov-desc-${beacon.id}',
          title: l10n.beaconDescriptionAttachmentsTitle,
          child: BeaconInfo(
            key: ValueKey('overview-${beacon.id}'),
            beacon: beacon,
            isShowBeaconEnabled: false,
            isShowMoreEnabled: false,
            showTitle: false,
            descriptionBeforeMedia: true,
            mediaMaxHeight: 180,
            compactImageGallery: true,
          ),
        ),
        if (beacon.context.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: kSpacingSmall / 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(beacon.context.trim()),
              ),
            ),
          ),
      ],
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.storageKey,
    required this.title,
    required this.child,
  });

  final String storageKey;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: PageStorageKey<String>(storageKey),
      margin: const EdgeInsets.only(bottom: kSpacingSmall),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        maintainState: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: kSpacingSmall),
        visualDensity: VisualDensity.compact,
        minTileHeight: 44,
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        childrenPadding: kPaddingSmallH.add(
          const EdgeInsets.only(bottom: kSpacingSmall),
        ),
        children: [child],
      ),
    );
  }
}

const _beaconAuthorUpdateEditWindow = Duration(hours: 1);

bool _authorUpdateEditableNow(DateTime createdAt) =>
    DateTime.now().toUtc().difference(createdAt.toUtc()) <=
    _beaconAuthorUpdateEditWindow;
