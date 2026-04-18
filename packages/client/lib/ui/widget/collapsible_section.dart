import 'package:flutter/material.dart';

import 'package:tentura/ui/utils/ui_utils.dart';

/// Compact expansion section for mobile (wraps [ExpansionTile]).
class CollapsibleSection extends StatelessWidget {
  const CollapsibleSection({
    required this.title,
    required this.child,
    this.initiallyExpanded = true,
    this.badge,
    super.key,
  });

  final String title;

  final Widget child;

  final bool initiallyExpanded;

  /// Optional trailing count or label (e.g. update count).
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: kSpacingSmall),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        maintainState: true,
        initiallyExpanded: initiallyExpanded,
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (badge != null && badge!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: kSpacingSmall),
                child: Text(
                  badge!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
        childrenPadding: kPaddingSmallH.add(
          const EdgeInsets.only(bottom: kSpacingSmall),
        ),
        children: [child],
      ),
    );
  }
}
