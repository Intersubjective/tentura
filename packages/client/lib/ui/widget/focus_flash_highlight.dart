import 'dart:async';

import 'package:flutter/material.dart';

/// Wraps [child] and, while [active], scrolls it into view (within the nearest
/// [Scrollable]) and plays a brief one-shot highlight flash.
///
/// Used to draw attention to a target after the user taps a Log row that points
/// at a coordination item (Items tab) or a participant (People tab).
class FocusFlashHighlight extends StatefulWidget {
  const FocusFlashHighlight({
    required this.active,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.scrollAlignment = 0.15,
    super.key,
  });

  final bool active;
  final Widget child;
  final BorderRadius borderRadius;

  /// Target alignment passed to [Scrollable.ensureVisible] (0 = top edge).
  final double scrollAlignment;

  @override
  State<FocusFlashHighlight> createState() => _FocusFlashHighlightState();
}

class _FocusFlashHighlightState extends State<FocusFlashHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _trigger());
    }
  }

  @override
  void didUpdateWidget(FocusFlashHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _trigger());
    }
  }

  void _trigger() {
    if (!mounted) return;
    final ctx = context;
    final scrollable = Scrollable.maybeOf(ctx);
    if (scrollable != null) {
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          alignment: widget.scrollAlignment,
        ),
      );
    }
    unawaited(_controller.forward(from: 0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        // Full intensity at the start, easing out to none.
        final intensity = 1 - Curves.easeInOut.transform(_controller.value);
        if (intensity <= 0.001) return child!;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: primary.withValues(alpha: intensity),
              width: 2,
            ),
            color: primary.withValues(alpha: 0.10 * intensity),
          ),
          child: child,
        );
      },
    );
  }
}
