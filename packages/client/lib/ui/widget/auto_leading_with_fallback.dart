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
    super.key,
  });

  final String fallbackPath;

  @override
  Widget build(BuildContext context) {
    if (context.router.canPop()) {
      return const AutoLeadingButton();
    }
    final l10n = MaterialLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.backButtonTooltip,
      child: IconButton(
        icon: const BackButtonIcon(),
        onPressed: () =>
            unawaited(context.router.navigatePath(fallbackPath)),
      ),
    );
  }
}
