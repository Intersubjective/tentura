import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

import 'package:tentura/domain/port/clock_port.dart';
import 'package:tentura/domain/port/wake_up_port.dart';
import 'package:tentura/domain/scheduling/adaptive_slice_controller.dart';

/// Runs a resumable job in bounded slices, at most one per frame.
///
/// Slices are posted with [Priority.idle]. Continuous animation can starve
/// idle tasks, so each post also arms a [starvationWindow] wake-up through
/// [WakeUpPort] that re-posts the slice at [Priority.animation]. Every post
/// bumps an epoch and each posted callback checks it, so a slice runs at most
/// once however many of its callbacks end up eligible. A pointer that is down
/// pauses the job until the last pointer is released.
class FrameSliceScheduler {
  FrameSliceScheduler({
    required this._clock,
    required this._wakeUpPort,
    required this._controller,
  }) {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointerEvent);
  }

  static const starvationWindow = Duration(milliseconds: 100);

  final ClockPort _clock;
  final WakeUpPort _wakeUpPort;
  final AdaptiveSliceController _controller;
  final _pointersDown = <int>{};

  bool Function(int units)? _step;
  void Function()? _onComplete;
  WakeUpHandle? _wakeUp;
  var _epoch = 0;

  /// Replaces any running job; [step] returns true once the job is done.
  void start({
    required bool Function(int units) step,
    required void Function() onComplete,
  }) {
    cancel();
    _step = step;
    _onComplete = onComplete;
    if (_pointersDown.isEmpty) _post();
  }

  void cancel() {
    _step = null;
    _onComplete = null;
    _invalidate();
  }

  /// Cancels the job only if it is still the one started with [onComplete],
  /// so a stale owner cannot cancel its replacement.
  void cancelJob(void Function() onComplete) {
    if (identical(_onComplete, onComplete)) cancel();
  }

  void dispose() {
    cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointerEvent);
  }

  void _invalidate() {
    _epoch++;
    _wakeUp?.cancel();
    _wakeUp = null;
  }

  void _post() {
    _invalidate();
    final epoch = _epoch;
    final binding = SchedulerBinding.instance;
    // A starved idle task makes the binding re-poll its queue in a hot loop,
    // so during animation only the wake-up below posts the slice.
    if (binding.transientCallbackCount == 0) {
      unawaited(binding.scheduleTask<void>(() => _run(epoch), Priority.idle));
    }
    _wakeUp = _wakeUpPort.schedule(
      starvationWindow,
      () => unawaited(
        binding.scheduleTask<void>(() => _run(epoch), Priority.animation),
      ),
    );
  }

  void _run(int epoch) {
    final step = _step;
    if (epoch != _epoch || step == null) return;
    _invalidate();

    final startedAt = _clock.now();
    var units = 0;
    var done = false;
    var elapsed = Duration.zero;
    try {
      do {
        done = step(1);
        units++;
        elapsed = _clock.now().difference(startedAt);
      } while (!done &&
          units < _controller.batchSize &&
          elapsed < _controller.setpoint);
    } catch (_) {
      cancel();
      rethrow;
    }
    _controller.recordSlice(units: units, elapsed: elapsed);

    if (done) {
      final onComplete = _onComplete;
      cancel();
      onComplete?.call();
      return;
    }
    // Frame permit: the next slice may only be posted after a frame.
    final permitEpoch = _epoch;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (permitEpoch == _epoch && _pointersDown.isEmpty) _post();
      })
      ..ensureVisualUpdate();
  }

  void _onPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (_pointersDown.add(event.pointer)) _invalidate();
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_pointersDown.remove(event.pointer) &&
          _pointersDown.isEmpty &&
          _step != null) {
        _post();
      }
    }
  }
}
