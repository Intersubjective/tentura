import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

/// Compact privacy hint with (i) button that opens the full explanation.
class EvaluationPrivacyInfoRow extends StatelessWidget {
  const EvaluationPrivacyInfoRow({
    required this.shortLabel,
    required this.fullText,
    super.key,
  });

  final String shortLabel;
  final String fullText;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final textStyle = theme.textTheme.bodySmall?.copyWith(color: muted);

    return Row(
      children: [
        Icon(Icons.lock_outline, size: 14, color: muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(shortLabel, style: textStyle),
        ),
        IconButton(
          tooltip: fullText,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                content: Text(fullText),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l10n.buttonDismiss),
                  ),
                ],
              ),
            );
          },
          icon: Icon(Icons.info_outline, size: 18, color: muted),
        ),
      ],
    );
  }
}
