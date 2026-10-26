import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/utils/post_expiry_clock.dart';

// Consumer contract: PostExpiryClock(clock: DateTime Function(), onTick: callback),
// setDeadlines(Set<DateTime>), dispose(). The fake clock and Timer zone advance
// together; no wall-clock sleeps or private lifecycle callbacks are used.
final _start = DateTime.utc(2026, 10, 26, 12);

PostExpiryClock _clock(FakeAsync async, List<Duration> ticks) =>
    PostExpiryClock(
      clock: () => _start.add(async.elapsed),
      onTick: () => ticks.add(async.elapsed),
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('Post expiry clock deadline notifications', () {
    test('ticks exactly at the nearest deadline and then the next one', () {
      fakeAsync((async) {
        final ticks = <Duration>[];
        final clock = _clock(async, ticks);
        addTearDown(clock.dispose);
        clock.setDeadlines({
          _start.add(const Duration(seconds: 40)),
          _start.add(const Duration(seconds: 10)),
        });
        ticks.clear();

        async.elapse(const Duration(seconds: 9, milliseconds: 999));
        expect(ticks, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(ticks, [const Duration(seconds: 10)]);
        async.elapse(const Duration(seconds: 29, milliseconds: 999));
        expect(ticks, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(ticks, [
          const Duration(seconds: 10),
          const Duration(seconds: 40),
        ]);
      });
    });

    test('rearms for an earlier replacement deadline', () {
      fakeAsync((async) {
        final ticks = <Duration>[];
        final clock = _clock(async, ticks);
        addTearDown(clock.dispose);
        clock.setDeadlines({_start.add(const Duration(seconds: 30))});
        async.elapse(const Duration(seconds: 2));
        clock.setDeadlines({_start.add(const Duration(seconds: 5))});
        ticks.clear();

        async.elapse(const Duration(seconds: 2, milliseconds: 999));
        expect(ticks, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(ticks, [const Duration(seconds: 5)]);
        async.elapse(const Duration(seconds: 30));
        expect(ticks, [const Duration(seconds: 5)]);
      });
    });

    test(
      'cancels the earlier timer when the replacement deadline is later',
      () {
        fakeAsync((async) {
          final ticks = <Duration>[];
          final clock = _clock(async, ticks);
          addTearDown(clock.dispose);
          clock.setDeadlines({_start.add(const Duration(seconds: 5))});
          async.elapse(const Duration(seconds: 2));
          clock.setDeadlines({_start.add(const Duration(seconds: 30))});
          ticks.clear();

          async.elapse(const Duration(seconds: 27, milliseconds: 999));
          expect(ticks, isEmpty);
          async.elapse(const Duration(milliseconds: 1));
          expect(ticks, [const Duration(seconds: 30)]);
        });
      },
    );

    test('clearing the deadline set cancels all scheduled ticks', () {
      fakeAsync((async) {
        final ticks = <Duration>[];
        final clock = _clock(async, ticks);
        addTearDown(clock.dispose);
        clock
          ..setDeadlines({_start.add(const Duration(minutes: 10))})
          ..setDeadlines({});
        ticks.clear();

        expect(async.nonPeriodicTimerCount, 0);
        expect(async.periodicTimerCount, 0);
        async.elapse(const Duration(hours: 2));
        expect(ticks, isEmpty);
      });
    });

    test('expired deadlines do not leave a timer loop running', () {
      fakeAsync((async) {
        final ticks = <Duration>[];
        final clock = _clock(async, ticks);
        addTearDown(clock.dispose);
        clock.setDeadlines({
          _start.subtract(const Duration(seconds: 1)),
          _start,
        });
        ticks.clear();

        async.elapse(const Duration(minutes: 2));
        expect(ticks, isEmpty);
        expect(async.nonPeriodicTimerCount, 0);
        expect(async.periodicTimerCount, 0);
      });
    });
  });

  group('Post expiry clock countdown refresh', () {
    test('ticks once per minute while a deadline is within the last hour', () {
      fakeAsync((async) {
        final ticks = <Duration>[];
        final clock = _clock(async, ticks);
        addTearDown(clock.dispose);
        clock.setDeadlines({_start.add(const Duration(minutes: 59))});
        ticks.clear();

        async.elapse(const Duration(seconds: 59));
        expect(ticks, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(ticks, [const Duration(minutes: 1)]);
        async.elapse(const Duration(minutes: 2));
        expect(ticks, [
          const Duration(minutes: 1),
          const Duration(minutes: 2),
          const Duration(minutes: 3),
        ]);
      });
    });

    test(
      'starts minute refreshes when a distant deadline enters its last hour',
      () {
        fakeAsync((async) {
          final ticks = <Duration>[];
          final clock = _clock(async, ticks);
          addTearDown(clock.dispose);
          clock.setDeadlines({_start.add(const Duration(hours: 2))});
          ticks.clear();

          async.elapse(const Duration(minutes: 59));
          expect(ticks, isEmpty);
          async.elapse(const Duration(minutes: 2));
          expect(ticks, contains(const Duration(minutes: 61)));
          final count = ticks.length;
          async.elapse(const Duration(minutes: 1));
          expect(ticks.length, count + 1);
          expect(ticks.last, const Duration(minutes: 62));
        });
      },
    );
  });

  group('Post expiry clock lifecycle', () {
    test('app resume emits a tick even before the deadline', () {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      fakeAsync((async) {
        final ticks = <Duration>[];
        final clock = _clock(async, ticks);
        addTearDown(clock.dispose);
        clock.setDeadlines({_start.add(const Duration(hours: 2))});
        binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
          ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
        ticks.clear();

        binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(ticks, hasLength(1));
      });
    });

    test('dispose cancels timers and unregisters the resume listener', () {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      fakeAsync((async) {
        final ticks = <Duration>[];
        _clock(async, ticks)
          ..setDeadlines({_start.add(const Duration(minutes: 10))})
          ..dispose();
        ticks.clear();

        expect(async.nonPeriodicTimerCount, 0);
        expect(async.periodicTimerCount, 0);
        async.elapse(const Duration(hours: 3));
        binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
          ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(ticks, isEmpty);
        expect(async.nonPeriodicTimerCount, 0);
        expect(async.periodicTimerCount, 0);
      });
    });
  });
}
