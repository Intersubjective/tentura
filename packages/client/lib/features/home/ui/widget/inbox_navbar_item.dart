import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

typedef _InboxNavBadgeView = ({
  bool showTriage,
  bool showUnreadDot,
  int triageCount,
  int unreadMarkerCount,
});

/// Inbox tab icon with triage count or unread activity badge.
class InboxNavbarItem extends StatelessWidget {
  const InboxNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocSelector<HomeAttentionCubit, HomeAttentionState, _InboxNavBadgeView>(
      selector: (state) => (
        showTriage: state.showInboxTriageBadge,
        showUnreadDot: state.showInboxUnreadDot,
        triageCount: state.inboxTriageCount,
        unreadMarkerCount: state.inboxMarkerIds.length,
      ),
      builder: (context, view) {
        final scheme = Theme.of(context).colorScheme;
        final icon = Icon(selected ? Icons.inbox : Icons.inbox_outlined);

        if (view.showTriage) {
          return Semantics(
            label: l10n.activityTriageRequestsNeedResponse(view.triageCount),
            excludeSemantics: true,
            child: Badge(
              label: Text('${view.triageCount}'),
              isLabelVisible: true,
              backgroundColor: scheme.primary,
              child: icon,
            ),
          );
        }

        if (view.showUnreadDot) {
          final unread = view.unreadMarkerCount;
          return Semantics(
            label: l10n.activityNavBadgeNewActivity,
            identifier: 'updates-unread-count-$unread',
            child: Badge(
              isLabelVisible: true,
              backgroundColor: scheme.primary,
              child: icon,
            ),
          );
        }

        return Semantics(
          identifier: 'updates-unread-count-0',
          child: icon,
        );
      },
    );
  }
}
