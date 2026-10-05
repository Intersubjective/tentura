import 'package:flutter/material.dart';

import '../tentura_tokens.dart';
import '../tentura_text.dart';

/// A top-bar control that shows its label while there is room for it and
/// becomes an icon button when there is not — Material's rule for app-bar
/// actions: icons, with the label kept in the tooltip.
///
/// The parent bar decides [collapsed] (it knows what else must fit); use
/// [expandedWidth] to measure the labelled form.
class TenturaTopBarControl extends StatelessWidget {
  const TenturaTopBarControl({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.collapsed = false,
    this.trailingIcon,
    super.key,
  });

  /// The current value it shows, e.g. the active filter.
  final String label;

  /// The glyph standing in for the label when collapsed.
  final IconData icon;

  /// What the control does; the collapsed tooltip adds [label] to it.
  final String tooltip;

  final VoidCallback? onPressed;

  final bool collapsed;

  /// Glyph after the label in the labelled form (e.g. a dropdown arrow);
  /// defaults to [icon].
  final IconData? trailingIcon;

  static TextStyle _labelStyle(BuildContext context) => TenturaText.labelLarge(
    Theme.of(context).colorScheme.onSurfaceVariant,
  ).copyWith(fontWeight: FontWeight.w600);

  /// Width of the labelled form for [label].
  static double expandedWidth(BuildContext context, String label) {
    final tt = context.tt;
    return (textWidth(context, label, _labelStyle(context)) +
            tt.iconSize +
            tt.tightGap * 4)
        .ceilToDouble();
  }

  /// One-line width of [text] in [style] at the ambient text scale.
  static double textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Width of the collapsed (icon) form.
  static double collapsedWidth(BuildContext context) => context.tt.buttonHeight;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    if (collapsed) {
      return IconButton(
        tooltip: '$tooltip: $label',
        onPressed: onPressed,
        icon: Icon(icon, color: scheme.onSurfaceVariant),
        constraints: BoxConstraints(
          minWidth: tt.buttonHeight,
          minHeight: tt.buttonHeight,
        ),
      );
    }
    return Tooltip(
      message: tooltip,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: tt.tightGap * 2),
          minimumSize: Size(tt.buttonHeight, tt.buttonHeight),
          foregroundColor: scheme.onSurfaceVariant,
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _labelStyle(context),
              ),
            ),
            Icon(
              trailingIcon ?? icon,
              size: tt.iconSize,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
