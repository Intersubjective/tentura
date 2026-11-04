import 'package:flutter/material.dart';
import 'package:readmore/readmore.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class ShowMoreText extends StatelessWidget {
  static const String _noBreakSpace = '\u00A0';

  /// Leading separator and word-internal no-break spaces for the expanded trim link.
  static String formatExpandedTrimText(String trimText) {
    final words = trimText.replaceAll(' ', _noBreakSpace);
    return '$_noBreakSpace$words';
  }

  static TextStyle buildTextStyle(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return TextStyle(
      color: textTheme.bodyMedium?.color,
      fontSize: textTheme.bodyMedium?.fontSize,
      fontFamily: textTheme.bodyMedium?.fontFamily,
      fontWeight: textTheme.bodyMedium?.fontWeight,
    );
  }

  const ShowMoreText(
    this.data, {
    super.key,
    this.style,
    this.colorClickableText,
    this.annotations,
    this.trimCollapsedText,
    this.trimExpandedText,
    this.trimLines = kMaxLines,
    this.trimMode = TrimMode.Line,
    this.textAlign = TextAlign.left,
  });

  final String data;
  final TextStyle? style;
  final Color? colorClickableText;
  final List<Annotation>? annotations;
  final String? trimCollapsedText;
  final String? trimExpandedText;
  final int trimLines;
  final TrimMode trimMode;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final expandedTrim =
        trimExpandedText ?? L10n.of(context)!.beaconShowcaseShowLess;
    return ReadMoreText(
      data,
      // readmore only merges [style] when inherit is true.
      style: style?.copyWith(inherit: true),
      colorClickableText: colorClickableText,
      annotations: annotations,
      trimCollapsedText:
          trimCollapsedText ?? L10n.of(context)!.beaconShowcaseReadMore,
      trimExpandedText: formatExpandedTrimText(expandedTrim),
      trimLines: trimLines,
      trimMode: trimMode,
      textAlign: textAlign,
    );
  }
}
