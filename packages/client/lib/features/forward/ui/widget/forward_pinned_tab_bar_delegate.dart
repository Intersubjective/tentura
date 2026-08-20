import 'package:flutter/material.dart';

/// Pinned tab-bar sliver header.
///
/// [height] is supplied by the caller (derived from live design tokens, not
/// a hardcoded constant) so the reserved extent tracks the child's actual
/// window-class-scaled content height instead of drifting out of sync.
class ForwardPinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  ForwardPinnedTabBarDelegate({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: overlapsContent ? 0.5 : 0,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant ForwardPinnedTabBarDelegate oldDelegate) {
    return child != oldDelegate.child || height != oldDelegate.height;
  }
}
