import 'package:flutter/material.dart';

import '../tentura_tokens.dart';

/// Accessible, reduced-motion-aware emphasis for a newly changed field.
class TenturaChangeHighlight extends StatelessWidget {
  const TenturaChangeHighlight({
    required this.active,
    required this.child,
    super.key,
  });

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Semantics(
      container: active,
      liveRegion: active,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: active
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(tt.cardRadius),
                border: Border.all(color: tt.attentionHighlight, width: 2),
                color: tt.attentionHighlight.withValues(alpha: 0.08),
              )
            : null,
        child: child,
      ),
    );
  }
}
