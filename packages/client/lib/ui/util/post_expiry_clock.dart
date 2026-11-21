import 'dart:async';

import 'package:flutter/widgets.dart';

/// Refreshes a consumer at Post deadlines, during the last hour and on resume.
/// Each consumer owns and disposes its own clock.
final class PostExpiryClock {
  PostExpiryClock({
    required this._onTick,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _lifecycleListener = AppLifecycleListener(onResume: _tick);
  }

  final VoidCallback _onTick;
  final DateTime Function() _clock;
  late final AppLifecycleListener _lifecycleListener;
  Set<DateTime> _deadlines = {};
  Timer? _timer;
  bool _disposed = false;

  /// Replaces the deadlines and cancels the previous scheduled refresh.
  void setDeadlines(Set<DateTime> deadlines) {
    if (_disposed) return;
    _deadlines = Set.of(deadlines);
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    final now = _clock();
    DateTime? nearest;
    for (final deadline in _deadlines) {
      if (deadline.isAfter(now) &&
          (nearest == null || deadline.isBefore(nearest))) {
        nearest = deadline;
      }
    }
    if (nearest == null) return;

    final remaining = nearest.difference(now);
    const hour = Duration(hours: 1);
    const minute = Duration(minutes: 1);
    // Wake on entering the last hour, then once per minute, without delaying
    // a deadline that falls between minute ticks.
    final delay = remaining > hour
        ? remaining - hour
        : remaining > minute
        ? minute
        : remaining;
    _timer = Timer(delay, _tick);
  }

  void _tick() {
    if (_disposed) return;
    _arm();
    _onTick();
  }

  /// Cancels timers and detaches the app lifecycle listener.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _lifecycleListener.dispose();
  }
}
