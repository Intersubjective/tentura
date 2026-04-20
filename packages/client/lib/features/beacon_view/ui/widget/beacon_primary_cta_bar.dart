import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/beacon_view_state.dart';

/// Primary + secondary actions for the beacon operational header.
class BeaconPrimaryCtaBar extends StatelessWidget {
  const BeaconPrimaryCtaBar({
    required this.state,
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
    final open = beacon.lifecycle == BeaconLifecycle.open;

    Widget? primary;
    Widget? secondary;

    if (state.isBeaconMine && open) {
      primary = onUpdateStatus != null
          ? FilledButton(
              onPressed: onUpdateStatus,
              child: Text(l10n.beaconCtaUpdateStatus),
            )
          : null;
      secondary = onPostUpdate != null
          ? TextButton(
              onPressed: onPostUpdate,
              child: Text(l10n.postUpdateCTA),
            )
          : null;
    } else if (!state.isBeaconMine && open) {
      if (!state.isCommitted && beacon.allowsNewCommitAsNonAuthor) {
        primary = onCommit != null
            ? FilledButton(
                onPressed: onCommit,
                child: Text(l10n.labelCommit),
              )
            : null;
        secondary = onForward != null
            ? TextButton(
                onPressed: onForward,
                child: Text(l10n.labelForward),
              )
            : null;
      } else if (state.isCommitted) {
        if (beacon.allowsWithdrawWhileCommitted) {
          primary = onEditCommitment != null
              ? FilledButton(
                  onPressed: onEditCommitment,
                  child: Text(l10n.beaconCtaEditCommitment),
                )
              : null;
          secondary = onWithdraw != null
              ? TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: onWithdraw,
                  child: Text(l10n.dialogWithdrawTitle),
                )
              : null;
        } else {
          primary = onForward != null
              ? FilledButton(
                  onPressed: onForward,
                  child: Text(l10n.labelForward),
                )
              : null;
          secondary = onViewChain != null
              ? TextButton(
                  onPressed: onViewChain,
                  child: Text(l10n.beaconCtaViewChain),
                )
              : null;
        }
      } else {
        primary = onForward != null
            ? FilledButton(
                onPressed: onForward,
                child: Text(l10n.labelForward),
              )
            : null;
        secondary = onViewChain != null
            ? TextButton(
                onPressed: onViewChain,
                child: Text(l10n.beaconCtaViewChain),
              )
            : null;
      }
    } else {
      secondary = onViewChain != null
          ? TextButton(
              onPressed: onViewChain,
              child: Text(l10n.beaconCtaViewChain),
            )
          : null;
    }

    if (primary == null && secondary == null && open) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: kSpacingSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!open)
            Padding(
              padding: const EdgeInsets.only(bottom: kSpacingSmall),
              child: Align(
                alignment: Alignment.centerLeft,
                child: BeaconCardPillReadOnly(l10n: l10n),
              ),
            ),
          ?primary,
          if (primary != null && secondary != null)
            const SizedBox(height: kSpacingSmall),
          ?secondary,
        ],
      ),
    );
  }
}

class BeaconCardPillReadOnly extends StatelessWidget {
  const BeaconCardPillReadOnly({required this.l10n, super.key});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        l10n.beaconCtaReadOnly,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
