import 'package:flutter/material.dart';

/// Shows a popup menu anchored below [anchorContext]'s render box.
///
/// Workaround: PopupMenuButton with a custom child often drops taps on Flutter
/// web (especially mobile Firefox). Prefer this helper from TextButton or
/// IconButton onPressed, or use PopupMenuButton.icon for icon-only triggers.
/// See flutter/flutter#164282 and beacon-create picker rows (InkWell).
Future<T?> showAnchoredPopupMenu<T>({
  required BuildContext anchorContext,
  required List<PopupMenuEntry<T>> items,
}) async {
  final box = anchorContext.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;

  final overlay =
      Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
  if (overlay == null) return null;

  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );

  return showMenu<T>(
    context: anchorContext,
    position: position,
    items: items,
  );
}
