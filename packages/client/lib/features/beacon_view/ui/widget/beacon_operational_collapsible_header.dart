import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/beacon_view_state.dart';
import '../util/beacon_chip_derivation.dart';
import 'beacon_primary_cta_bar.dart';

class BeaconOperationalCollapsibleHeader extends StatelessWidget {
  const BeaconOperationalCollapsibleHeader({
    required this.state,
    required this.onStatusChipTap,
    required this.onUpdateStatus,
    required this.onPostUpdate,
    required this.onCommit,
    required this.onEditCommitment,
    required this.onWithdraw,
    required this.onForward,
    required this.onViewChain,
    super.key,
  });

  final BeaconViewState state;
  final VoidCallback? onStatusChipTap;
  final VoidCallback? onUpdateStatus;
  final VoidCallback? onPostUpdate;
  final VoidCallback? onCommit;
  final VoidCallback? onEditCommitment;
  final VoidCallback? onWithdraw;
  final VoidCallback? onForward;
  final VoidCallback? onViewChain;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final beacon = state.beacon;

    final chips = deriveSupportingChips(
      l10n: l10n,
      beacon: beacon,
      commitments: state.commitments,
      viewerForwardEdges: state.viewerForwardEdges,
      myUserId: state.myProfile.id,
      isAuthorView: state.isBeaconMine,
    );

    final showCoordinationPill = state.isBeaconMine ||
        (beacon.coordinationStatus != BeaconCoordinationStatus.noCommitmentsYet &&
            beacon.coordinationStatus !=
                BeaconCoordinationStatus.commitmentsWaitingForReview);

    return Padding(
      padding: const EdgeInsets.only(bottom: kSpacingSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BeaconIdentityTile(beacon: beacon),
              const SizedBox(width: kSpacingSmall),
              Expanded(
                child: Text(
                  beacon.title.isEmpty ? '—' : beacon.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: kSpacingSmall),
          Wrap(
            spacing: kSpacingSmall,
            runSpacing: kSpacingSmall,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (beacon.lifecycle != BeaconLifecycle.open)
                BeaconCardPill(
                  label: _lifecycleLabel(l10n, beacon.lifecycle),
                ),
              if (showCoordinationPill)
                BeaconCardPill(
                  label: coordinationStatusLabel(
                    l10n,
                    beacon.coordinationStatus,
                  ),
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  emphasized: true,
                  onTap: state.isBeaconMine ? onStatusChipTap : null,
                ),
              for (final c in chips)
                BeaconCardPill(
                  label: c.label,
                  emphasized: c.emphasized,
                  backgroundColor: c.emphasized
                      ? null
                      : theme.colorScheme.surfaceContainerHigh,
                  foregroundColor: c.emphasized
                      ? null
                      : theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
          BeaconPrimaryCtaBar(
            state: state,
            onUpdateStatus: onUpdateStatus,
            onPostUpdate: onPostUpdate,
            onCommit: onCommit,
            onEditCommitment: onEditCommitment,
            onWithdraw: onWithdraw,
            onForward: onForward,
            onViewChain: onViewChain,
          ),
        ],
      ),
    );
  }
}

String _lifecycleLabel(L10n l10n, BeaconLifecycle lc) => switch (lc) {
      BeaconLifecycle.open => l10n.beaconLifecycleOpen,
      BeaconLifecycle.closed => l10n.beaconLifecycleClosed,
      BeaconLifecycle.deleted => l10n.beaconLifecycleDeleted,
      BeaconLifecycle.draft => l10n.beaconLifecycleDraft,
      BeaconLifecycle.pendingReview => l10n.beaconLifecyclePendingReview,
      BeaconLifecycle.closedReviewOpen => l10n.beaconLifecycleClosedReviewOpen,
      BeaconLifecycle.closedReviewComplete =>
        l10n.beaconLifecycleClosedReviewComplete,
    };
