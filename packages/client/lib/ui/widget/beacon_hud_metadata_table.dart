import 'package:flutter/material.dart';

import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

/// One row in [BeaconHudMetadataTable]: lead icon metadata + body (+ optional trailing).
@immutable
class BeaconHudMetadataEntry {
  const BeaconHudMetadataEntry({
    required this.icon,
    required this.semanticsLabel,
    required this.body,
    this.onTap,
    this.trailing,
    this.semanticsValue,
  });

  final IconData icon;
  final String semanticsLabel;
  final Widget body;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Combined label for tappable rows (a11y button on icon+body region).
  final String? semanticsValue;
}

/// Resolves the width used for responsive metadata decisions (YOU collapse, etc.).
///
/// Prefer [BoxConstraints.maxWidth] from [LayoutBuilder]; fall back to window
/// width when the parent passes unbounded horizontal constraints.
double beaconHudMetadataRowWidth(
  BoxConstraints constraints,
  BuildContext context,
) {
  final width = constraints.maxWidth;
  if (width.isFinite && width > 0) {
    return width;
  }
  return MediaQuery.sizeOf(context).width;
}

/// Two-column metadata block: fixed 32px centered icon column + expanded body.
///
/// Pass [buildEntries] so row visibility uses the same allocated width as layout.
class BeaconHudMetadataTable extends StatelessWidget {
  const BeaconHudMetadataTable({
    required this.buildEntries,
    super.key,
  });

  final List<BeaconHudMetadataEntry> Function(double rowWidth) buildEntries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowWidth = beaconHudMetadataRowWidth(constraints, context);
        final entries = buildEntries(rowWidth);
        if (entries.isEmpty) {
          return const SizedBox.shrink();
        }

        final scheme = Theme.of(context).colorScheme;
        final rows = <Widget>[];

        for (var i = 0; i < entries.length; i++) {
          if (i > 0) {
            rows.add(const SizedBox(height: kBeaconHudRowGap));
          }
          rows.add(_MetadataTableRow(
            entry: entries[i],
            iconColor: scheme.onSurfaceVariant,
          ));
        }

        return ClipRect(
          clipBehavior: Clip.none,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: rows,
          ),
        );
      },
    );
  }
}

class _MetadataTableRow extends StatelessWidget {
  const _MetadataTableRow({
    required this.entry,
    required this.iconColor,
  });

  final BeaconHudMetadataEntry entry;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final iconColumn = SizedBox(
      width: kBeaconHudRowLeadWidth,
      child: Center(
        child: ExcludeSemantics(
          excluding: entry.onTap != null,
          child: Semantics(
            label: entry.semanticsLabel,
            child: Icon(
              entry.icon,
              size: kBeaconHudRowIconSize,
              color: iconColor,
            ),
          ),
        ),
      ),
    );

    final bodyContent = Align(
      alignment: Alignment.centerLeft,
      child: ClipRect(
        clipBehavior: Clip.none,
        child: entry.body,
      ),
    );

    final trailing = entry.trailing;

    if (entry.onTap != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: Semantics(
                button: true,
                label: entry.semanticsValue ?? entry.semanticsLabel,
                child: InkWell(
                  onTap: entry.onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        iconColumn,
                        Expanded(child: bodyContent),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      );
    }

    return ClipRect(
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          iconColumn,
          Expanded(child: bodyContent),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}
