import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

typedef _InboxNavBadgeView = ({
  bool showUnreadDot,
  int unreadMarkerCount,
});

/// Activity tab icon with an unread dot when off-tab receipts remain.
class InboxNavbarItem extends StatelessWidget {
  const InboxNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocSelector<HomeAttentionCubit, HomeAttentionState, _InboxNavBadgeView>(
      selector: (state) => (
        showUnreadDot: state.showRedesignActivityUnreadDot,
        unreadMarkerCount: state.inboxMarkerIds.length,
      ),
      builder: (context, view) {
        final scheme = Theme.of(context).colorScheme;
        final icon = Icon(selected ? Icons.inbox : Icons.inbox_outlined);

        if (view.showUnreadDot) {
          return Semantics(
            label: l10n.activityNavBadgeNewActivity,
            identifier: 'activity-surface-unread-dot',
            child: Badge(
              isLabelVisible: true,
              backgroundColor: scheme.primary,
              child: icon,
            ),
          );
        }

        return Semantics(
          identifier: 'activity-surface-unread-count-0',
          child: icon,
        );
      },
    );
  }
}
