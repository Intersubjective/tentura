import 'dart:math' as math;

/// Adapts slice sizes from measured per-unit costs using AIMD.
class AdaptiveSliceController {
  AdaptiveSliceController({required Duration initialUnitCost}) {
    if (initialUnitCost <= Duration.zero) {
      throw ArgumentError.value(
        initialUnitCost,
        'initialUnitCost',
        'Must be positive',
      );
    }
    _ewmaUnitCostUs = initialUnitCost.inMicroseconds.toDouble();
    _batchSize = math.max(1, setpoint.inMicroseconds ~/ _ewmaUnitCostUs);
  }

  final Duration setpoint = const Duration(milliseconds: 4);
  final Duration hardCap = const Duration(milliseconds: 8);

  late double _ewmaUnitCostUs;
  late int _batchSize;

  int get batchSize => _batchSize;

  Duration get ewmaUnitCost => Duration(microseconds: _ewmaUnitCostUs.round());

  /// Reports completed units, including slices stopped before [batchSize].
  void recordSlice({required int units, required Duration elapsed}) {
    if (units <= 0) {
      throw ArgumentError.value(units, 'units', 'Must be positive');
    }
    if (elapsed < Duration.zero) {
      throw ArgumentError.value(elapsed, 'elapsed', 'Must not be negative');
    }
    _ewmaUnitCostUs =
        0.3 * (elapsed.inMicroseconds / units) + 0.7 * _ewmaUnitCostUs;
    final nextSize = elapsed <= setpoint ? _batchSize + 8 : _batchSize ~/ 2;
    final cappedSize = hardCap.inMicroseconds ~/ _ewmaUnitCostUs;
    _batchSize = math.max(1, math.min(nextSize, cappedSize));
  }
}
