import 'package:flutter/material.dart';

import '../tentura_text.dart';
import '../tentura_tokens.dart';

/// Muted metadata line (timestamps, middots) — `bodySmall` Inter, muted token.
class TenturaMetaText extends StatelessWidget {
  const TenturaMetaText(
    this.text, {
    super.key,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;
  final int maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      style: TenturaText.bodySmall(context.tt.textMuted),
    );
  }
}
