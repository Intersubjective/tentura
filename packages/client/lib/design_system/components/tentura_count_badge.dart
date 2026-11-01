import 'package:flutter/material.dart';

import '../tentura_text.dart';

/// Small circular count chip (tab badges, item discussion totals).
class TenturaCountBadge extends StatelessWidget {
  const TenturaCountBadge({
    required this.count,
    required this.backgroundColor,
    super.key,
  });

  final int count;
  final Color backgroundColor;

  /// The chip's diameter: its minimum width and height.
  static const double minSize = 18;

  /// Horizontal padding on each side of the count.
  static const double horizontalPadding = 5;

  /// Counts above this read as `99+`.
  static const int maxShown = 99;

  /// The text the chip shows for [count].
  static String label(int count) => count > maxShown ? '$maxShown+' : '$count';

  /// The width the chip takes for [count] in [context] (text scale and
  /// direction included), for layouts that size around it before building.
  static double widthFor(BuildContext context, int count) {
    final painter = TextPainter(
      text: TextSpan(
        text: label(count),
        style: TenturaText.labelSmall(Colors.white),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width + 2 * horizontalPadding;
    painter.dispose();
    return width < minSize ? minSize : width;
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: minSize, minHeight: minSize),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(minSize / 2),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Center(
            child: Text(
              label(count),
              style: TenturaText.labelSmall(Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
