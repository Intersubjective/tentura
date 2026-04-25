import 'package:flutter/material.dart';

import '../tentura_tokens.dart';

/// Flat record card: white surface, hairline border, no elevation by default.
class TenturaTechCard extends StatelessWidget {
  const TenturaTechCard({
    required this.child,
    super.key,
    this.isOwned = false,
    this.onTap,
    this.padding,
    this.showShadow = false,
  });

  final Widget child;
  final bool isOwned;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final effectivePadding = padding ?? tt.cardPadding;
    final borderColor = isOwned
        ? tt.info.withValues(alpha: 0.3)
        : tt.border;
    return Material(
      color: tt.surface,
      shadowColor: showShadow
          ? Colors.black.withValues(alpha: 0.04)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tt.cardRadius),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(
              padding: effectivePadding,
              child: child,
            )
          : InkWell(
              onTap: onTap,
              child: Padding(
                padding: effectivePadding,
                child: child,
              ),
            ),
    );
  }
}

/// Same visuals as [TenturaTechCard] but without [InkWell] (non-tappable content).
class TenturaTechCardStatic extends StatelessWidget {
  const TenturaTechCardStatic({
    required this.child,
    super.key,
    this.isOwned = false,
    this.padding,
    this.showShadow = false,
  });

  final Widget child;
  final bool isOwned;
  final EdgeInsetsGeometry? padding;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final effectivePadding = padding ?? tt.cardPadding;
    final borderColor = isOwned
        ? tt.info.withValues(alpha: 0.3)
        : tt.border;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tt.surface,
        borderRadius: BorderRadius.circular(tt.cardRadius),
        border: Border.all(color: borderColor),
        boxShadow: showShadow
            ? const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: effectivePadding,
        child: child,
      ),
    );
  }
}
