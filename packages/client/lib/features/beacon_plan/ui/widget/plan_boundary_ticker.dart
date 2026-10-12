import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../domain/entity/beacon_plan.dart';

/// The longest the ticker sleeps: «+N min» and «in …» stay fresh to a minute.
const kPlanTickerMaxDelay = Duration(minutes: 1);

/// Time until the plan's next boundary after [now] — a step's start, end or
/// overdue boundary — capped at [kPlanTickerMaxDelay]; null without steps.
Duration? planNextBoundaryDelay(BeaconPlan? plan, DateTime now) {
  if (plan == null || plan.isEmpty) return null;
  var best = kPlanTickerMaxDelay;
  for (final s in plan.steps) {
    for (final t in [s.startAt, s.endAt, s.toState().overdueBoundary]) {
      if (t == null || !t.isAfter(now)) continue;
      final d = t.difference(now);
      if (d < best) best = d;
    }
  }
  // Land just after the boundary so the rebuild sees it as passed.
  return Duration(
    milliseconds: math.max(1000, best.inMilliseconds + 50),
  );
}

/// Rebuilds [builder] at the plan's next boundary (plan §5.2 «тикер»): the
/// HUD rows, the NOW line and the overdue marks move by the clock. Nothing is
/// refetched.
class PlanBoundaryTicker extends StatefulWidget {
  const PlanBoundaryTicker({
    required this.plan,
    required this.builder,
    this.clock,
    super.key,
  });

  final BeaconPlan? plan;
  final Widget Function(BuildContext context, DateTime now) builder;

  /// Test seam for «now».
  final DateTime Function()? clock;

  @override
  State<PlanBoundaryTicker> createState() => _PlanBoundaryTickerState();
}

class _PlanBoundaryTickerState extends State<PlanBoundaryTicker> {
  Timer? _timer;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  void _schedule(DateTime now) {
    _timer?.cancel();
    final delay = planNextBoundaryDelay(widget.plan, now);
    if (delay == null) return;
    _timer = Timer(delay, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = _now();
    _schedule(now);
    return widget.builder(context, now);
  }
}
