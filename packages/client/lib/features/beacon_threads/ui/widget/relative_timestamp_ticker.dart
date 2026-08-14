import 'dart:async';

import 'package:flutter/material.dart';

/// Rebuilds [child] when wall-clock relative-time labels may change — at each
/// minute boundary (separate from [StaleDeadlineTicker]'s deadline cadence).
class RelativeTimestampTicker extends StatefulWidget {
  const RelativeTimestampTicker({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<RelativeTimestampTicker> createState() =>
      _RelativeTimestampTickerState();
}

class _RelativeTimestampTickerState extends State<RelativeTimestampTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
    final delay = nextMinute.difference(now) + const Duration(milliseconds: 200);
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
