import 'dart:async';

import 'package:flutter/widgets.dart';

/// The one wall clock every relative-time label on screen follows (U092).
///
/// It ticks on the [period] boundary of the wall clock (…:00, …:30), so all
/// labels move in the same frame, and it runs only while someone listens:
/// the last [RelativeTimestampTicker] to stop listening (unmounted, or its
/// tab hidden) stops the timer.
class RelativeTimeClock extends ChangeNotifier {
  RelativeTimeClock._();

  /// Shared by every [RelativeTimestampTicker] that is not given its own.
  static final instance = RelativeTimeClock._();

  static const period = Duration(seconds: 30);

  Timer? _timer;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _timer ??= Timer(_untilNextTick(), _tick);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _tick() {
    _timer = hasListeners ? Timer(_untilNextTick(), _tick) : null;
    notifyListeners();
  }

  static Duration _untilNextTick() {
    final periodMs = period.inMilliseconds;
    final intoPeriod =
        RelativeTimestampTicker.now().millisecondsSinceEpoch % periodMs;
    return Duration(milliseconds: periodMs - intoPeriod);
  }
}

/// Rebuilds [builder] on every tick of the shared [RelativeTimeClock], so
/// relative-time labels ("Just now", "2m ago") keep counting while a screen
/// stays open (U092). Compute ages against [RelativeTimestampTicker.now]
/// inside [builder], and wrap only the widgets that show the age: the
/// builder runs on every tick.
///
/// A ticker under a disabled [TickerMode] (a tab kept mounted behind
/// another) stops listening, and catches up when it is shown again.
class RelativeTimestampTicker extends StatefulWidget {
  const RelativeTimestampTicker({
    required this.builder,
    this.clock,
    super.key,
  });

  final WidgetBuilder builder;

  /// Defaults to [RelativeTimeClock.instance].
  final Listenable? clock;

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
  Listenable? _listening;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-shown after being hidden: this rebuild is the catch-up.
    _listen();
  }

  @override
  void didUpdateWidget(RelativeTimestampTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clock != widget.clock) _listen();
  }

  void _listen() {
    final wanted = TickerMode.valuesOf(context).enabled
        ? widget.clock ?? RelativeTimeClock.instance
        : null;
    if (identical(wanted, _listening)) return;
    _listening?.removeListener(_onTick);
    _listening = wanted?..addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _listening?.removeListener(_onTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
