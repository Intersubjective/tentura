import 'package:flutter/material.dart';
import 'package:readmore/readmore.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class ShowMoreText extends StatelessWidget {
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
    return ReadMoreText(
      data,
      // readmore only merges [style] when inherit is true.
      style: style?.copyWith(inherit: true),
      colorClickableText: colorClickableText,
      annotations: annotations,
      trimCollapsedText:
          trimCollapsedText ?? L10n.of(context)!.beaconShowcaseReadMore,
      trimExpandedText:
          trimExpandedText ?? L10n.of(context)!.beaconShowcaseShowLess,
      trimLines: trimLines,
      trimMode: trimMode,
      textAlign: textAlign,
    );
  }
}
