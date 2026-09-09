import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// Author-only discoverability toggle with a plain reach statement (§8.5).
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
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: Semantics(
        identifier: TestIds.requestDiscoverableToggle,
        toggled: isDiscoverable,
        child: SwitchListTile.adaptive(
          key: TestIds.key(TestIds.requestDiscoverableToggle),
          contentPadding: EdgeInsets.symmetric(horizontal: tt.cardPadding.left),
          title: Text(l10n.requestDiscoverableLabel),
          subtitle: Text(
            l10n.requestDiscoverableHint,
            style: TenturaText.bodySmall(scheme.onSurfaceVariant),
          ),
          value: isDiscoverable,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
