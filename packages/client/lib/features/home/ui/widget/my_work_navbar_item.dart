import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/features/home/domain/work_activity_redesign_gate.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

typedef _MyWorkNavBadgeView = ({
  int obligationCount,
  bool showLegacyObligationBadge,
  bool showRedesignObligationBadge,
  bool showRedesignUnreadDot,
});

/// My Work tab icon with a live-obligation count badge.
class MyWorkNavbarItem extends StatelessWidget {
  const MyWorkNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final redesignEnabled = readWorkActivityRedesignGateEnabled();
    return BlocSelector<HomeAttentionCubit, HomeAttentionState, _MyWorkNavBadgeView>(
      selector: (state) {
        final obligationCount = redesignEnabled
            ? state.surfaceNeedsYouTotal
            : (state.showMyWorkObligationBadge
                  ? state.myWorkObligationCount
                  : 0);
        return (
          obligationCount: obligationCount,
          showLegacyObligationBadge:
              !redesignEnabled && state.showMyWorkObligationBadge,
          showRedesignObligationBadge:
              redesignEnabled && state.showRedesignMyWorkObligationBadge,
          showRedesignUnreadDot:
              redesignEnabled && state.showRedesignMyWorkUnreadDot,
        );
      },
      builder: (context, view) {
        final scheme = Theme.of(context).colorScheme;
        final icon = Icon(selected ? Icons.work : Icons.work_outline);

        if (view.showLegacyObligationBadge || view.showRedesignObligationBadge) {
          final count = view.obligationCount;
          final badge = Badge(
            label: Text('$count'),
            isLabelVisible: true,
            backgroundColor: selected ? scheme.onPrimary : scheme.primary,
            textColor: selected ? scheme.primary : scheme.onPrimary,
            child: icon,
          );
          if (view.showRedesignObligationBadge) {
            return Semantics(
              label: l10n.myWorkNavBadgeObligations(count),
              excludeSemantics: true,
              child: badge,
            );
          }
          return badge;
        }

        if (view.showRedesignUnreadDot) {
          return Semantics(
            label: l10n.activityNavBadgeNewActivity,
            identifier: 'my-work-surface-unread-dot',
            child: Badge(
              isLabelVisible: true,
              backgroundColor: scheme.primary,
              child: icon,
            ),
          );
        }

        return icon;
      },
    );
  }
}
