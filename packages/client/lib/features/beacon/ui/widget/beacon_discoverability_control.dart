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

    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            identifier: TestIds.requestDiscoverableToggle,
            toggled: isDiscoverable,
            child: SwitchListTile.adaptive(
              key: TestIds.key(TestIds.requestDiscoverableToggle),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: tt.cardPadding.left),
              title: Text(l10n.requestDiscoverableLabel),
              subtitle: Text(current, style: explanationStyle),
              value: isDiscoverable,
              onChanged: onChanged,
            ),
          ),
          Padding(
            padding: tt.cardPadding.copyWith(top: 0),
            child: Text(alternative, style: explanationStyle),
          ),
        ],
      ),
    );
  }
}
