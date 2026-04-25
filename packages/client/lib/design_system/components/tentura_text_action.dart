import 'package:flutter/material.dart';

import '../tentura_text.dart';
import '../tentura_tokens.dart';
import '../tentura_tone.dart';

/// Inline text action with optional leading icon; expanded tap target.
class TenturaTextAction extends StatelessWidget {
  const TenturaTextAction({
    required this.label,
    super.key,
    this.onPressed,
    this.tone = TenturaTone.info,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final TenturaTone tone;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final color = _toneToColor(tt, tone);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: color,
      ),
      child: icon == null
          ? Text(
              label,
              style: TenturaText.command(color),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(size: 14, color: color),
                  child: icon!,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TenturaText.command(color),
                ),
              ],
            ),
    );
  }

  static Color _toneToColor(TenturaTokens tt, TenturaTone tone) {
    return switch (tone) {
      TenturaTone.neutral => tt.textMuted,
      TenturaTone.info => tt.info,
      TenturaTone.good => tt.good,
      TenturaTone.warn => tt.warn,
      TenturaTone.danger => tt.danger,
    };
  }
}
