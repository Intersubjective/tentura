import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

/// App bar leading: [AutoLeadingButton] when the stack can pop; otherwise a
/// back control that navigates to [fallbackPath] (e.g. after a web refresh).
///
/// Uses [IconButton] without a [Tooltip] for the fallback path to avoid a
/// web overlay layout assertion (`size == theater.size`) during first frame.
class AutoLeadingWithFallback extends StatelessWidget {
  const AutoLeadingWithFallback({
    required this.fallbackPath,
    this.onFallback,
    this.onPressed,
    this.closeWhenCanPop = false,
    super.key,
  });

  final String fallbackPath;

  /// When the stack cannot pop (e.g. web refresh on a deep link), run this
  /// instead of [StackRouter.navigatePath] on [fallbackPath].
  final VoidCallback? onFallback;

  /// Replaces both [maybePop] and the fallback navigation when set.
  final VoidCallback? onPressed;

  /// Show a close icon instead of back when the stack can pop.
  final bool closeWhenCanPop;

  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    if (context.router.canPop()) {
      if (onPressed != null || closeWhenCanPop) {
        // The tooltip names the button; a Semantics label on top of it was
        // read as "Back\nBack" (#668).
        return IconButton(
          icon: Icon(closeWhenCanPop ? Icons.close : Icons.arrow_back),
          tooltip: closeWhenCanPop
              ? l10n.closeButtonLabel
              : l10n.backButtonTooltip,
          onPressed: onPressed ?? () => unawaited(context.router.maybePop()),
        );
      }
      // AutoLeadingButton may still render noLeading when its RouterScope
      // canPop disagrees with context.router.canPop() (e.g. after warm deep
      // link + browser history.back). Keep a tappable fallback in that case.
      return AutoLeadingButton.builder(
        builder: (context, leading) {
          if (leading != null) return leading;
          return IconButton(
            icon: Icon(
              Icons.arrow_back,
              semanticLabel: l10n.backButtonTooltip,
            ),
            onPressed: () {
              final custom = onFallback;
              if (custom != null) {
                custom();
                return;
              }
              unawaited(context.router.navigatePath(fallbackPath));
            },
          );
        },
      );
    }
    // No tooltip here (see class doc): the icon's own label names the
    // button, so it is one node said once (#668).
    return IconButton(
      icon: Icon(
        closeWhenCanPop ? Icons.close : Icons.arrow_back,
        semanticLabel: l10n.backButtonTooltip,
      ),
      onPressed: () {
        final custom = onPressed ?? onFallback;
        if (custom != null) {
          custom();
          return;
        }
        unawaited(context.router.navigatePath(fallbackPath));
      },
    );
  }
}
