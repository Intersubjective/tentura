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

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Center(
            child: Text(
              count > 99 ? '99+' : '$count',
              style: TenturaText.labelSmall(Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
