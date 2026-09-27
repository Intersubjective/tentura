import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// Author-only discoverability toggle with current-state + alternative copy.
///
/// Current state lives in [SwitchListTile.subtitle] (screen-reader merged).
/// The other state is a sibling paragraph so testers need not flip to learn it.
class BeaconDiscoverabilityControl extends StatelessWidget {
  const BeaconDiscoverabilityControl({
    required this.isAuthor,
    required this.isDiscoverable,
    required this.onChanged,
    super.key,
  });

  final bool isAuthor;
  final bool isDiscoverable;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!isAuthor) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final current = isDiscoverable
        ? l10n.requestDiscoverableOn
        : l10n.requestDiscoverableOff;
    final alternative = isDiscoverable
        ? l10n.requestDiscoverableOff
        : l10n.requestDiscoverableOn;
    final explanationStyle = TenturaText.bodySmall(tt.textMuted);
    final theme = Theme.of(context);
    // Same geometry and title scale as the Details rows above it: icon on
    // the card padding, text on one keyline, titleSmall w600.
    final textStart = tt.cardPadding.left + tt.iconSize + tt.avatarTextGap;

    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            identifier: TestIds.requestDiscoverableToggle,
            toggled: isDiscoverable,
            child: ListTileTheme.merge(
              minLeadingWidth: tt.iconSize,
              horizontalTitleGap: tt.avatarTextGap,
              // Desktop density trims the title gap by 4 dp, which moved this
              // row's text off the Details rows' keyline.
              visualDensity: VisualDensity.standard,
              child: SwitchListTile.adaptive(
                key: TestIds.key(TestIds.requestDiscoverableToggle),
                contentPadding: EdgeInsets.only(
                  left: tt.cardPadding.left,
                  right: tt.rowGap,
                ),
                minLeadingWidth: tt.iconSize,
                horizontalTitleGap: tt.avatarTextGap,
                secondary: Icon(
                  Icons.travel_explore,
                  size: tt.iconSize,
                  color: tt.textMuted,
                ),
                title: Text(
                  l10n.requestDiscoverableLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(current, style: explanationStyle),
                value: isDiscoverable,
                onChanged: onChanged,
              ),
            ),
          ),
          Padding(
            padding: tt.cardPadding.copyWith(top: 0, left: textStart),
            child: Text(alternative, style: explanationStyle),
          ),
        ],
      ),
    );
  }
}
