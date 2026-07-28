import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'graph_legend_content.dart';
import 'graph_legend_mode.dart';

/// Collapsible map-style legend overlay for [GraphBody].
class GraphLegendPanel extends StatelessWidget {
  const GraphLegendPanel({
    required this.mode,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final GraphLegendMode mode;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    if (!expanded) {
      return Semantics(
        button: true,
        label: l10n.graphLegendOpen,
        child: Material(
          color: scheme.surfaceContainerHigh,
          elevation: 2,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(tt.cardRadius),
            child: SizedBox(
              width: tt.buttonHeight,
              height: tt.buttonHeight,
              child: Icon(
                Icons.map_outlined,
                semanticLabel: l10n.graphLegendOpen,
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 4,
      borderRadius: BorderRadius.circular(tt.cardRadius),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: MediaQuery.sizeOf(context).height * 0.55,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                tt.cardPadding.left,
                tt.rowGap,
                tt.tightGap,
                tt.tightGap,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.graphLegendTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.graphLegendClose,
                    onPressed: onToggle,
                    icon: const Icon(Icons.expand_more),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  tt.cardPadding.left,
                  0,
                  tt.cardPadding.right,
                  tt.cardPadding.bottom,
                ),
                child: GraphLegendContent(mode: mode),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
