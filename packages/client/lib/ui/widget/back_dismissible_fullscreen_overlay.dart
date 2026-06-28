import 'package:flutter/material.dart';

import 'back_dismissible_overlay_history.dart';

/// Wraps a fullscreen imperative overlay so browser / PWA back closes it first.
///
/// On Flutter Web, [MaterialPageRoute] pushes often do not win against a parent
/// [PopScope] history sentinel (e.g. beacon room). Registering `canPop: false`
/// on the overlay route intercepts back here and pops the overlay explicitly.
class BackDismissibleFullscreenOverlay extends StatefulWidget {
  const BackDismissibleFullscreenOverlay({
    required this.child,
    super.key,
  });

  final Widget child;

  static final List<VoidCallback> _popCallbacks = [];
  static DateTime? _browserBackHandledAt;

  static bool get hasOpenOverlay => _popCallbacks.isNotEmpty;

  static bool consumeBrowserBackHandledByOverlay() {
    final handledAt = _browserBackHandledAt;
    if (handledAt == null) {
      return false;
    }
    _browserBackHandledAt = null;
    return DateTime.timestamp().difference(handledAt) <
        const Duration(seconds: 2);
  }

  static void _markBrowserBackHandledByOverlay() {
    _browserBackHandledAt = DateTime.timestamp();
  }

  /// Pops the top app-owned fullscreen overlay, if one is open.
  ///
  /// Parent [PopScope] handlers use this instead of popping the root
  /// navigator directly so the overlay can mark its browser-history sentinel
  /// as already consumed by back navigation.
  static bool popTopOverlay() {
    if (_popCallbacks.isEmpty) {
      return false;
    }
    _popCallbacks.last();
    return true;
  }

  @override
  State<BackDismissibleFullscreenOverlay> createState() =>
      _BackDismissibleFullscreenOverlayState();
}

class _BackDismissibleFullscreenOverlayState
    extends State<BackDismissibleFullscreenOverlay> {
  late final BackDismissibleOverlayHistorySentinel _historySentinel;

  @override
  void initState() {
    super.initState();
    _historySentinel = BackDismissibleOverlayHistorySentinel(
      onPop: () => _popOverlay(fromBrowserHistory: true),
    );
    BackDismissibleFullscreenOverlay._popCallbacks.add(_popOverlay);
  }

  @override
  void dispose() {
    BackDismissibleFullscreenOverlay._popCallbacks.remove(_popOverlay);
    BackDismissibleFullscreenOverlay._markBrowserBackHandledByOverlay();
    _historySentinel.dispose();
    super.dispose();
  }

  void _popOverlay({bool fromBrowserHistory = false}) {
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      if (fromBrowserHistory) {
        BackDismissibleFullscreenOverlay._markBrowserBackHandledByOverlay();
      }
      _historySentinel.markHandledByBack();
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _popOverlay();
      },
      child: widget.child,
    );
  }
}

/// Pushes [child] on the root navigator as a back-dismissible fullscreen overlay.
Future<T?> pushBackDismissibleFullscreenOverlay<T>(
  BuildContext context,
  Widget child,
) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    MaterialPageRoute<T>(
      fullscreenDialog: true,
      builder: (_) => BackDismissibleFullscreenOverlay(child: child),
    ),
  );
}
