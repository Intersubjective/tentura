import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../tentura_spacing.dart';

/// Fades the edges of a horizontally scrolled row where more content is hidden,
/// so the row reads as scrollable (#659, Field tag row #973).
class TenturaEdgeFadedRow extends StatefulWidget {
  const TenturaEdgeFadedRow({
    required this.color,
    required this.child,
    this.fadeKeyPrefix = 'constellation.show',
    super.key,
  });

  final Color color;
  final Widget child;

  /// Prefix for fade overlay keys (`{prefix}.fade_start` / `.fade_end`).
  final String fadeKeyPrefix;

  @override
  State<TenturaEdgeFadedRow> createState() => _TenturaEdgeFadedRowState();
}

class _TenturaEdgeFadedRowState extends State<TenturaEdgeFadedRow> {
  static const _fadeWidth = TenturaSpacing.scrollEdgeFade;

  var _moreBefore = false;
  var _moreAfter = false;

  bool _onMetrics(ScrollMetrics metrics) {
    if (metrics.axis != Axis.horizontal) return false;
    final moreBefore = metrics.extentBefore > 0.5;
    final moreAfter = metrics.extentAfter > 0.5;
    if (moreBefore == _moreBefore && moreAfter == _moreAfter) return false;
    void apply() {
      if (!mounted) return;
      setState(() {
        _moreBefore = moreBefore;
        _moreAfter = moreAfter;
      });
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
    return false;
  }

  Widget _fade(String key, AlignmentDirectional towards) => IgnorePointer(
    key: Key(key),
    child: SizedBox(
      width: _fadeWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: -towards,
            end: towards,
            colors: [widget.color.withValues(alpha: 0), widget.color],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) => _onMetrics(notification.metrics),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) =>
              notification.depth == 0 && _onMetrics(notification.metrics),
          child: widget.child,
        ),
      ),
      if (_moreBefore)
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          child: _fade(
            '${widget.fadeKeyPrefix}.fade_start',
            AlignmentDirectional.centerStart,
          ),
        ),
      if (_moreAfter)
        PositionedDirectional(
          end: 0,
          top: 0,
          bottom: 0,
          child: _fade(
            '${widget.fadeKeyPrefix}.fade_end',
            AlignmentDirectional.centerEnd,
          ),
        ),
    ],
  );
}
