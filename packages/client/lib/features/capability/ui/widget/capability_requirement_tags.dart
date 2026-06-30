import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Resolves known [CapabilityTag]s from beacon needs slugs, sorted by slug.
List<CapabilityTag> resolveCapabilityRequirementTags(Iterable<String> slugs) {
  final tags = <CapabilityTag>[];
  for (final slug in slugs) {
    final tag = CapabilityTag.fromSlug(slug.trim());
    if (tag != null) {
      tags.add(tag);
    }
  }
  tags.sort((a, b) => a.slug.compareTo(b.slug));
  return tags;
}

/// Read-only capability requirements: inline icon + muted label (no pill/chip).
class CapabilityRequirementTags extends StatelessWidget {
  const CapabilityRequirementTags({
    required this.tags,
    this.showHeading = true,
    this.labelStyle,
    super.key,
  });

  factory CapabilityRequirementTags.fromSlugs({
    required Iterable<String> slugs,
    bool showHeading = true,
    Key? key,
  }) {
    return CapabilityRequirementTags(
      key: key,
      tags: resolveCapabilityRequirementTags(slugs),
      showHeading: showHeading,
    );
  }

  final List<CapabilityTag> tags;
  final bool showHeading;
  final TextStyle? labelStyle;

  static const double _iconSize = 18;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = this.labelStyle ?? TenturaText.bodySmall(tt.textMuted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeading) ...[
          Text(
            l10n.beaconRequirementsSubheading,
            style: TenturaText.typeLabel(scheme.onSurface),
          ),
          SizedBox(height: tt.tightGap),
        ],
        Wrap(
          spacing: TenturaSpacing.iconText,
          runSpacing: TenturaSpacing.tight,
          children: [
            for (final tag in tags)
              _CapabilityRequirementTagRow(
                tag: tag,
                label: tag.labelOf(l10n),
                labelStyle: labelStyle,
                iconColor: tt.textMuted,
                iconTextGap: tt.iconTextGap,
              ),
          ],
        ),
      ],
    );
  }
}

class _CapabilityRequirementTagRow extends StatelessWidget {
  const _CapabilityRequirementTagRow({
    required this.tag,
    required this.label,
    required this.labelStyle,
    required this.iconColor,
    required this.iconTextGap,
  });

  final CapabilityTag tag;
  final String label;
  final TextStyle labelStyle;
  final Color iconColor;
  final double iconTextGap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tag.icon, size: CapabilityRequirementTags._iconSize, color: iconColor),
          SizedBox(width: iconTextGap),
          Text(label, style: labelStyle),
        ],
      ),
    );
  }
}
