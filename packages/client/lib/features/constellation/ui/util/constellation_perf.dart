import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Constellation diagnostics. Release builds never allocate tracing state.
abstract final class ConstellationPerf {
  static ValueNotifier<bool>? _hudEnabled;

  static ValueNotifier<bool> get hudEnabled {
    if (kDebugMode) {
      return _hudEnabled ??= ValueNotifier<bool>(false);
    }
    throw StateError('The performance HUD is debug-only');
  }

  static T timeSync<T>(String name, T Function() work) {
    if (kReleaseMode) return work();
    return Timeline.timeSync(name, work);
  }

  static TimelineTask? startSpan(String name) {
    if (kReleaseMode) return null;
    return TimelineTask()..start(name);
  }

  static void finishSpan(TimelineTask? span) {
    if (kReleaseMode) return;
    span?.finish();
  }

  static void startFrameReporting() {
    if (kReleaseMode) return;
    SchedulerBinding.instance.addTimingsCallback(_reportFrames);
  }

  static void stopFrameReporting() {
    if (kReleaseMode) return;
    SchedulerBinding.instance.removeTimingsCallback(_reportFrames);
  }

  static void _reportFrames(List<FrameTiming> timings) {
    if (kReleaseMode) return;
    for (final frame in timings) {
      if (frame.buildDuration.inMicroseconds > 50000) {
        debugPrint('Constellation long build: ${frame.buildDuration}');
      }
      if (frame.rasterDuration.inMicroseconds > 50000) {
        debugPrint('Constellation long raster: ${frame.rasterDuration}');
      }
    }
  }
}
