import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Whether [ThemeData.platform] is a desktop coordinator target (mouse select).
bool tenturaDesktopSelectionEnabledFor(ThemeData theme) {
  return switch (theme.platform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };
}

/// Wraps [child] in [SelectionArea] on desktop platforms only.
///
/// Mobile web and native touch clients keep long-press menus unchanged.
/// Flutter's default selection context menu is suppressed so secondary-tap
/// can reach caller menus (message / fact actions) on ancestor [InkWell]s.
class TenturaSelectionArea extends StatelessWidget {
  const TenturaSelectionArea({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!tenturaDesktopSelectionEnabledFor(Theme.of(context))) {
      return child;
    }

    return SelectionArea(
      contextMenuBuilder: (_, _) => const SizedBox.shrink(),
      child: child,
    );
  }
}
