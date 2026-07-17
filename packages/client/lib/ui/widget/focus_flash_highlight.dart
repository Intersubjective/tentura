import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';

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
    this.autoScroll = true,
    this.animateFlash = true,
    this.staticHighlight = false,
    super.key,
  });

  final bool active;
  final Widget child;
  final BorderRadius borderRadius;

  /// Target alignment passed to [Scrollable.ensureVisible] (0 = top edge).
  final double scrollAlignment;

  /// When false, the wrapper does not call [Scrollable.ensureVisible].
  final bool autoScroll;

  /// When false, uses a static border instead of an animated flash.
  final bool animateFlash;

  /// Persistent highlight (no animation) for attention rows.
  final bool staticHighlight;

  @override
  State<FocusFlashHighlight> createState() => _FocusFlashHighlightState();
}

class _FocusFlashHighlightState extends State<FocusFlashHighlight>
    with SingleTickerProviderStateMixin {
  // Nullable, created on first use — NOT `late final`: a lazy initializer
  // first touched from dispose() would call createTicker → TickerMode
  // ancestor lookup on a deactivated element and throw ("Looking up a
  // deactivated widget's ancestor is unsafe").
  AnimationController? _controllerOrNull;

  AnimationController get _controller =>
      _controllerOrNull ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      );

  @override
  void initState() {
    super.initState();
    if (widget.active && !widget.staticHighlight) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _trigger());
    } else if (widget.active && widget.autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollIntoView());
    }
  }

  @override
  void didUpdateWidget(FocusFlashHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _trigger());
    }
  }

  void _scrollIntoView({bool animated = true}) {
    if (!mounted || !widget.autoScroll) return;
    final ctx = context;
    final scrollable = Scrollable.maybeOf(ctx);
    if (scrollable == null) return;
    if (animated && widget.animateFlash) {
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          alignment: widget.scrollAlignment,
        ),
      );
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        ctx,
        alignment: widget.scrollAlignment,
      ),
    );
  }

  void _trigger() {
    if (!mounted) return;
    if (widget.staticHighlight) {
      _scrollIntoView(animated: widget.animateFlash);
      return;
    }
    _scrollIntoView(animated: widget.animateFlash);
    if (widget.animateFlash) {
      unawaited(_controller.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _controllerOrNull?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (widget.staticHighlight && widget.active) {
      return TenturaChangeHighlight(
        active: true,
        child: widget.child,
      );
    }
    if (!widget.animateFlash || !widget.active) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
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
