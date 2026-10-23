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
class TenturaSelectionArea extends StatefulWidget {
  const TenturaSelectionArea({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<TenturaSelectionArea> createState() => _TenturaSelectionAreaState();
}

class _TenturaSelectionAreaState extends State<TenturaSelectionArea> {
  // Not a Tab stop: the text sits inside a control that already has its own
  // stop, so a second, invisible stop would repeat it (#415). A click still
  // focuses it, so Ctrl+A / Ctrl+C keep working after a mouse selection.
  final _focusNode = FocusNode(
    debugLabel: 'TenturaSelectionArea',
    skipTraversal: true,
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!tenturaDesktopSelectionEnabledFor(Theme.of(context))) {
      return widget.child;
    }

    // Nothing inside the selectable layer is a Tab stop either: on the web
    // SelectableRegion adds a browser-menu view with a focus node of its own
    // while the browser menu is on, which was one more invisible stop after
    // each message, fact or description (#415). The text here has no
    // controls of its own; a click still focuses the selection.
    return ExcludeFocusTraversal(
      child: SelectionArea(
        focusNode: _focusNode,
        contextMenuBuilder: (_, _) => const SizedBox.shrink(),
        child: widget.child,
      ),
    );
  }
}
