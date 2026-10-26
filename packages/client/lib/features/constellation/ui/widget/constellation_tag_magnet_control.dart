import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// One magnet action, reachable by button, touch hold or secondary click.
/// A held source can also be dragged; releasing it without moving opens its
/// menu instead, so the hold menu does not steal a drag in progress.
class ConstellationTagMagnetControl extends StatefulWidget {
  const ConstellationTagMagnetControl({
    required this.child,
    required this.actionLabel,
    required this.onAction,
    this.onDrop,
    super.key,
  });

  final Widget child;
  final String actionLabel;
  final VoidCallback onAction;
  final ValueChanged<Offset>? onDrop;

  @override
  State<ConstellationTagMagnetControl> createState() =>
      _ConstellationTagMagnetControlState();
}

class _ConstellationTagMagnetControlState
    extends State<ConstellationTagMagnetControl> {
  Offset? _start;

  Future<void> _menu(Offset at) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(at);
    final selected = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(local.dx, local.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: true, child: Text(widget.actionLabel)),
      ],
    );
    if (selected == true && mounted) widget.onAction();
  }

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.child,
        IconButton(
          tooltip: widget.actionLabel,
          icon: const Icon(Icons.more_vert),
          onPressed: () {
            final box = context.findRenderObject()! as RenderBox;
            unawaited(_menu(box.localToGlobal(box.size.center(Offset.zero))));
          },
        ),
      ],
    );
    final onDrop = widget.onDrop;
    return Listener(
      onPointerDown: (event) => _start = event.position,
      child: GestureDetector(
        onSecondaryTapUp: (details) => unawaited(_menu(details.globalPosition)),
        onLongPressStart: onDrop == null
            ? (details) => unawaited(_menu(details.globalPosition))
            : null,
        child: onDrop == null
            ? content
            : LongPressDraggable<bool>(
                data: true,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: Material(child: widget.child),
                onDragEnd: (details) {
                  if (_start == null) return;
                  if ((details.offset - _start!).distance <= kTouchSlop) {
                    unawaited(_menu(details.offset));
                  } else {
                    onDrop(details.offset);
                  }
                  _start = null;
                },
                child: content,
              ),
      ),
    );
  }
}
