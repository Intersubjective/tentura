import 'package:flutter/material.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../tentura_spacing.dart';
import '../tentura_tokens.dart';

/// Vertical splitter: 1 px hairline with a wider drag hit target.
///
/// Dragging left/right reports [onDragDelta] as the horizontal pointer delta
/// (positive = pointer moved right). Caller owns clamp/layout.
class TenturaVerticalResizeHandle extends StatefulWidget {
  const TenturaVerticalResizeHandle({
    required this.onDragDelta,
    this.subtle = true,
    this.semanticLabel,
    super.key,
  });

  /// Horizontal pointer delta for this drag update (logical px).
  final ValueChanged<double> onDragDelta;

  final bool subtle;

  /// Screen-reader name; null reads the app-language default (#670).
  final String? semanticLabel;

  @override
  State<TenturaVerticalResizeHandle> createState() =>
      _TenturaVerticalResizeHandleState();
}

class _TenturaVerticalResizeHandleState
    extends State<TenturaVerticalResizeHandle> {
  bool _dragging = false;
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final hitWidth = TenturaSpacing.row;
    final active = _dragging || _hovering;
    final color = active
        ? tt.border
        : (widget.subtle ? tt.borderSubtle : tt.border);

    return Semantics(
      label:
          widget.semanticLabel ??
          L10n.of(context)?.paneResizeHandleSemantics ??
          'Resize panes',
      slider: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (details) {
            widget.onDragDelta(details.delta.dx);
          },
          onHorizontalDragEnd: (_) => setState(() => _dragging = false),
          onHorizontalDragCancel: () => setState(() => _dragging = false),
          child: SizedBox(
            width: hitWidth,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                width: _dragging ? 2 : 1,
                height: double.infinity,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
