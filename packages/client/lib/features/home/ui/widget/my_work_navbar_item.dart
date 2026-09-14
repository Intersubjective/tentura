import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

typedef _MyWorkNavBadgeView = ({
  int obligationCount,
  bool showObligationBadge,
  bool showUnreadDot,
});

/// My Work tab icon with live-obligation count or unread dot.
class MyWorkNavbarItem extends StatelessWidget {
  const MyWorkNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocSelector<HomeAttentionCubit, HomeAttentionState, _MyWorkNavBadgeView>(
      selector: (state) => (
        obligationCount: state.surfaceNeedsYouTotal,
        showObligationBadge: state.showRedesignMyWorkObligationBadge,
        showUnreadDot: state.showRedesignMyWorkUnreadDot,
      ),
      builder: (context, view) {
        final scheme = Theme.of(context).colorScheme;
        final icon = Icon(selected ? Icons.work : Icons.work_outline);

        if (view.showObligationBadge) {
          final count = view.obligationCount;
          final badge = Badge(
            label: Text('$count'),
            isLabelVisible: true,
            backgroundColor: selected ? scheme.onPrimary : scheme.primary,
            textColor: selected ? scheme.primary : scheme.onPrimary,
            child: icon,
          );
          return Semantics(
            label: l10n.myWorkNavBadgeObligations(count),
            excludeSemantics: true,
            child: badge,
          );
        }

        if (view.showUnreadDot) {
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
