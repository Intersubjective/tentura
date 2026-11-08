import 'package:test/test.dart';

import '../../support/task_worker_harness.dart';

/// Characterization of the worker's schedule: which jobs one tick runs, in
/// what order, and how often each runs as the clock moves. Every harness fake
/// throws right after it logs, so this also pins that a failing job is still
/// throttled and never stops the jobs after it.
void main() {
  const allJobsInOrder = [
    'trustPublish',
    'closureFinalize',
    'closureDraftReminder',
    'contactResolution',
    'budAnchor',
    'attentionCaptureSettlement',
    'staleRequestReminder',
    'attentionDelivery',
    'hierarchyDelivery',
    'deadlineReminder',
    'postExpiry',
    'postExpiryWarning',
    'planStep',
    'trustMaintenance',
    'blockCascade',
    'blockRelease',
    'imageHash',
    'emailDigest',
    'outboxRetention',
    'imageGc',
    'stageExpiry',
    'capabilityCellExpiry',
    'capabilityTelemetry',
    'witnessWindowGc',
    'capabilityGenerationGc',
    'availabilityCleanup',
  ];

  test('the first tick runs every job once, in schedule order', () async {
    final h = TaskWorkerHarness();
    expect(await h.tickAt(h.now), allJobsInOrder);
  });

  test(
    'a second tick at the same instant runs only the unthrottled job',
    () async {
      final h = TaskWorkerHarness();
      await h.tickAt(h.now);
      expect(await h.tickAt(h.now), ['imageHash']);
    },
  );

  test('each job runs exactly when its interval has elapsed', () async {
    final h = TaskWorkerHarness();
    final start = h.now;
    // Ticks every 5 s for 7 h: a job with interval I runs 1 + floor(7h / I)
    // times (a tick exactly I after the last run is due).
    for (var s = 0; s <= 7 * 3600; s += 5) {
      await h.tickAt(start.add(Duration(seconds: s)));
    }
    final counts = <String, int>{};
    for (final job in h.runs) {
      counts[job] = (counts[job] ?? 0) + 1;
    }
    expect(counts, {
      'trustPublish': 2521, // 10 s
      'closureFinalize': 421, // 60 s
      'closureDraftReminder': 8, // 1 h
      'contactResolution': 211, // env: 2 min in the harness
      'budAnchor': 2521, // 10 s
      'attentionCaptureSettlement': 421, // 1 min
      'staleRequestReminder': 8, // 1 h
      'attentionDelivery': 2521, // 10 s
      'hierarchyDelivery': 2521, // 10 s
      'deadlineReminder': 85, // 5 min
      'postExpiry': 841, // 30 s
      'postExpiryWarning': 421, // 1 min
      'planStep': 841, // 30 s
      'trustMaintenance': 421, // 1 min
      'blockCascade': 421, // 1 min
      'blockRelease': 141, // env: 3 min in the harness
      'imageHash': 5041, // every tick
      'emailDigest': 43, // 10 min
      'outboxRetention': 2, // 6 h
      'imageGc': 841, // 30 s
      'stageExpiry': 85, // 5 min
      'capabilityCellExpiry': 29, // 15 min
      'capabilityTelemetry': 10, // 45 min
      'witnessWindowGc': 8, // 1 h
      'capabilityGenerationGc': 2, // 6 h
      'availabilityCleanup': 2, // 6 h
    });
  });

  test('a job just short of its interval waits for the next tick', () async {
    final h = TaskWorkerHarness();
    final start = h.now;
    await h.tickAt(start);
    final early = await h.tickAt(
      start.add(const Duration(seconds: 9, milliseconds: 999)),
    );
    expect(early, isNot(contains('trustPublish')));
    expect(
      await h.tickAt(start.add(const Duration(seconds: 10))),
      containsAllInOrder(['trustPublish', 'budAnchor', 'attentionDelivery']),
    );
  });

  test(
    'a nudge runs the publisher and the bud sweep on the next tick, once',
    () async {
      final h = TaskWorkerHarness();
      final start = h.now;
      await h.tickAt(start);
      h.trustPublisher.nudge();
      h.budAnchorSweep.nudge();
      final nudged = await h.tickAt(start.add(const Duration(seconds: 1)));
      expect(nudged, ['trustPublish', 'budAnchor', 'imageHash']);
      // The nudged run restarts the 10 s window.
      expect(
        await h.tickAt(start.add(const Duration(seconds: 10))),
        isNot(contains('trustPublish')),
      );
      expect(
        await h.tickAt(start.add(const Duration(seconds: 11))),
        containsAllInOrder(['trustPublish', 'budAnchor']),
      );
    },
  );

  test('with plans disabled the plan step sweep never runs', () async {
    final h = TaskWorkerHarness(planEnabled: false);
    final start = h.now;
    for (var s = 0; s <= 120; s += 30) {
      await h.tickAt(start.add(Duration(seconds: s)));
    }
    expect(h.runs, isNot(contains('planStep')));
    expect(h.runs.where((j) => j == 'postExpiry'), hasLength(5));
  });

  test(
    'the env intervals drive the contact and block release sweeps',
    () async {
      final h = TaskWorkerHarness(
        contactResolutionSweepInterval: const Duration(seconds: 20),
        blockReleaseSweepInterval: const Duration(seconds: 40),
      );
      final start = h.now;
      for (var s = 0; s <= 120; s += 10) {
        await h.tickAt(start.add(Duration(seconds: s)));
      }
      expect(h.runs.where((j) => j == 'contactResolution'), hasLength(7));
      expect(h.runs.where((j) => j == 'blockRelease'), hasLength(4));
    },
  );

  test('the production factory wires every job', () async {
    final h = TaskWorkerHarness();
    final created = await h.create();
    // create() keeps the system clock, so the first tick runs everything.
    await created.tick();
    expect(h.runs, allJobsInOrder);
  });
}
