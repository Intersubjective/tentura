import 'package:test/test.dart';

import 'package:tentura_server/domain/use_case/task_worker_case.dart';

import '../../support/task_worker_harness.dart';

/// The sweeps added for closures (A14, A17) and trust publishing: the
/// production factory forwards each one, the worker runs it on its first
/// tick, again exactly when its interval has elapsed and not before, and a
/// `runDue(now:)` sweep gets the worker's clock.
void main() {
  /// Ticks the worker at each of [offsets] after the harness start; returns
  /// the offsets whose tick ran [job].
  Future<List<Duration>> ranAt(
    TaskWorkerHarness h,
    String job,
    List<Duration> offsets, {
    TaskWorkerCase? on,
  }) async {
    final start = h.now;
    final ran = <Duration>[];
    for (final offset in offsets) {
      if ((await h.tickAt(start.add(offset), on: on)).contains(job)) {
        ran.add(offset);
      }
    }
    return ran;
  }

  group('the production factory', () {
    for (final job in [
      'trustPublish',
      'closureFinalize',
      'closureDraftReminder',
      'staleRequestReminder',
    ]) {
      test('forwards the $job sweep', () async {
        final h = TaskWorkerHarness();
        await (await h.create()).tick();
        expect(h.runs, contains(job));
      });
    }
  });

  test('closure finalize runs every 60 s', () async {
    final h = TaskWorkerHarness();
    expect(
      await ranAt(h, 'closureFinalize', const [
        Duration.zero,
        Duration(seconds: 59),
        Duration(seconds: 60),
        Duration(seconds: 119),
        Duration(seconds: 120),
      ]),
      const [Duration.zero, Duration(seconds: 60), Duration(seconds: 120)],
    );
    expect(h.lastCall('closureFinalize').memberName, #dueEpochs);
  });

  test('closure draft reminder runs hourly with the worker clock', () async {
    final h = TaskWorkerHarness();
    expect(
      await ranAt(h, 'closureDraftReminder', const [
        Duration.zero,
        Duration(minutes: 59, seconds: 55),
        Duration(hours: 1),
      ]),
      const [Duration.zero, Duration(hours: 1)],
    );
    final call = h.lastCall('closureDraftReminder');
    expect(call.memberName, #writeDraftReminders);
    expect(call.namedArguments[#now], h.now);
  });

  test('stale request reminder runs hourly with the worker clock', () async {
    final h = TaskWorkerHarness();
    expect(
      await ranAt(h, 'staleRequestReminder', const [
        Duration.zero,
        Duration(minutes: 59, seconds: 55),
        Duration(hours: 1),
      ]),
      const [Duration.zero, Duration(hours: 1)],
    );
    final call = h.lastCall('staleRequestReminder');
    expect(call.memberName, #writeStaleRequestReminders);
    expect(call.namedArguments[#now], h.now);
  });

  test('trust publisher runs every 10 s', () async {
    final h = TaskWorkerHarness();
    expect(
      await ranAt(h, 'trustPublish', const [
        Duration.zero,
        Duration(seconds: 9),
        Duration(seconds: 10),
        Duration(seconds: 19),
        Duration(seconds: 20),
      ]),
      const [Duration.zero, Duration(seconds: 10), Duration(seconds: 20)],
    );
    expect(h.lastCall('trustPublish').memberName, #cutoverPending);
  });
}
