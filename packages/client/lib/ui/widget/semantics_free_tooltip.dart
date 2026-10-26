import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// A pointer tooltip that adds nothing to the semantics tree (#678).
///
/// [Tooltip.excludeFromSemantics] only drops the tooltip's message from the
/// child's own node. The bubble itself is still a text node in the overlay,
/// and on the web that node is attached to the button with `aria-owns`, so
/// while it shows (and on the web often after) the button is read twice
/// ("Map Map"). Here the bubble is excluded from semantics as well, so the
/// child must name itself (a semantic label on its icon or a [Semantics]).
///
/// Styling and timing follow the app's [TooltipTheme] like [Tooltip] does.
class SemanticsFreeTooltip extends StatelessWidget {
  const SemanticsFreeTooltip({
    required this.message,
    required this.child,
    this.triggerMode,
    this.showDuration,
    super.key,
  });

  final String message;

  final Widget child;

  /// How a touch shows it; [TooltipTheme] or long press by default. A mouse
  /// shows it on hover either way.
  final TooltipTriggerMode? triggerMode;

  /// How long it stays after a touch; [TooltipTheme] or 1.5 s by default.
  final Duration? showDuration;

  static const _defaultVerticalOffset = 24.0;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty || !TooltipVisibility.of(context)) return child;
    final scheme = Theme.of(context).colorScheme;
    final tooltipTheme = TooltipTheme.of(context);
    final tt = context.tt;
    final box = ConstrainedBox(
      constraints:
          tooltipTheme.constraints ?? BoxConstraints(minHeight: tt.iconSize),
      child: Container(
        decoration:
            tooltipTheme.decoration ??
            BoxDecoration(
              color: scheme.inverseSurface,
              borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
            ),
        padding:
            tooltipTheme.padding ??
            EdgeInsets.symmetric(horizontal: tt.rowGap, vertical: tt.tightGap),
        margin: tooltipTheme.margin,
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            message,
            style:
                tooltipTheme.textStyle ??
                TenturaText.bodySmall(scheme.onInverseSurface),
            textAlign: tooltipTheme.textAlign ?? TextAlign.start,
          ),
        ),
      ),
    );
    final verticalOffset =
        tooltipTheme.verticalOffset ?? _defaultVerticalOffset;
    final preferBelow = tooltipTheme.preferBelow ?? true;
    return RawTooltip(
      // No semantics tooltip on the child either: it names itself.
      semanticsTooltip: null,
      tooltipBuilder: (context, animation) => ExcludeSemantics(
        child: FadeTransition(opacity: animation, child: box),
      ),
      hoverDelay: tooltipTheme.waitDuration ?? Duration.zero,
      touchDelay:
          showDuration ??
          tooltipTheme.showDuration ??
          const Duration(milliseconds: 1500),
      dismissDelay:
          tooltipTheme.exitDuration ?? const Duration(milliseconds: 100),
      triggerMode:
          triggerMode ??
          tooltipTheme.triggerMode ??
          TooltipTriggerMode.longPress,
      enableFeedback: tooltipTheme.enableFeedback ?? true,
      positionDelegate: (position) => positionDependentBox(
        size: position.overlaySize,
        childSize: position.tooltipSize,
        target: position.target,
        verticalOffset: verticalOffset,
        preferBelow: preferBelow,
      ),
      ignorePointer: true,
      child: child,
    );
  }
}
