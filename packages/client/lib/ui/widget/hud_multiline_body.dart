import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Multiline HUD body: primary text, optional show-more hint, optional subline.
class HudMultilineBody extends StatelessWidget {
  const HudMultilineBody({
    required this.text,
    required this.mutedColor,
    this.subline,
    this.isPlaceholder = false,
    this.primaryMaxLines = defaultPrimaryMaxLines,
    this.showTruncationHint = true,
    super.key,
  });

  final String text;
  final String? subline;
  final Color mutedColor;
  final bool isPlaceholder;
  final int primaryMaxLines;
  final bool showTruncationHint;

  static const int defaultPrimaryMaxLines = 2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context)!;
    final textColor =
        isPlaceholder ? scheme.onSurfaceVariant : scheme.onSurface;
    final primaryStyle = TenturaText.hudBodySmall(textColor);
    final showMoreStyle = TenturaText.hudBodySmall(scheme.primary);

    return LayoutBuilder(
      builder: (context, constraints) {
        final exceeds = showTruncationHint &&
            HudMultilineLayout.textExceedsMaxLines(
              text: text,
              style: primaryStyle,
              maxWidth: constraints.maxWidth,
              maxLines: primaryMaxLines,
            );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              maxLines: primaryMaxLines,
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
                style: TenturaText.hudBodySmall(scheme.error),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Layout helpers shared by [HudMultilineBody] and [HudLabeledMultiline].
abstract final class HudMultilineLayout {
  static const double editColumnWidth = 40;

  static bool textExceedsMaxLines({
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

  static bool textFitsSingleLine({
    required String text,
    required TextStyle? style,
    required double maxWidth,
  }) {
    if (maxWidth <= 0 || text.isEmpty) return true;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return !painter.didExceedMaxLines;
  }
}
