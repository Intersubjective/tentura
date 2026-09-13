import 'package:flutter/material.dart';

import '../tentura_text.dart';
import '../tentura_tokens.dart';

/// Bounded “open the full list” summary row (Activity triage, collapsed prompts, …).
class TenturaAttentionSummaryRow extends StatelessWidget {
  const TenturaAttentionSummaryRow({
    required this.label,
    required this.onTap,
    required this.semanticsLabel,
    this.leading,
    this.maxLines = 1,
    this.showChevron = true,
    this.inkWellKey,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final String semanticsLabel;
  final Widget? leading;
  final int maxLines;
  final bool showChevron;
  final Key? inkWellKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(tt.cardRadius),
        child: InkWell(
          key: inkWellKey,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          onTap: onTap,
          child: SizedBox(
            height: tt.buttonHeight + tt.tightGap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tt.rowGap),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    SizedBox(width: tt.tightGap * 2),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TenturaText.titleSmall(scheme.onSurface),
                    ),
                  ),
                  if (showChevron)
                    Icon(
                      Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                      size: tt.iconSize,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
