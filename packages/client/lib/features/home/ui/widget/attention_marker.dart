import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Compact, accessible marker for unread activity on a Request card.
class AttentionMarker extends StatelessWidget {
  const AttentionMarker({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    return Semantics(
      label: l10n.newStuffBadge,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: tt.rowGap, color: scheme.primary),
            SizedBox(width: tt.iconTextGap),
            Text(
              l10n.newStuffBadge,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}
