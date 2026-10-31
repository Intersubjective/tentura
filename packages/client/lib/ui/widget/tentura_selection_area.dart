import 'package:flutter/material.dart';

import 'browser_context_menu_hold.dart';

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

  // Holds the child across the re-key below (#761): a new key on
  // [SelectionArea] would otherwise rebuild everything under it, so a
  // description someone expanded (`ShowMoreText`) would collapse again
  // whenever a room opens or the last one closes. With a [GlobalKey] Flutter
  // moves the child's elements and state under the fresh region instead; its
  // text then registers with the new region's container.
  final _childKey = GlobalKey(debugLabel: 'TenturaSelectionArea.child');

  // The current region; replaced after each browser-menu flip (see [build]).
  // A region built after a flip never sees that flip, so it keeps its key.
  var _areaKey = GlobalKey<SelectionAreaState>();

  /// Whether this state is in the active element list (#761).
  var _active = true;

  /// A menu flip arrived while this area could not safely replace its region.
  var _flipPending = false;

  @override
  void initState() {
    super.initState();
    BrowserContextMenuHold.menuFlips.addListener(_onMenuFlip);
  }

  void _onMenuFlip() {
    // Drop the selection while its old region still owns it. The moved
    // child's text keeps its own selection state, so without this it would
    // stay highlighted under a fresh region that knows nothing about it.
    _areaKey.currentState?.selectableRegion.clearSelection();
    if (_mayReplaceRegionNow) {
      _flipPending = false;
      setState(() => _areaKey = GlobalKey<SelectionAreaState>());
      return;
    }
    _flipPending = true;
    _schedulePendingFlip();
  }

  bool get _mayReplaceRegionNow {
    if (!mounted || !_active) {
      return false;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return false;
    }
    return true;
  }

  void _schedulePendingFlip() {
    WidgetsBinding.instance.addPostFrameCallback(_applyPendingFlipAfterFrame);
  }

  void _applyPendingFlipAfterFrame(Duration _) {
    if (!mounted || !_flipPending) {
      return;
    }
    if (!_mayReplaceRegionNow) {
      return;
    }
    _flipPending = false;
    setState(() => _areaKey = GlobalKey<SelectionAreaState>());
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    if (_flipPending) {
      _schedulePendingFlip();
    }
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  void dispose() {
    BrowserContextMenuHold.menuFlips.removeListener(_onMenuFlip);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keyed on both paths, so a platform switch keeps the child's state too.
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (_flipPending && _mayReplaceRegionNow) {
      _schedulePendingFlip();
    }
    if (!tenturaDesktopSelectionEnabledFor(Theme.of(context))) {
      return child;
    }

    // Nothing inside the selectable layer is a Tab stop either: on the web
    // SelectableRegion adds a browser-menu view with a focus node of its own
    // while the browser menu is on, which was one more invisible stop after
    // each message, fact or description (#415). The text here has no
    // controls of its own; a click still focuses the selection.
    //
    // A fresh region after each browser-menu flip (#761): SelectableRegion
    // wraps its inner container in a browser-menu view only while that menu
    // is on, so rebuilding a region across a flip re-creates the container
    // under a region that still has the old one registered, and release web
    // builds crash in SelectionContainer. The re-key is deferred until this
    // state is active on the current route (#761 QA): flipping while Home is
    // deactivated for a Profile push re-keyed into the same unmount pass as
    // the GlobalKey child move and left a subscribed container with no
    // registrar at dispose. Only the region and its selection are new (see
    // [_onMenuFlip]): a selection here is dropped when a room opens or the
    // last one closes, while the child itself keeps its state (see
    // [_childKey]).
    // Inside a room nothing flips (#623).
    return ExcludeFocusTraversal(
      child: SelectionArea(
        key: _areaKey,
        focusNode: _focusNode,
        contextMenuBuilder: (_, _) => const SizedBox.shrink(),
        child: child,
      ),
    );
  }
}
