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
    final maxW = tokens.contentMaxWidth;
    final themed = Theme(
      data: theme.copyWith(extensions: <ThemeExtension<dynamic>>[tokens]),
      child: child,
    );
    if (maxW == null) {
      return themed;
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: themed,
      ),
    );
  }
}
