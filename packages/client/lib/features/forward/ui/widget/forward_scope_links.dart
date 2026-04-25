import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/forward_state.dart';

/// Compact `best/2  unseen/3  involved/1     MR sort` row.
class ForwardScopeLinks extends StatelessWidget {
  const ForwardScopeLinks({
    required this.activeFilter,
    required this.counts,
    required this.onScopeChanged,
    super.key,
  });

  final ForwardFilter activeFilter;
  final ForwardScopeCounts counts;
  final ValueChanged<ForwardFilter> onScopeChanged;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;

    Widget scopeLink(ForwardFilter f, String label, int count) {
      final active = f == activeFilter;
      final labelStyle = TenturaText.meta(
        active ? tt.info : tt.textMuted,
      ).copyWith(fontWeight: FontWeight.w600);
      final countStyle = TenturaText.meta(tt.textFaint);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onScopeChanged(f),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: labelStyle),
            Text('/$count', style: countStyle),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        4,
        tt.screenHPadding,
        4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                scopeLink(
                  ForwardFilter.bestNext,
                  l10n.forwardScopeBestShort,
                  counts.best,
                ),
                scopeLink(
                  ForwardFilter.unseen,
                  l10n.forwardScopeUnseenShort,
                  counts.unseen,
                ),
                scopeLink(
                  ForwardFilter.alreadyInvolved,
                  l10n.forwardScopeInvolvedShort,
                  counts.involved,
                ),
              ],
            ),
          ),
          Text(
            l10n.forwardMrSortShort,
            style: TenturaText.meta(tt.textFaint),
          ),
        ],
      ),
    );
  }
}
