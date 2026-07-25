import 'package:flutter/material.dart';

/// Shared square frame for request identity tiles (photo / symbol / neutral).
///
/// Owns constraints, radius, clip, outline border, and optional semantics.
/// Content is supplied by the caller ([child]).
class TenturaIdentityTileFrame extends StatelessWidget {
  const TenturaIdentityTileFrame({
    required this.size,
    required this.child,
    this.semanticsLabel,
    this.backgroundColor,
    super.key,
  });

  final double size;
  final Widget child;
  final String? semanticsLabel;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = size * 0.2;
    final frame = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: child,
        ),
      ),
    );
    if (semanticsLabel == null) {
      return frame;
    }
    return Semantics(
      label: semanticsLabel,
      child: frame,
    );
  }
}
