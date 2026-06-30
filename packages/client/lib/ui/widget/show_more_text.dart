import 'package:flutter/material.dart';
import 'package:readmore/readmore.dart';

import 'package:tentura/consts.dart';

class ShowMoreText extends ReadMoreText {
  static TextStyle buildTextStyle(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return TextStyle(
      color: textTheme.bodyMedium?.color,
      fontSize: textTheme.bodyMedium?.fontSize,
      fontFamily: textTheme.bodyMedium?.fontFamily,
      fontWeight: textTheme.bodyMedium?.fontWeight,
    );
  }

  ShowMoreText(
    super.data, {
    super.key,
    TextStyle? style,
    super.colorClickableText,
    super.annotations,
    super.trimCollapsedText,
    super.trimExpandedText,
    super.trimLines = kMaxLines,
    super.trimMode = TrimMode.Line,
    super.textAlign = TextAlign.left,
  }) : super(
          // readmore only merges [style] when inherit is true.
          style: style?.copyWith(inherit: true),
        );
}
