import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

/// App bar leading: [AutoLeadingButton] when the stack can pop; otherwise a
/// [BackButton] that navigates to [fallbackPath] (e.g. after a web refresh).
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
    return BackButton(
      onPressed: () =>
          unawaited(context.router.navigatePath(fallbackPath)),
    );
  }
}
