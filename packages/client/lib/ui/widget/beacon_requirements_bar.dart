import 'dart:math' show min;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Read-only row of capability icons for [needs] slugs (comma-split beacon field).
///
/// Shows up to [maxIcons] icons; remaining count is shown as `+N`.
/// Unknown slugs are skipped (no placeholder).
class BeaconRequirementsBar extends StatelessWidget {
  const BeaconRequirementsBar({
    required this.needs,
    this.maxIcons = 5,
    this.leadingLabel,
    this.inline = false,
    super.key,
  });

  final Set<String> needs;

  /// Maximum icons to render before `+N` overflow text.
  final int maxIcons;

  /// Optional prefix (e.g. l10n beaconForwardRequirementsHint) before icons.
  final String? leadingLabel;

  /// Single-line row for embedding in a tight horizontal layout (no [Wrap]).
  final bool inline;

  @override
  Widget build(BuildContext context) {
    if (needs.isEmpty) {
      return const SizedBox.shrink();
    }

    final tt = context.tt;
    final tags = <CapabilityTag>[];
    for (final slug in needs) {
      final t = CapabilityTag.fromSlug(slug.trim());
      if (t != null) {
        tags.add(t);
      }
    }
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final effectiveMaxIcons = inline && maxIcons == 5 ? 3 : maxIcons;
    final visibleCount =
        effectiveMaxIcons < 1 ? tags.length : min(tags.length, effectiveMaxIcons);
    final overflow = tags.length - visibleCount;

    final iconChildren = <Widget>[
      for (var i = 0; i < visibleCount; i++)
        Tooltip(
          message: tags[i].labelOf(l10n),
          child: Icon(
            tags[i].icon,
            size: 22,
            color: tt.textMuted,
          ),
        ),
      if (overflow > 0)
        Text(
          '+$overflow',
          style: TenturaText.labelSmall(tt.textMuted),
        ),
    ];

    if (inline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingLabel != null && leadingLabel!.isNotEmpty) ...[
            Text(
              leadingLabel!,
              style: TenturaText.bodySmall(tt.textMuted),
            ),
            SizedBox(width: tt.iconTextGap),
          ],
          ...iconChildren,
        ],
      );
    }

    return Row(
      children: [
        if (leadingLabel != null && leadingLabel!.isNotEmpty) ...[
          Text(
            leadingLabel!,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
          SizedBox(width: tt.iconTextGap),
        ],
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: iconChildren,
          ),
        ),
      ],
    );
  }
}
