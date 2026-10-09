import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/scheduling/adaptive_slice_controller.dart';

// Domain contract: seed with a measured per-unit cost, read batchSize, then
// report completed units and elapsed time through recordSlice. No scheduler,
// frame callbacks, or real clock is involved in these tests.
void main() {
  group('Adaptive slice budgets', () {
    test('targets four milliseconds with an eight millisecond hard cap', () {
      final controller = AdaptiveSliceController(
        initialUnitCost: const Duration(microseconds: 100),
      );

      expect(controller.setpoint, const Duration(milliseconds: 4));
      expect(controller.hardCap, const Duration(milliseconds: 8));
    });

    test('caps additive growth at eight milliseconds of estimated work', () {
      final controller = AdaptiveSliceController(
        initialUnitCost: const Duration(microseconds: 500),
      );
      expect(controller.batchSize, 8);

      controller.recordSlice(
        units: 8,
        elapsed: const Duration(milliseconds: 4),
      );
      expect(controller.batchSize, 16);

      controller.recordSlice(
        units: 16,
        elapsed: const Duration(milliseconds: 4),
      );
      expect(controller.ewmaUnitCost, const Duration(microseconds: 425));

      // Uncapped +8 growth would request 24 units at 425 us each: 10.2 ms.
      expect(24 * controller.ewmaUnitCost.inMicroseconds, greaterThan(8000));
      expect(controller.batchSize, 18);
      expect(
        controller.batchSize * controller.ewmaUnitCost.inMicroseconds,
        lessThanOrEqualTo(8000),
        reason:
            'The requested batch must respect the cap after additive growth',
      );
    });

    test('sizes the first batch from the measured per-unit cost', () {
      for (final (costUs, expectedUnits) in [(100, 40), (250, 16), (300, 13)]) {
        final controller = AdaptiveSliceController(
          initialUnitCost: Duration(microseconds: costUs),
        );

        expect(controller.batchSize, expectedUnits, reason: 'cost $costUs us');
        expect(controller.ewmaUnitCost, Duration(microseconds: costUs));
      }
    });

    test('allows one unit when its cost exceeds the setpoint', () {
      final controller = AdaptiveSliceController(
        initialUnitCost: const Duration(milliseconds: 5),
      );

      expect(controller.batchSize, 1);
    });
  });

  group('Per-unit cost estimation', () {
    test('weights each per-unit sample by 0.3 and prior cost by 0.7', () {
      final controller = AdaptiveSliceController(
        initialUnitCost: const Duration(microseconds: 100),
      );

      controller.recordSlice(
        units: 10,
        elapsed: const Duration(microseconds: 4000),
      );
      expect(controller.ewmaUnitCost, const Duration(microseconds: 190));

      controller.recordSlice(
        units: 10,
        elapsed: const Duration(microseconds: 3000),
      );
      expect(controller.ewmaUnitCost, const Duration(microseconds: 223));
    });

    test(
      'uses completed units when a slice stops before its planned batch',
      () {
        final controller = AdaptiveSliceController(
          initialUnitCost: const Duration(microseconds: 100),
        );
        expect(controller.batchSize, 40);

        controller.recordSlice(
          units: 5,
          elapsed: const Duration(microseconds: 2000),
        );

        expect(controller.ewmaUnitCost, const Duration(microseconds: 190));
      },
    );
  });

  group('Additive increase and multiplicative decrease', () {
    test('adds eight units after consecutive slices below the setpoint', () {
      final controller = AdaptiveSliceController(
        initialUnitCost: const Duration(microseconds: 100),
      );

      for (final expectedUnits in [48, 56]) {
        controller.recordSlice(
          units: controller.batchSize,
          elapsed: const Duration(milliseconds: 3),
        );

        expect(controller.batchSize, expectedUnits);
      }
    });

    test('treats exactly four milliseconds as on time', () {
      final controller = AdaptiveSliceController(
        initialUnitCost: const Duration(microseconds: 100),
      );

      controller.recordSlice(
        units: 40,
        elapsed: const Duration(milliseconds: 4),
      );

      expect(controller.batchSize, 48);
    });

    test(
      'halves the batch when a slice exceeds the setpoint by one microsecond',
      () {
        final controller = AdaptiveSliceController(
          initialUnitCost: const Duration(microseconds: 100),
        );

        controller.recordSlice(
          units: 40,
          elapsed: const Duration(microseconds: 4001),
        );

        expect(controller.batchSize, 20);
      },
    );

    test(
      'rounds halved batches down and never requests fewer than one unit',
      () {
        final controller = AdaptiveSliceController(
          initialUnitCost: const Duration(microseconds: 300),
        );
        expect(controller.batchSize, 13);

        for (final expectedUnits in [6, 3, 1, 1]) {
          controller.recordSlice(
            units: controller.batchSize,
            elapsed: const Duration(milliseconds: 5),
          );

          expect(controller.batchSize, expectedUnits);
        }
      },
    );

    test('resumes additive growth after an over-budget slice', () {
      final controller = AdaptiveSliceController(
        initialUnitCost: const Duration(microseconds: 100),
      );
      controller.recordSlice(
        units: 40,
        elapsed: const Duration(milliseconds: 5),
      );
      expect(controller.batchSize, 20);

      controller.recordSlice(
        units: 20,
        elapsed: const Duration(milliseconds: 3),
      );

      expect(controller.batchSize, 28);
    });
  });

  group('Convergence after increased unit cost', () {
    for (final (initialCostUs, changedCostUs, behavior) in [
      (50, 500, 'converges within five slices after a large cost increase'),
      (
        100,
        500,
        'converges within five slices when increased cost reaches the unit ceiling',
      ),
      (
        100,
        400,
        'converges within five slices when increased cost stays below the unit ceiling',
      ),
      (250, 500, 'converges within five slices after a small cost increase'),
    ]) {
      test(
        behavior,
        () {
          final controller = AdaptiveSliceController(
            initialUnitCost: Duration(microseconds: initialCostUs),
          );
          final baselineUnits = controller.batchSize;
          controller.recordSlice(
            units: baselineUnits,
            elapsed: Duration(microseconds: baselineUnits * initialCostUs),
          );
          expect(
            controller.ewmaUnitCost,
            Duration(microseconds: initialCostUs),
          );
          final durationsUs = <int>[];
          final requestedWorkUs = <int>[];

          // Measure complete batches so an external scheduler's deadline cannot
          // hide a controller that fails to adapt. The slowest unit is 0.5 ms,
          // matching the bounded-unit contract in the architecture.
          for (var slice = 0; slice < 5; slice++) {
            final units = controller.batchSize;
            final elapsedUs = units * changedCostUs;
            durationsUs.add(elapsedUs);
            expect(units, greaterThanOrEqualTo(1));
            controller.recordSlice(
              units: units,
              elapsed: Duration(microseconds: elapsedUs),
            );
            expect(controller.batchSize, greaterThanOrEqualTo(1));
            requestedWorkUs.add(
              controller.batchSize * controller.ewmaUnitCost.inMicroseconds,
            );
            if (elapsedUs <= 4000 &&
                requestedWorkUs.any((workUs) => workUs <= 4000)) {
              break;
            }
          }

          expect(durationsUs.first, greaterThan(4000));
          expect(
            durationsUs.last,
            lessThanOrEqualTo(4000),
            reason: 'Post-change slice durations in microseconds: $durationsUs',
          );
          // AIMD probes upward by +8 after an on-time slice, so measured and
          // estimated work can reach the target on different iterations.
          // Both must reach it within the same five-slice recovery window.
          expect(
            requestedWorkUs,
            contains(lessThanOrEqualTo(4000)),
            reason:
                'Post-record requested work in microseconds: $requestedWorkUs',
          );
        },
      );
    }
  });
}
