import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

typedef _MyWorkNavBadgeView = ({
  int obligationCount,
  bool showObligationBadge,
  bool showUnreadDot,
});

/// My Work tab icon: live-obligation count **and** unread dot.
///
/// R7 — this used to `return` as soon as it had a number to show, so a
/// Request with both indicators lit only one of them on the tab above it.
/// `docs/features/request-attention.md` §6 and design-plan D09 both say the
/// two are independent and appear together; the same rule already holds one
/// level down in `RequestAttentionIndicators`, and a tab that disagreed with
/// the cards under it is the M1 failure in miniature.
///
/// The two slots are placed apart rather than stacked: the number keeps the
/// conventional trailing corner, the dot takes the leading one.
class MyWorkNavbarItem extends StatelessWidget {
  const MyWorkNavbarItem({super.key, this.selected = false});

  static const dotKey = ValueKey('my-work-nav-dot');
  static const countKey = ValueKey('my-work-nav-count');

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocSelector<HomeAttentionCubit, HomeAttentionState, _MyWorkNavBadgeView>(
      selector: (state) => (
        obligationCount: state.surfaceMyDeskCount,
        showObligationBadge: state.showRedesignMyWorkObligationBadge,
        showUnreadDot: state.showRedesignMyWorkUnreadDot,
      ),
      builder: (context, view) {
        final scheme = Theme.of(context).colorScheme;
        final count = view.obligationCount;
        Widget badged = Icon(selected ? Icons.work : Icons.work_outline);

        if (view.showUnreadDot) {
          badged = Badge(
            key: dotKey,
            alignment: AlignmentDirectional.topStart,
            isLabelVisible: true,
            backgroundColor: scheme.primary,
            child: badged,
          );
        }
        if (view.showObligationBadge) {
          badged = Badge(
            key: countKey,
            label: Text('$count'),
            isLabelVisible: true,
            backgroundColor: selected ? scheme.onPrimary : scheme.primary,
            textColor: selected ? scheme.primary : scheme.onPrimary,
            child: badged,
          );
        }
        if (!view.showUnreadDot && !view.showObligationBadge) {
          return badged;
        }

        return Semantics(
          label: [
            if (view.showObligationBadge) l10n.myWorkNavBadgeObligations(count),
            if (view.showUnreadDot) l10n.activityNavBadgeNewActivity,
          ].join(', '),
          identifier: view.showUnreadDot ? 'my-work-surface-unread-dot' : null,
          excludeSemantics: true,
          child: badged,
        );
      },
    );
  }
}
