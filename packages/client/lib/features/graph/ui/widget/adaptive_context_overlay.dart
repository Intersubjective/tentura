import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// Positions a context card on a graph canvas: bottom dock on compact,
/// fixed-width right rail on regular/expanded ([WindowClass]).
class AdaptiveContextOverlay extends StatelessWidget {
  const AdaptiveContextOverlay({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;

    if (context.windowClass == WindowClass.compact) {
      return Positioned(
        left: tt.screenHPadding,
        right: tt.screenHPadding,
        bottom: 0,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: tt.rowGap),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.sizeOf(context).height *
                    tt.graphPersonContextCompactMaxHeightFraction,
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    return Positioned(
      top: tt.rowGap,
      right: tt.screenHPadding,
      bottom: tt.rowGap,
      width: tt.graphPersonContextWidth,
      child: SafeArea(
        left: false,
        child: child,
      ),
    );
  }
}
