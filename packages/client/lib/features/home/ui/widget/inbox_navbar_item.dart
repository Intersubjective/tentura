import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/features/home/domain/work_activity_redesign_gate.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

typedef _InboxNavBadgeView = ({
  bool showTriage,
  bool showUnreadDot,
  bool showRedesignUnreadDot,
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
    final redesignEnabled = readWorkActivityRedesignGateEnabled();
    return BlocSelector<HomeAttentionCubit, HomeAttentionState, _InboxNavBadgeView>(
      selector: (state) => (
        showTriage: !redesignEnabled && state.showInboxTriageBadge,
        showUnreadDot: !redesignEnabled && state.showInboxUnreadDot,
        showRedesignUnreadDot:
            redesignEnabled && state.showRedesignActivityUnreadDot,
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
              backgroundColor: selected ? scheme.onPrimary : scheme.primary,
              textColor: selected ? scheme.primary : scheme.onPrimary,
              child: icon,
            ),
          );
        }

        if (view.showUnreadDot || view.showRedesignUnreadDot) {
          final unread = view.unreadMarkerCount;
          return Semantics(
            label: l10n.activityNavBadgeNewActivity,
            identifier: redesignEnabled
                ? 'activity-surface-unread-dot'
                : 'updates-unread-count-$unread',
            child: Badge(
              isLabelVisible: true,
              backgroundColor: scheme.primary,
              child: icon,
            ),
          );
        }

        return Semantics(
          identifier: redesignEnabled
              ? 'activity-surface-unread-count-0'
              : 'updates-unread-count-0',
          child: icon,
        );
      },
    );
  }
}
