import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_item.dart';

/// Rebuilds when the nearest active-item stale deadline or overdue label bucket
/// changes so stale labels and remind actions update without leaving the Items tab.
class StaleDeadlineTicker extends StatefulWidget {
  const StaleDeadlineTicker({
    required this.items,
    required this.child,
  });

  final List<CoordinationItem> items;
  final Widget child;

  @override
  State<StaleDeadlineTicker> createState() => _StaleDeadlineTickerState();
}

class _StaleDeadlineTickerState extends State<StaleDeadlineTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant StaleDeadlineTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now().toUtc();
    DateTime? nearest;
    for (final item in widget.items) {
      if (!item.isActive) continue;
      final next = item.nextStaleOverdueLabelChangeAt(now);
      if (next == null) continue;
      final utc = next.toUtc();
      if (nearest == null || utc.isBefore(nearest)) {
        nearest = utc;
      }
    }
    if (nearest == null) return;
    final delay = nearest.difference(now) + const Duration(milliseconds: 500);
    _timer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        if (!mounted) return;
        setState(() {});
        _schedule();
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
