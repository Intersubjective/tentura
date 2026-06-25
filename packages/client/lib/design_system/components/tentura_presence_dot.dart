import 'package:flutter/material.dart';

import '../tentura_tokens.dart';

/// Small online-presence indicator for avatar overlays.
class TenturaPresenceDot extends StatelessWidget {
  const TenturaPresenceDot({
    super.key,
    this.size = 10,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tt.good,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.30),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
