import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/constellation_cubit.dart';

/// Map chrome while the forward-help tree overlay is active (#774 31ve.6).
class ConstellationForwardTreeOverlayBar extends StatelessWidget {
  const ConstellationForwardTreeOverlayBar({
    required this.cubit,
    super.key,
  });

  final ConstellationCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    return BlocBuilder<ConstellationCubit, ConstellationState>(
      bloc: cubit,
      buildWhen: (p, c) => p.forwardTreeOverlay != c.forwardTreeOverlay,
      builder: (context, state) {
        final overlay = state.forwardTreeOverlay;
        if (overlay == null) return const SizedBox.shrink();
        return Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          color: theme.colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tt.tightGap,
              vertical: tt.tightGap / 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('constellation.forward_tree.close'),
                  tooltip: l10n.constellationForwardTreeClose,
                  onPressed: cubit.exitForwardTreeMode,
                  icon: const Icon(Icons.close),
                ),
                if (!overlay.reduceMotion)
                  TextButton.icon(
                    key: const Key('constellation.forward_tree.replay'),
                    onPressed: cubit.replayForwardTree,
                    icon: const Icon(Icons.replay_outlined),
                    label: Text(l10n.constellationForwardTreeReplay),
                  ),
                TextButton(
                  key: const Key('constellation.forward_tree.arrange'),
                  onPressed: cubit.toggleForwardTreeArrange,
                  child: Text(
                    overlay.arrangeAsTree
                        ? l10n.constellationForwardTreeRestoreLayout
                        : l10n.constellationForwardTreeArrangeAsTree,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
