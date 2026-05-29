import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

/// HUD row: fixed-width label column + multiline body (+ optional edit).
class HudLabeledMultiline extends StatelessWidget {
  const HudLabeledMultiline({
    required this.label,
    required this.text,
    required this.mutedColor,
    this.subline,
    this.isPlaceholder = false,
    this.onEdit,
    this.editSemanticLabel,
    this.onShowDetail,
    this.showDetailSemanticLabel,
    super.key,
  });

  final String label;
  final String text;
  final String? subline;
  final Color mutedColor;
  final bool isPlaceholder;
  final VoidCallback? onEdit;
  final String? editSemanticLabel;
  final VoidCallback? onShowDetail;
  final String? showDetailSemanticLabel;

  static const int _primaryMaxLines = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context)!;
    final textColor =
        isPlaceholder ? scheme.onSurfaceVariant : scheme.onSurface;
    final semanticsText = subline == null ? text : '$text\n$subline';
    final primaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: textColor,
      height: 1.25,
    );
    final showMoreStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.primary,
      height: 1.25,
    );

    Widget buildPrimaryContent(double maxWidth) {
      final exceeds = _textExceedsMaxLines(
        text: text,
        style: primaryStyle,
        maxWidth: maxWidth,
        maxLines: _primaryMaxLines,
      );

      final primaryColumn = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            maxLines: _primaryMaxLines,
            overflow: TextOverflow.ellipsis,
            style: primaryStyle,
          ),
          if (exceeds) ...[
            const SizedBox(height: 2),
            Text(l10n.itemShowMore, style: showMoreStyle),
          ],
        ],
      );

      if (onShowDetail == null) {
        return primaryColumn;
      }

      return Semantics(
        button: true,
        label: showDetailSemanticLabel ?? '$label $semanticsText',
        child: InkWell(
          onTap: onShowDetail,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: primaryColumn,
          ),
        ),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) =>
              buildPrimaryContent(constraints.maxWidth),
        ),
        if (subline != null) ...[
          const SizedBox(height: 2),
          Text(
            subline!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.error,
              height: 1.25,
            ),
          ),
        ],
      ],
    );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: mutedColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(child: content),
        if (onEdit != null) ...[
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: editSemanticLabel,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: Icon(
                Icons.edit_outlined,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              onPressed: onEdit,
            ),
          ),
        ],
      ],
    );

    return Semantics(
      label: '$label $semanticsText',
      child: ExcludeSemantics(child: row),
    );
  }

  static bool _textExceedsMaxLines({
    required String text,
    required TextStyle? style,
    required double maxWidth,
    required int maxLines,
  }) {
    if (maxWidth <= 0 || text.isEmpty) return false;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }
}
