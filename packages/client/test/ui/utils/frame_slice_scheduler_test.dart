import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/scheduling/adaptive_slice_controller.dart';
import 'package:tentura/ui/utils/frame_slice_scheduler.dart';

import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';

// Contract under test (lib/ui/utils/frame_slice_scheduler.dart):
//
//   FrameSliceScheduler({
//     required ClockPort clock,          // deadline measurement
//     required WakeUpPort wakeUpPort,    // independent starvation wake-up
//     required AdaptiveSliceController controller,
//   })
//   void start({required bool Function(int units) step,
//               required void Function() onComplete})
//       // replaces (cancels) any running job; step returns true when done
//   void cancel()
//   void dispose()
//
// A slice calls `step(1)` repeatedly, checking the clock after each unit, and
// stops once the controller's setpoint (4 ms) elapsed. Slices are posted with
// `Priority.idle`; when idle tasks are starved for 100 ms the wake-up port
// re-posts the job at `Priority.animation`. At most one slice runs per frame.
// Pointer down pauses the job until the pointer is released.
//
// Every fake unit below "costs" 5 ms on the fake clock, which is over the
// setpoint, so one slice is exactly one `step(1)` call.
const _unitCost = Duration(milliseconds: 5);
const _frame = Duration(milliseconds: 16);

void main() {
  group('Frame slice scheduler', () {
    late FakeClockPort clock;
    late FakeWakeUpPort wakeUp;
    late FrameSliceScheduler scheduler;
    late AdaptiveSliceController controller;
    late int frameIndex;

    /// Frame index at the time of each `step` call, in call order.
    late List<int> stepFrames;
    var completions = 0;

    bool Function(int) stepper({required int totalUnits}) {
      var done = 0;
      return (units) {
        expectSync(units, 1, reason: 'the deadline is checked after every unit');
        stepFrames.add(frameIndex);
        clock.advance(_unitCost);
        done += units;
        return done >= totalUnits;
      };
    }

    /// One frame of fake time for both the frame pipeline and the wake-up
    /// port (the port's timers fire only when time is elapsed on it).
    Future<void> pumpFrame(WidgetTester tester) async {
      wakeUp.elapse(_frame);
      await tester.pump(_frame);
    }

    /// Drops the job and lets the binding drain tasks it already queued, so
    /// no scheduler timer outlives the test.
    Future<void> finish(WidgetTester tester) async {
      scheduler.dispose();
      await pumpFrame(tester);
    }

    setUp(() {
      clock = FakeClockPort();
      wakeUp = FakeWakeUpPort();
      frameIndex = 0;
      stepFrames = [];
      completions = 0;
      controller = AdaptiveSliceController(
        initialUnitCost: const Duration(microseconds: 100),
      );
      scheduler = FrameSliceScheduler(
        clock: clock,
        wakeUpPort: wakeUp,
        controller: controller,
      );
    });

    testWidgets('runs a job to completion without any animation', (
      tester,
    ) async {
      tester.binding.addPersistentFrameCallback((_) => frameIndex++);

      scheduler.start(
        step: stepper(totalUnits: 3),
        onComplete: () => completions++,
      );
      for (var i = 0; i < 10; i++) {
        await pumpFrame(tester);
      }

      expect(stepFrames, hasLength(3));
      expect(completions, 1);
      await finish(tester);
    });

    testWidgets('never runs two slices in the same frame', (tester) async {
      tester.binding.addPersistentFrameCallback((_) => frameIndex++);

      scheduler.start(
        step: stepper(totalUnits: 6),
        onComplete: () => completions++,
      );
      for (var i = 0; i < 20; i++) {
        await pumpFrame(tester);
      }

      expect(stepFrames, hasLength(6));
      expect(
        stepFrames.toSet(),
        hasLength(stepFrames.length),
        reason: 'each slice must land in its own frame: $stepFrames',
      );
      expect(completions, 1);
      await finish(tester);
    });

    testWidgets('slice stops at the setpoint instead of the batch estimate', (
      tester,
    ) async {
      // Controller thinks a unit costs 100 us, so its batch is ~40 units.
      expect(controller.batchSize, greaterThan(1));
      tester.binding.addPersistentFrameCallback((_) => frameIndex++);

      scheduler.start(
        step: stepper(totalUnits: 5),
        onComplete: () => completions++,
      );
      await pumpFrame(tester);
      await pumpFrame(tester);

      expect(
        stepFrames.length,
        lessThanOrEqualTo(2),
        reason: 'two frames, at most one 5 ms unit per slice',
      );
      await finish(tester);
    });

    group('under continuous animation', () {
      testWidgets('still makes progress and completes the job', (tester) async {
        tester.binding.addPersistentFrameCallback((_) => frameIndex++);
        final ticker = Ticker((_) {})..start();

        scheduler.start(
          step: stepper(totalUnits: 3),
          onComplete: () => completions++,
        );
        // ~3.2 s of uninterrupted animation: idle tasks never get to run, so
        // every unit must come from the starvation wake-up.
        for (var i = 0; i < 200; i++) {
          await pumpFrame(tester);
        }

        expect(stepFrames, hasLength(3));
        expect(completions, 1);
        ticker.dispose();
        await finish(tester);
      });

      testWidgets('never runs two slices in one frame while promoted', (
        tester,
      ) async {
        tester.binding.addPersistentFrameCallback((_) => frameIndex++);
        final ticker = Ticker((_) {})..start();

        scheduler.start(
          step: stepper(totalUnits: 4),
          onComplete: () => completions++,
        );
        for (var i = 0; i < 200; i++) {
          await pumpFrame(tester);
        }

        expect(stepFrames, hasLength(4));
        expect(stepFrames.toSet(), hasLength(stepFrames.length));
        ticker.dispose();
        await finish(tester);
      });

      testWidgets('does not run before the 100 ms starvation window', (
        tester,
      ) async {
        tester.binding.addPersistentFrameCallback((_) => frameIndex++);
        final ticker = Ticker((_) {})..start();

        scheduler.start(
          step: stepper(totalUnits: 3),
          onComplete: () => completions++,
        );
        for (var i = 0; i < 5; i++) {
          await pumpFrame(tester); // 80 ms
        }

        expect(stepFrames, isEmpty);
        ticker.dispose();
        await finish(tester);
      });
    });

    group('when a frame stalls', () {
      testWidgets('wakes the job exactly once, with no duplicate execution', (
        tester,
      ) async {
        tester.binding.addPersistentFrameCallback((_) => frameIndex++);
        final ticker = Ticker((_) {})..start();

        scheduler.start(
          step: stepper(totalUnits: 3),
          onComplete: () => completions++,
        );
        await tester.pump(_frame);
        expect(stepFrames, isEmpty);

        // One long stall: a 120 ms frame. Both the original idle task and the
        // wake-up are now eligible, but the job token allows only one slice.
        wakeUp.elapse(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 120));

        expect(stepFrames, hasLength(1));
        expect(completions, 0);
        ticker.dispose();
        await finish(tester);
      });

      testWidgets('executes each unit exactly once across promotion and idle', (
        tester,
      ) async {
        tester.binding.addPersistentFrameCallback((_) => frameIndex++);
        final ticker = Ticker((_) {})..start();

        scheduler.start(
          step: stepper(totalUnits: 2),
          onComplete: () => completions++,
        );
        await tester.pump(_frame);
        wakeUp.elapse(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 120));

        // Animation ends: the idle task that was starved may now run. It must
        // not execute the job a second time.
        ticker.dispose();
        for (var i = 0; i < 40; i++) {
          await pumpFrame(tester);
        }

        expect(stepFrames, hasLength(2));
        expect(completions, 1);
        await finish(tester);
      });

      testWidgets('keeps no wake-up pending once the job is done', (
        tester,
      ) async {
        tester.binding.addPersistentFrameCallback((_) => frameIndex++);

        scheduler.start(
          step: stepper(totalUnits: 1),
          onComplete: () => completions++,
        );
        for (var i = 0; i < 10; i++) {
          await pumpFrame(tester);
        }

        expect(completions, 1);
        expect(wakeUp.pendingCount, 0);
        await finish(tester);
      });
    });

    group('pausing on pointer down', () {
      testWidgets('runs no slice while a pointer is down, then resumes', (
        tester,
      ) async {
        tester.binding.addPersistentFrameCallback((_) => frameIndex++);

        final gesture = await tester.startGesture(const Offset(20, 20));
        scheduler.start(
          step: stepper(totalUnits: 3),
          onComplete: () => completions++,
        );
        for (var i = 0; i < 20; i++) {
          await pumpFrame(tester);
        }
        expect(stepFrames, isEmpty);

        await gesture.up();
        for (var i = 0; i < 20; i++) {
          await pumpFrame(tester);
        }

        expect(stepFrames, hasLength(3));
        expect(completions, 1);
        await finish(tester);
      });

      testWidgets('is not fooled by the starvation wake-up while paused', (
        tester,
      ) async {
        tester.binding.addPersistentFrameCallback((_) => frameIndex++);
        final ticker = Ticker((_) {})..start();

        final gesture = await tester.startGesture(const Offset(20, 20));
        addTearDown(gesture.up);
        scheduler.start(
          step: stepper(totalUnits: 3),
          onComplete: () => completions++,
        );
        for (var i = 0; i < 60; i++) {
          await pumpFrame(tester);
        }

        expect(stepFrames, isEmpty);
        ticker.dispose();
        await finish(tester);
      });
    });

    group('replacing a job', () {
      testWidgets('a newer job cancels the running one', (tester) async {
        tester.binding.addPersistentFrameCallback((_) => frameIndex++);
        var firstCompletions = 0;
        var firstSteps = 0;
        var secondSteps = 0;

        scheduler.start(
          step: (units) {
            firstSteps++;
            clock.advance(_unitCost);
            return firstSteps >= 5;
          },
          onComplete: () => firstCompletions++,
        );
        await pumpFrame(tester);
        await pumpFrame(tester);
        final firstBeforeReplace = firstSteps;

        scheduler.start(
          step: (units) {
            secondSteps++;
            clock.advance(_unitCost);
            return secondSteps >= 2;
          },
          onComplete: () => completions++,
        );
        for (var i = 0; i < 20; i++) {
          await pumpFrame(tester);
        }

        expect(firstSteps, firstBeforeReplace);
        expect(firstCompletions, 0);
        expect(secondSteps, 2);
        expect(completions, 1);
        await finish(tester);
      });

      testWidgets('cancel stops the job and leaves no wake-up pending', (
        tester,
      ) async {
        tester.binding.addPersistentFrameCallback((_) => frameIndex++);
        final ticker = Ticker((_) {})..start();

        scheduler
          ..start(
            step: stepper(totalUnits: 3),
            onComplete: () => completions++,
          )
          ..cancel();
        for (var i = 0; i < 40; i++) {
          await pumpFrame(tester);
        }

        expect(stepFrames, isEmpty);
        expect(completions, 0);
        expect(wakeUp.pendingCount, 0);
        ticker.dispose();
        await finish(tester);
      });
    });
  });
}
