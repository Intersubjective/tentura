import 'package:flutter/material.dart';

import '../tentura_text.dart';
import '../tentura_tokens.dart';

/// Bordered compact command: white bg, sky border and text, height ~40.
class TenturaCommandButton extends StatelessWidget {
  const TenturaCommandButton({
    required this.label,
    super.key,
    this.onPressed,
    this.icon,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final color = tt.info;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(
          color: selected ? color : tt.skyBorder,
          width: selected ? 2 : 1,
        ),
        foregroundColor: color,
        backgroundColor: selected ? color.withValues(alpha: 0.08) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tt.buttonRadius),
        ),
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
                Flexible(
                  child: Text(
                    label,
                    style: TenturaText.command(color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
  }
}
