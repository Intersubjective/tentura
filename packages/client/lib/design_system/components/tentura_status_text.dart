import 'package:flutter/material.dart';

import '../tentura_text.dart';
import '../tentura_tokens.dart';
import '../tentura_tone.dart';

/// Colored status line: compact sans (see [TenturaText.status]), no Container/Chip.
class TenturaStatusText extends StatelessWidget {
  const TenturaStatusText(
    this.text, {
    super.key,
    this.tone = TenturaTone.neutral,
    this.maxLines = 1,
    this.textAlign,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;
  final TenturaTone tone;
  final int maxLines;
  final TextAlign? textAlign;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final color = switch (tone) {
      TenturaTone.neutral => tt.textMuted,
      TenturaTone.info => tt.info,
      TenturaTone.good => tt.good,
      TenturaTone.warn => tt.warn,
      TenturaTone.danger => tt.danger,
    };
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: TenturaText.status(color),
    );
  }
}
