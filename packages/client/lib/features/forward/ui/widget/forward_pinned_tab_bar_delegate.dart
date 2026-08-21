import 'package:flutter/material.dart';

/// Generic pinned sliver header — used for both the scope tab bar and the
/// invite/clear-selection bar above it.
///
/// [height] is supplied by the caller (derived from live design tokens, not
/// a hardcoded constant) so the reserved extent tracks the child's actual
/// window-class-scaled content height instead of drifting out of sync.
class ForwardPinnedSliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  ForwardPinnedSliverHeaderDelegate({
    required this.child,
    required this.height,
  });

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
  bool shouldRebuild(covariant ForwardPinnedSliverHeaderDelegate oldDelegate) {
    return child != oldDelegate.child || height != oldDelegate.height;
  }
}
