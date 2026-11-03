import 'package:flutter/material.dart';

/// Shared indeterminate progress for screen gates and inline actions.
///
/// Feature code must not use [CircularProgressIndicator] directly; this widget
/// is the allow-listed surface (see `no_raw_circular_progress_in_features`).
class TenturaCircularProgress extends StatelessWidget {
  const TenturaCircularProgress({
    this.adaptive = false,
    this.strokeWidth,
    super.key,
  });

  final bool adaptive;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    if (adaptive) {
      return CircularProgressIndicator.adaptive(strokeWidth: strokeWidth);
    }
    return CircularProgressIndicator(strokeWidth: strokeWidth);
  }
}
