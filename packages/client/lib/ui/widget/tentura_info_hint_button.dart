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

    void open() {
      unawaited(
        showDialog<void>(
          context: context,
          builder: (ctx) {
            final dialogTt = ctx.tt;
            return AlertDialog(
              constraints: BoxConstraints(
                maxWidth: dialogTt.contentMaxWidth ?? 560,
              ),
              content: SingleChildScrollView(
                child: Text(
                  fullText,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.buttonDismiss),
                ),
              ],
            );
          },
        ),
      );
    }

    // Its own node (container), with the IconButton's node folded in: a
    // non-container `button` wrapper merged up into the nearest ancestor
    // node and turned the whole surrounding area (e.g. a sheet's scroll
    // view) into one button, hiding its contents from web a11y (#360).
    return Semantics(
      container: true,
      button: true,
      focusable: true,
      label: label,
      onTap: open,
      excludeSemantics: true,
      child: IconButton(
        tooltip: fullText,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(
          minWidth: tt.buttonHeight,
          minHeight: tt.buttonHeight,
        ),
        onPressed: open,
        icon: Icon(Icons.info_outline, size: tt.iconSize * 0.85, color: muted),
      ),
    );
  }
}
