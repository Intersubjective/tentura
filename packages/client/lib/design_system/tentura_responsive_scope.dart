import 'package:flutter/material.dart';

import 'tentura_tokens.dart';
import 'tentura_window_class.dart';

/// Rebuilds `Theme` with `TenturaTokens` density for the current `WindowClass`.
///
/// `TextTheme` sizes are unchanged from `TenturaTheme`; [TenturaTokens.applyWindowClass]
/// updates spacing, chrome sizes, avatar/icon metrics, and `contentMaxWidth`.
class TenturaResponsiveScope extends StatelessWidget {
  const TenturaResponsiveScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.extension<TenturaTokens>();
    if (base == null) {
      return child;
    }
    final wc = context.windowClass;
    final tokens = base.applyWindowClass(wc);
    final themed = Theme(
      data: theme.copyWith(extensions: <ThemeExtension<dynamic>>[tokens]),
      child: child,
    );
    // Apply token density only. Do not cap layout width here: a centered
    // ConstrainedBox clips full-bleed shells (home rail, graph canvas) on web.
    // Screens that need a centered column use [TenturaTokens.contentMaxWidth]
    // locally (see credentials_screen.dart).
    return themed;
  }
}

/// Centers [child] when [TenturaTokens.contentMaxWidth] is set for the current
/// [WindowClass]. Use on standalone routes; not on home shell / graph canvas.
class TenturaContentColumn extends StatelessWidget {
  const TenturaContentColumn({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxW = context.tt.contentMaxWidth;
    if (maxW == null) {
      return child;
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: child,
      ),
    );
  }
}

/// Expands [child] to the full viewport width.
///
/// Kept for graph routes; a no-op when the app root is already full width.
class TenturaFullBleed extends StatelessWidget {
  const TenturaFullBleed({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
