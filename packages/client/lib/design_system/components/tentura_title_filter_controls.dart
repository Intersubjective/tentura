import 'package:flutter/material.dart';

import '../tentura_text.dart';
import '../tentura_tokens.dart';
import 'tentura_top_bar_control.dart';

/// A title followed by a filter and an optional trailing control. When space
/// runs out, the trailing control collapses first, then the filter; their
/// labels remain available in tooltips.
class TenturaTitleFilterControls extends StatelessWidget {
  const TenturaTitleFilterControls({
    required this.title,
    required this.filterLabel,
    required this.filterTooltip,
    required this.onFilterPressed,
    this.trailingControl,
    super.key,
  });

  final String title;
  final String filterLabel;
  final String filterTooltip;
  final VoidCallback onFilterPressed;
  final ({String label, Widget Function(bool collapsed) builder})?
  trailingControl;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final tt = context.tt;
      final titleStyle = TenturaText.titleLarge(
        Theme.of(context).colorScheme.onSurface,
      );
      final titleWidth =
          TenturaTopBarControl.textWidth(context, title, titleStyle) +
          tt.iconTextGap;
      final filterWidth = TenturaTopBarControl.expandedWidth(
        context,
        filterLabel,
      );
      final trailing = trailingControl;
      final trailingWidth = trailing == null
          ? 0.0
          : TenturaTopBarControl.expandedWidth(context, trailing.label);
      final iconWidth = TenturaTopBarControl.collapsedWidth(context);
      final collapseTrailing =
          trailing != null &&
          titleWidth + filterWidth + trailingWidth > constraints.maxWidth;
      final collapseFilter =
          titleWidth +
              filterWidth +
              (collapseTrailing ? iconWidth : trailingWidth) >
          constraints.maxWidth;
      return Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                SizedBox(width: tt.iconTextGap),
                Flexible(
                  child: TenturaTopBarControl(
                    label: filterLabel,
                    icon: Icons.filter_list,
                    trailingIcon: Icons.arrow_drop_down,
                    tooltip: filterTooltip,
                    collapsed: collapseFilter,
                    onPressed: onFilterPressed,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing.builder(collapseTrailing),
        ],
      );
    },
  );
}
