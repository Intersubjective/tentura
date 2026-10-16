import 'package:test/test.dart';

import 'perf_report.dart' show nearestRankPercentile;

const d8WriteComponentEndpoints = {
  'MainToWorker': ('admittedAtMs', 'receivedAtMs'),
  'AdmissionWait': ('schedulerAdmittedAtMs', 'startedAtMs'),
  'LaneWait': ('startedAtMs', 'laneAcquiredAtMs'),
  'MeritRank': ('meritRankStartedAtMs', 'meritRankCompletedAtMs'),
  'Db': ('dbStartedAtMs', 'dbCompletedAtMs'),
  'Execution': ('laneAcquiredAtMs', 'executionCompletedAtMs'),
};

/// Shared assertions for the JSON read back from the real build/perf artifact
/// and the model's report-boundary unit tests. No harness or model logic lives
/// here: this checks recorded observations against the report's claims.
void expectD8WriteEvidence(
  Map<String, Object?> evidence, {
  required bool requireMinimumSamples,
}) {
  final duration = (evidence['durationMs']! as num).toDouble();
  final writes = (evidence['writes']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final failed = (evidence['failedWrites']! as List<Object?>)
      .cast<Map<String, Object?>>();
  expect(evidence, contains('unfinishedWrites'));
  final unfinished = (evidence['unfinishedWrites']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final summary = evidence['summary']! as Map<String, Object?>;
  expect(summary['writes'], writes.length);
  expect(summary['failedWrites'], failed.length);
  expect(summary['unfinishedWrites'], unfinished.length);

  // A missing callback at the deadline and a late response both have to remain
  // visible in the artifact. Comparing with the dispatch counter catches writes
  // silently dropped by the old completion-window guard.
  final counters = evidence['counters']! as Map<String, Object?>;
  expect(
    counters['writeRequests'],
    writes.length + failed.length + unfinished.length,
    reason: 'every dispatched write must have a recorded window outcome',
  );
  for (final write in [...writes, ...failed, ...unfinished]) {
    expect(write['admittedAtMs'], isA<num>());
    expect(write['admittedAtMs'], inInclusiveRange(0, duration));
  }
  for (final write in unfinished) {
    final completed = write['completedAtMs'];
    if (completed != null) {
      expect(completed, greaterThan(duration));
    }
  }
  for (final write in writes) {
    expect(write['completedAtMs'], inInclusiveRange(0, duration));
    // These are relative times, not worker epoch timestamps accidentally left
    // untouched by relWrite. Each component must expose both clock endpoints.
    for (final endpoints in d8WriteComponentEndpoints.values) {
      // Since U50 an apply makes no MeritRank call, so that component has no
      // clock endpoints; every other component must expose both.
      if (endpoints.$1.startsWith('meritRank') &&
          write[endpoints.$1] == null &&
          write[endpoints.$2] == null) {
        continue;
      }
      for (final key in [endpoints.$1, endpoints.$2]) {
        expect(write, contains(key), reason: 'completed write lacks $key');
        expect(write[key], inInclusiveRange(0, duration));
      }
      expect(write[endpoints.$2], greaterThanOrEqualTo(write[endpoints.$1]!));
    }
    expect(
      write['laneAcquiredAtMs'],
      greaterThanOrEqualTo(write['startedAtMs']!),
    );
    if (write['meritRankStartedAtMs'] != null) {
      expect(
        write['meritRankStartedAtMs'],
        greaterThanOrEqualTo(write['laneAcquiredAtMs']!),
      );
      expect(
        write['meritRankCompletedAtMs'],
        lessThanOrEqualTo(write['executionCompletedAtMs']!),
      );
    }
    expect(
      write['dbStartedAtMs'],
      greaterThanOrEqualTo(write['laneAcquiredAtMs']!),
    );
    expect(
      write['dbCompletedAtMs'],
      lessThanOrEqualTo(write['executionCompletedAtMs']!),
    );
  }
  for (final entry in d8WriteComponentEndpoints.entries) {
    // As the model: only writes that recorded both endpoints (no MeritRank
    // endpoints since U50).
    final durations = [
      for (final write in writes)
        if (write[entry.value.$1] != null && write[entry.value.$2] != null)
          (write[entry.value.$2]! as num).toDouble() -
              (write[entry.value.$1]! as num).toDouble(),
    ];
    expect(
      summary['write${entry.key}P50Ms'],
      closeTo(nearestRankPercentile(durations, 0.50), 0.01),
    );
    expect(
      summary['write${entry.key}P95Ms'],
      closeTo(nearestRankPercentile(durations, 0.95), 0.01),
    );
  }
  if (requireMinimumSamples) {
    expect(
      writes,
      hasLength(greaterThanOrEqualTo(30)),
      reason:
          'each measured D8 scenario and level needs a meaningful write p95',
    );
  }
  if (writes.length < 30 || unfinished.isNotEmpty) {
    expect(summary['writesHold'], isFalse);
  }
}
