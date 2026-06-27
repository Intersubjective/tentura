import 'package:flutter/material.dart';

/// Wraps a fullscreen imperative overlay so browser / PWA back closes it first.
///
/// On Flutter Web, [MaterialPageRoute] pushes often do not win against a parent
/// [PopScope] history sentinel (e.g. beacon room). Registering `canPop: false`
/// on the overlay route intercepts back here and pops the overlay explicitly.
class BackDismissibleFullscreenOverlay extends StatelessWidget {
  const BackDismissibleFullscreenOverlay({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) {
          nav.pop();
        }
      },
      child: child,
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
