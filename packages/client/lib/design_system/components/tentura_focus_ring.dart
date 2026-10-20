import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../tentura_radii.dart';
import '../tentura_spacing.dart';

/// Draws a keyboard focus ring around whichever control holds keyboard focus
/// (#499).
///
/// Material only tints a focused control with a faint overlay fill, which
/// does not meet WCAG 2.4.11 / 2.4.13 (focus indicator ≥ 3:1). This sits
/// above the app's navigator (in `MaterialApp.builder`) and outlines the
/// primary focus with a [TenturaSpacing.focusRing]-wide stroke in
/// [ColorScheme.primary], [gap] outside the control, so every focusable
/// control — buttons, icon buttons, list tiles, chips, cards — gets the same
/// ring without each widget opting in. The fill stays.
///
/// The ring shows only in keyboard (traditional) highlight mode, so taps and
/// clicks never draw it. Text fields are skipped: their focused border is
/// already a 2 dp primary outline. A control that draws its own keyboard
/// ring opts out with [TenturaFocusRing.exclude].
class TenturaFocusRing extends StatefulWidget {
  const TenturaFocusRing({required this.child, super.key});

  /// Key of the ring decoration, for tests.
  static const ringKey = ValueKey<String>('tenturaFocusRing');

  /// Space between the focused control's bounds and the ring.
  static const double gap = 2;

  /// A focused region larger than this share of the app is a container
  /// (screen-level shortcut scope), not a control, and gets no ring.
  static const double maxAreaFraction = 0.5;

  final Widget child;

  /// Marks [child]'s focus nodes as drawing their own keyboard focus ring, so
  /// the app-level ring skips them instead of drawing a second one. Wrap the
  /// control itself, not a whole screen: every focus node below it is
  /// skipped.
  static Widget exclude({required Widget child, Key? key}) =>
      _TenturaFocusRingExclude(key: key, child: child);

  @override
  State<TenturaFocusRing> createState() => _TenturaFocusRingState();
}

class _TenturaFocusRingState extends State<TenturaFocusRing> {
  final _stackKey = GlobalKey();

  Rect? _rect;

  bool _tracking = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance
      ..addListener(_onFocusChange)
      ..addHighlightModeListener(_onHighlightModeChange);
    _schedule();
  }

  @override
  void dispose() {
    FocusManager.instance
      ..removeListener(_onFocusChange)
      ..removeHighlightModeListener(_onHighlightModeChange);
    super.dispose();
  }

  void _onFocusChange() => _update();

  void _onHighlightModeChange(FocusHighlightMode _) => _update();

  /// Focus and highlight-mode changes usually land between frames (focus
  /// changes are applied in a microtask), when the last frame's layout is
  /// still valid: read the rect now so the ring is drawn in the very next
  /// frame, rather than one frame after it. Mid-frame, wait for the frame.
  void _update() {
    if (mounted &&
        SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      final rect = _computeRect();
      if (rect != _rect) {
        setState(() => _rect = rect);
      }
    }
    _schedule();
  }

  /// Re-reads the ring's rect after every frame while mounted; layout and
  /// scrolling move the focused control without a focus notification. The
  /// callback does not itself schedule frames, so an idle app stays idle.
  void _schedule() {
    WidgetsBinding.instance.ensureVisualUpdate();
    if (_tracking) {
      return;
    }
    _tracking = true;
    WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
  }

  void _afterFrame(Duration _) {
    _tracking = false;
    if (!mounted) {
      return;
    }
    final rect = _computeRect();
    if (rect != _rect) {
      setState(() => _rect = rect);
    }
    _tracking = true;
    WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
  }

  Rect? _computeRect() {
    final manager = FocusManager.instance;
    if (manager.highlightMode != FocusHighlightMode.traditional) {
      return null;
    }
    final node = manager.primaryFocus;
    if (node == null || node is FocusScopeNode) {
      return null;
    }
    final context = node.context;
    if (context == null || !context.mounted) {
      return null;
    }
    if (context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null ||
        context.findAncestorWidgetOfExactType<_TenturaFocusRingExclude>() !=
            null) {
      return null;
    }
    final target = context.findRenderObject();
    final stack = _stackKey.currentContext?.findRenderObject();
    if (target is! RenderBox ||
        stack is! RenderBox ||
        !target.attached ||
        !target.hasSize ||
        !stack.hasSize ||
        target.size.isEmpty) {
      return null;
    }
    final topLeft = target.localToGlobal(Offset.zero, ancestor: stack);
    final rect = topLeft & target.size;
    // A focus covering most of the app is a screen- or pane-level shortcut
    // scope (e.g. the constellation body), not a control; outlining it says
    // nothing about where the user is.
    final area = rect.intersect(Offset.zero & stack.size);
    if (area.width * area.height >
        stack.size.width *
            stack.size.height *
            TenturaFocusRing.maxAreaFraction) {
      return null;
    }
    return rect;
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    return Stack(
      key: _stackKey,
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (rect != null)
          Positioned.fromRect(
            rect: rect.inflate(
              TenturaFocusRing.gap + TenturaSpacing.focusRing,
            ),
            child: IgnorePointer(
              child: DecoratedBox(
                key: TenturaFocusRing.ringKey,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: TenturaSpacing.focusRing,
                  ),
                  borderRadius: BorderRadius.circular(
                    TenturaRadii.button +
                        TenturaFocusRing.gap +
                        TenturaSpacing.focusRing,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TenturaFocusRingExclude extends StatelessWidget {
  const _TenturaFocusRingExclude({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
