import 'package:flutter/material.dart';

import '../tentura_text.dart';
import '../tentura_tokens.dart';
import '../tentura_tone.dart';

/// Resolves a semantic [TenturaTone] to a theme token color.
Color tenturaToneColor(TenturaTokens tt, TenturaTone tone) => switch (tone) {
      TenturaTone.neutral => tt.textMuted,
      TenturaTone.info => tt.info,
      TenturaTone.good => tt.good,
      TenturaTone.warn => tt.warn,
      TenturaTone.danger => tt.danger,
    };

/// Colored status line: compact sans (see [TenturaText.status]), no Container/Chip.
class TenturaStatusText extends StatelessWidget {
  const TenturaStatusText(
    this.text, {
    super.key,
    this.tone = TenturaTone.neutral,
    this.maxLines = 1,
    this.textAlign,
    this.overflow = TextOverflow.ellipsis,
    this.softWrap = true,
  });

  final String text;
  final TenturaTone tone;

  /// When null, the line wraps freely (list cards). App bars keep [maxLines] = 1.
  final int? maxLines;
  final TextAlign? textAlign;
  final TextOverflow overflow;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      textAlign: textAlign,
      style: TenturaText.status(tenturaToneColor(tt, tone)),
    );
  }
}

/// Dual-slot operational STATUS (`slot1 · slot2`) with independent tones.
class TenturaStatusLine extends StatelessWidget {
  const TenturaStatusLine({
    required this.slot1,
    this.slot2,
    required this.slot1Tone,
    this.slot2Tone,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.softWrap = true,
    super.key,
  });

  final String slot1;
  final String? slot2;
  final TenturaTone slot1Tone;
  final TenturaTone? slot2Tone;
  final int? maxLines;
  final TextOverflow overflow;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final s2 = slot2?.trim() ?? '';
    if (s2.isEmpty) {
      return TenturaStatusText(
        slot1,
        tone: slot1Tone,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
      );
    }

    final baseStyle = TenturaText.status(tenturaToneColor(tt, slot1Tone));
    final s2Tone = slot2Tone ?? TenturaTone.neutral;
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: slot1),
          TextSpan(
            text: ' · ',
            style: TenturaText.status(tenturaToneColor(tt, TenturaTone.neutral)),
          ),
          TextSpan(
            text: s2,
            style: TenturaText.status(tenturaToneColor(tt, s2Tone)),
          ),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    );
  }
}
