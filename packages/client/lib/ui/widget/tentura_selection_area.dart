import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// Whether Flutter's [SelectableRegion] currently wraps its content in the
  /// browser context-menu view: on web, while [BrowserContextMenu.enabled].
  /// Replaceable in tests, where `kIsWeb` is always false.
  @visibleForTesting
  static bool Function() browserContextMenuEnabled = _browserContextMenuOn;

  static bool _browserContextMenuOn() => kIsWeb && BrowserContextMenu.enabled;

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

    return SelectionArea(
      // SelectableRegion adds or drops a browser context-menu wrapper when
      // BrowserContextMenu.enabled flips (chat bubbles flip it on hover,
      // #456). A rebuild across a flip re-creates the region's inner
      // SelectionContainer, which re-registers before layout and throws
      // "Null check operator used on a null value" (grey box, #623). Start a
      // fresh region instead whenever the flag differs from the last build.
      key: ValueKey<bool>(TenturaSelectionArea.browserContextMenuEnabled()),
      focusNode: _focusNode,
      contextMenuBuilder: (_, _) => const SizedBox.shrink(),
      child: widget.child,
    );
  }
}
