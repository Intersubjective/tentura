import 'dart:async';

import 'package:flutter/material.dart';

/// Rebuilds [builder] every [interval] so relative-time labels ("Just now",
/// "2m ago") keep counting while a screen stays open (U092). Compute ages
/// against [RelativeTimestampTicker.now] inside [builder].
///
/// The builder runs in this state's `build`, so each tick produces fresh
/// widgets; a fixed `child` would be reused as the same instance and never
/// rebuild.
class RelativeTimestampTicker extends StatefulWidget {
  const RelativeTimestampTicker({
    required this.builder,
    this.interval = const Duration(seconds: 30),
    super.key,
  });

  final WidgetBuilder builder;

  final Duration interval;

  /// Tests pin the wall clock here.
  @visibleForTesting
  static DateTime Function()? debugClock;

  /// The wall clock relative-time labels should use.
  static DateTime now() => (debugClock ?? DateTime.now)();

  @override
  State<RelativeTimestampTicker> createState() =>
      _RelativeTimestampTickerState();
}

class _RelativeTimestampTickerState extends State<RelativeTimestampTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(RelativeTimestampTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval) _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
