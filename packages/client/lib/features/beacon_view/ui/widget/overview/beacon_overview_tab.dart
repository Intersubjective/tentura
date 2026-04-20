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
import 'package:tentura/ui/widget/tentura_icons.dart';

import 'package:tentura/features/geo/ui/dialog/choose_location_dialog.dart';

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
    final needLine = firstParagraphNeedLine(beacon);
    final latest = latestTimelineUpdate(state.timeline);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverviewCard(
          title: l10n.beaconNeedSummaryTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (beacon.startAt != null || beacon.endAt != null)
                Row(
                  children: [
                    Icon(
                      TenturaIcons.calendar,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: kSpacingSmall),
                    Expanded(
                      child: Text(
                        '${dateFormatYMD(beacon.startAt)} — ${dateFormatYMD(beacon.endAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              if (beacon.coordinates?.isNotEmpty ?? false) ...[
                const SizedBox(height: kSpacingSmall),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      TenturaIcons.location,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: kSpacingSmall),
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => ChooseLocationDialog.show(
                          context,
                          center: beacon.coordinates,
                        ),
                        child: Text(
                          l10n.showOnMap,
                          style: theme.textTheme.bodySmall?.copyWith(
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (needLine != null) ...[
                const SizedBox(height: kSpacingSmall),
                Text(
                  needLine,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (beacon.coordinationStatus ==
                  BeaconCoordinationStatus.moreOrDifferentHelpNeeded) ...[
                const SizedBox(height: kSpacingSmall),
                Wrap(
                  spacing: kSpacingSmall,
                  runSpacing: kSpacingSmall,
                  children: [
                    BeaconCardPill(
                      label: l10n.beaconChipMoreHelpNeeded,
                      emphasized: true,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        _OverviewCard(
          title: l10n.beaconCoordinationCardTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                coordinationStatusLabel(l10n, beacon.coordinationStatus),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
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
                ],
              ),
            ],
          ),
        ),
        if (_hasRelationContext(state))
          _OverviewCard(
            title: l10n.beaconYourRelationTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _forwardChainLine(l10n, state),
                  style: theme.textTheme.bodySmall,
                ),
                if (state.inboxLatestNotePreview.trim().isNotEmpty) ...[
                  const SizedBox(height: kSpacingSmall),
                  Text(
                    state.inboxLatestNotePreview.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        _OverviewCard(
          title: l10n.beaconCommitSnapshotTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: kSpacingSmall),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onViewAllCommitments,
                  child: Text(l10n.beaconViewAllCommitments),
                ),
              ),
            ],
          ),
        ),
        if (latest != null)
          _OverviewCard(
            title: l10n.beaconLatestUpdateTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                        onPressed: () => unawaited(onEditTimelineUpdate(latest)),
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
            ),
          ),
        _OverviewCard(
          title: l10n.beaconForwardChainPreview,
          child: InkWell(
            onTap: onTapForwardChain,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: kSpacingSmall),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _forwardChainLine(l10n, state),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.beaconForwardChainTapHint,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _OverviewCard(
          title: l10n.beaconDescriptionAttachmentsTitle,
          child: BeaconInfo(
            key: ValueKey('overview-${beacon.id}'),
            beacon: beacon,
            isShowBeaconEnabled: false,
            showTitle: false,
            descriptionBeforeMedia: true,
            mediaMaxHeight: 180,
            compactImageGallery: true,
          ),
        ),
        if (beacon.context.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: kSpacingSmall),
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

bool _hasRelationContext(BeaconViewState state) {
  final p = state.forwardProvenance;
  if (state.inboxStatus != null) return true;
  return p.senders.isNotEmpty ||
      p.totalDistinctSenders > 0 ||
      p.strongestNotePreview.trim().isNotEmpty;
}

String _forwardChainLine(L10n l10n, BeaconViewState state) {
  final names = state.forwardProvenance.senders
      .map((s) => s.title.isEmpty ? l10n.noName : s.title)
      .toList();
  if (names.isNotEmpty) {
    return l10n.beaconViaChain(
      '${names.join(' → ')} → ${l10n.labelYou}',
    );
  }
  final n = distinctForwarderCountTowardViewer(
    viewerForwardEdges: state.viewerForwardEdges,
    myUserId: state.myProfile.id,
  );
  if (n > 0) {
    return l10n.beaconChipForwardedBy(n);
  }
  return l10n.beaconRelationNoTrail;
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: kSpacingMedium),
      child: Padding(
        padding: kPaddingAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: kSpacingSmall),
            child,
          ],
        ),
      ),
    );
  }
}

const _beaconAuthorUpdateEditWindow = Duration(hours: 1);

bool _authorUpdateEditableNow(DateTime createdAt) =>
    DateTime.now().toUtc().difference(createdAt.toUtc()) <=
    _beaconAuthorUpdateEditWindow;
