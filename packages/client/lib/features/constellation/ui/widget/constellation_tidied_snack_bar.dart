import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/undo_snack_bar.dart';

/// Tells how many people «Tidy up» moved and offers Undo.
void showConstellationTidiedSnackBar(
  BuildContext context, {
  required int count,
  required VoidCallback onUndo,
}) {
  showUndoSnackBar(
    context,
    text: L10n.of(context)!.constellationTidied(count),
    onUndo: onUndo,
    // The Field has just rearranged; the bar appears at once, not after it.
    animationStyle: AnimationStyle.noAnimation,
  );
}
