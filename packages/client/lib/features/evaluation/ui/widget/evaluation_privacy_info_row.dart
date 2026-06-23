import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final tt = context.tt;
    final textStyle = TenturaText.bodySmall(muted);

    return Row(
      children: [
        Icon(Icons.lock_outline, size: tt.iconSize * 0.65, color: muted),
        SizedBox(width: tt.iconTextGap),
        Expanded(
          child: Text(shortLabel, style: textStyle),
        ),
        IconButton(
          tooltip: fullText,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(
            minWidth: tt.buttonHeight,
            minHeight: tt.buttonHeight,
          ),
          onPressed: () {
            unawaited(
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
              ),
            );
          },
          icon: Icon(Icons.info_outline, size: tt.iconSize * 0.85, color: muted),
        ),
      ],
    );
  }
}
