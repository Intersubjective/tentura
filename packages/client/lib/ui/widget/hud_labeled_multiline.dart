import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
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
  static const double _labelColumnWidth = 44;
  static const double _editColumnWidth = 40;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context)!;
    final textColor =
        isPlaceholder ? scheme.onSurfaceVariant : scheme.onSurface;
    final semanticsText = subline == null ? text : '$text\n$subline';
    final labelStyle = TenturaText.typeLabel(mutedColor);
    final primaryStyle = TenturaText.bodySmall(textColor).copyWith(height: 1.25);
    final showMoreStyle = TenturaText.bodySmall(scheme.primary).copyWith(
      height: 1.25,
    );

    Widget buildLabelAndBody(double bodyMaxWidth) {
      final exceeds = _textExceedsMaxLines(
        text: text,
        style: primaryStyle,
        maxWidth: bodyMaxWidth,
        maxLines: _primaryMaxLines,
      );

      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: _labelColumnWidth,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
          ),
          Expanded(
            child: Column(
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
                if (subline != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subline!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.bodySmall(scheme.error).copyWith(
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final editReserved = onEdit != null ? _editColumnWidth : 0.0;
        final bodyMaxWidth =
            constraints.maxWidth - _labelColumnWidth - editReserved;

        final labelAndBody = buildLabelAndBody(bodyMaxWidth);

        final detailTarget = onShowDetail == null
            ? labelAndBody
            : Semantics(
                button: true,
                label: showDetailSemanticLabel ?? '$label $semanticsText',
                child: InkWell(
                  onTap: onShowDetail,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: labelAndBody,
                  ),
                ),
              );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: detailTarget),
            if (onEdit != null) ...[
              const SizedBox(width: 4),
              Semantics(
                button: true,
                label: editSemanticLabel,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
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
      },
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
