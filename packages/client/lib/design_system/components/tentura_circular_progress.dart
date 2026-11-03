import 'package:flutter/material.dart';

/// Shared indeterminate progress for screen gates and inline actions.
///
/// Feature code must not use [CircularProgressIndicator] directly; this widget
/// is the allow-listed surface (see `no_raw_circular_progress_in_features`).
class TenturaCircularProgress extends StatelessWidget {
  const TenturaCircularProgress({
    this.adaptive = false,
    this.strokeWidth,
    this.color,
    this.value,
    super.key,
  });

  final bool adaptive;
  final double? strokeWidth;
  final Color? color;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final valueColor = color == null
        ? null
        : AlwaysStoppedAnimation<Color>(color!);
    if (adaptive) {
      return CircularProgressIndicator.adaptive(
        strokeWidth: strokeWidth,
        value: value,
        valueColor: valueColor,
      );
    }
    return CircularProgressIndicator(
      strokeWidth: strokeWidth,
      color: color,
      value: value,
      valueColor: valueColor,
    );
  }
}
