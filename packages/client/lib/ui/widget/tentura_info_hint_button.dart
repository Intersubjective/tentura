import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Compact (i) button that opens [fullText] in a dismissible dialog.
class TenturaInfoHintButton extends StatelessWidget {
  const TenturaInfoHintButton({
    required this.fullText,
    this.semanticsLabel,
    super.key,
  });

  final String fullText;

  /// Screen reader label; defaults to [fullText].
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final muted = tt.textMuted;
    final label = semanticsLabel ?? fullText;

    return Semantics(
      button: true,
      label: label,
      child: IconButton(
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
    );
  }
}
