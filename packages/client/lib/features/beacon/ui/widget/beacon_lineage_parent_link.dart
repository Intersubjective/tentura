import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Clickable reference to the lineage parent beacon (no title fetch).
class BeaconLineageParentLink extends StatelessWidget {
  const BeaconLineageParentLink({
    required this.parentBeaconId,
    super.key,
  });

  final String parentBeaconId;

  @override
  Widget build(BuildContext context) {
    if (parentBeaconId.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    return Semantics(
      button: true,
      label: l10n.beaconLineageParentLinkSemantics,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () =>
              context.router.push(BeaconViewRoute(id: parentBeaconId)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tt.screenHPadding,
                vertical: tt.rowGap * 0.5,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: tt.iconSize,
                    color: tt.textMuted,
                  ),
                  SizedBox(width: tt.rowGap * 0.75),
                  Expanded(
                    child: Text(
                      l10n.beaconLineageParentLinkLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: tt.iconSize,
                    color: tt.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
