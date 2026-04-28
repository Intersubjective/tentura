import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/card_triage_action_row.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

import '../bloc/beacon_view_state.dart';

/// Primary + secondary actions for the beacon operational header.
class BeaconPrimaryCtaBar extends StatelessWidget {
  const BeaconPrimaryCtaBar({
    required this.state,
    required this.onUpdateStatus,
    required this.onPostUpdate,
    required this.onCommit,
    required this.onForward,
    required this.onViewChain,
    super.key,
  });

  final BeaconViewState state;
  final VoidCallback? onUpdateStatus;
  final VoidCallback? onPostUpdate;
  final Future<void> Function()? onCommit;
  final VoidCallback? onForward;
  final VoidCallback? onViewChain;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final beacon = state.beacon;
    final open = beacon.lifecycle == BeaconLifecycle.open;

    if (!open) {
      if (onViewChain == null) {
        return Padding(
          padding: const EdgeInsets.only(top: kSpacingSmall),
          child: Align(
            alignment: Alignment.centerLeft,
            child: BeaconCardPillReadOnly(l10n: l10n),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(top: kSpacingSmall),
        child: Row(
          children: [
            BeaconCardPillReadOnly(l10n: l10n),
            const Spacer(),
            IconButton(
              onPressed: onViewChain,
              icon: const Icon(TenturaIcons.graph, size: 22),
              style: IconButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              tooltip: l10n.beaconCtaViewChain,
            ),
          ],
        ),
      );
    }

    if (state.isBeaconMine) {
      final primary = onUpdateStatus != null
          ? FilledButton(
              onPressed: onUpdateStatus,
              style: FilledButton.styleFrom(
                textStyle: theme.textTheme.labelLarge!.copyWith(
                  color: scheme.onPrimary,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                alignment: Alignment.center,
              ),
              child: Text(
                l10n.beaconCtaUpdateStatus,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            )
          : null;
      final secondary = onPostUpdate != null
          ? OutlinedButton(
              onPressed: onPostUpdate,
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.primary,
                textStyle: theme.textTheme.labelLarge!.copyWith(
                  color: scheme.primary,
                ),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                alignment: Alignment.center,
              ),
              child: Text(
                l10n.postUpdateCTA,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            )
          : null;
      final forward = onForward != null
          ? OutlinedButton.icon(
              onPressed: onForward,
              icon: const Icon(Icons.send, size: 18),
              label: Text(
                l10n.labelForward,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.primary,
                textStyle: theme.textTheme.labelLarge!.copyWith(
                  color: scheme.primary,
                ),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                alignment: Alignment.center,
              ),
            )
          : null;

      if (primary == null && secondary == null && forward == null) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.only(top: kSpacingSmall),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              // [SliverToBoxAdapter] can pass unbounded max height; [stretch] needs a
              // finite cross-axis extent and throws (beacon view scroll body).
              children: [
                if (primary != null) ...[
                  Expanded(
                    flex: secondary != null ? 5 : 1,
                    child: primary,
                  ),
                ],
                if (primary != null && secondary != null)
                  const SizedBox(width: kSpacingSmall),
                if (secondary != null) ...[
                  Expanded(
                    flex: primary != null ? 4 : 1,
                    child: secondary,
                  ),
                ],
              ],
            ),
            if (forward != null) ...[
              const SizedBox(height: kSpacingSmall),
              Align(
                alignment: Alignment.centerLeft,
                child: forward,
              ),
            ],
          ],
        ),
      );
    }

    final canCommit =
        !state.isCommitted && beacon.allowsNewCommitAsNonAuthor;
    final showCommit = canCommit && onCommit != null;
    final showForward = onForward != null;
    final showViewChain = onViewChain != null;

    if (!showForward && !showCommit && !showViewChain) {
      return const SizedBox.shrink();
    }

    if (showForward) {
      return Padding(
        padding: const EdgeInsets.only(top: kSpacingSmall),
        child: CardTriageActionRow(
          onCommit: showCommit ? onCommit : null,
          onForward: onForward!,
          secondaryIcon: showViewChain ? TenturaIcons.graph : null,
          secondaryTooltip: showViewChain ? l10n.beaconCtaViewChain : null,
          onSecondary: showViewChain
              ? () async {
                  onViewChain!();
                }
              : null,
        ),
      );
    }

    if (!showViewChain) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: kSpacingSmall),
      child: Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          onPressed: onViewChain,
          icon: const Icon(TenturaIcons.graph, size: 22),
          style: IconButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(8),
            minimumSize: const Size(44, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          tooltip: l10n.beaconCtaViewChain,
        ),
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
