import 'dart:convert';

import 'package:test/test.dart';

import 'constellation_d8_load_model.dart';
import 'constellation_d8_write_evidence_expectations.dart';

// Timestamp names extend the existing write evidence contract. In particular,
// admittedAtMs is the MAIN isolate's dispatch, schedulerAdmittedAtMs is worker
// admission, and startedAtMs is scheduler dispatch BEFORE acquiring Drift's lane.
Map<String, Object?> _write({
  required int sequence,
  double transportMs = 1,
  double admissionWaitMs = 2,
  double laneWaitMs = 3,
  double meritRankMs = 4,
  double dbMs = 5,
}) {
  final admitted = 1000.0 * sequence;
  final received = admitted + transportMs;
  final schedulerAdmitted = received + 5;
  final started = schedulerAdmitted + admissionWaitMs;
  final laneAcquired = started + laneWaitMs;
  final meritRankStarted = laneAcquired + 7;
  final meritRankCompleted = meritRankStarted + meritRankMs;
  final dbStarted = meritRankCompleted + 11;
  final dbCompleted = dbStarted + dbMs;
  final executionCompleted = dbCompleted + 13;
  final encoded = executionCompleted + 3;
  return {
    'computationId': 'write-$sequence',
    'sessionId': 'viewer',
    'admittedAtMs': admitted,
    'receivedAtMs': received,
    'schedulerAdmittedAtMs': schedulerAdmitted,
    'startedAtMs': started,
    'laneAcquiredAtMs': laneAcquired,
    'meritRankStartedAtMs': meritRankStarted,
    'meritRankCompletedAtMs': meritRankCompleted,
    'dbStartedAtMs': dbStarted,
    'dbCompletedAtMs': dbCompleted,
    'executionCompletedAtMs': executionCompleted,
    'encodedAtMs': encoded,
    'completedAtMs': encoded + 7,
    'status': 'applied',
  };
}

Map<String, Object?> _evidence({
  required List<Map<String, Object?>> writes,
  D8Scenario scenario = D8Scenario.publicationBurst,
  D8Level level = D8Level.load,
  List<Map<String, Object?>> unfinishedWrites = const [],
  List<Map<String, Object?>> failedWrites = const [],
}) => {
  'scenario': scenario.label,
  'level': level.name,
  'durationMs': 100000.0,
  'sessions': [
    {'sessionId': 'viewer'},
  ],
  'publications': <Map<String, Object?>>[],
  // All writes are dispatched while a refresh is outstanding. A sample-size
  // verdict therefore cannot fail merely because the fixture was unloaded.
  'completedRefreshes': [
    {
      'sessionId': 'viewer',
      'generation': 1,
      'admittedAtMs': 0.0,
      'startedAtMs': 0.0,
      'completedAtMs': 100000.0,
    },
  ],
  'reconnects': <Map<String, Object?>>[],
  'writes': writes,
  'unfinishedWrites': unfinishedWrites,
  'failedWrites': failedWrites,
  'counters': {
    'writeRequests':
        writes.length + unfinishedWrites.length + failedWrites.length,
  },
};

Map<String, Object?> _jsonEvidence(Map<String, Object?> evidence) =>
    jsonDecode(
          jsonEncode({
            ...evidence,
            'summary': summarizeD8Run(evidence).toJson(),
          }),
        )
        as Map<String, Object?>;

Map<String, Object?> _jsonSummary(Map<String, Object?> evidence) =>
    _jsonEvidence(evidence)['summary']! as Map<String, Object?>;

List<Map<String, Object?>> _componentSamples() => [
  // Each band has ten samples. Components deliberately have different orders:
  // percentiles of timestamp endpoints must not be subtracted to estimate a
  // component, and scheduler dispatch must not be mistaken for lane acquisition.
  for (var i = 1; i <= 10; i++)
    _write(
      sequence: i,
      laneWaitMs: 90,
      meritRankMs: 3,
      dbMs: 4,
    ),
  for (var i = 11; i <= 20; i++)
    _write(
      sequence: i,
      transportMs: 100,
      admissionWaitMs: 20,
      laneWaitMs: 1,
      meritRankMs: 30,
      dbMs: 40,
    ),
  for (var i = 21; i <= 30; i++)
    _write(
      sequence: i,
      transportMs: 10,
      admissionWaitMs: 200,
      laneWaitMs: 9,
      meritRankMs: 300,
      dbMs: 400,
    ),
];

List<Map<String, Object?>> _fastWrites(int count) => [
  for (var i = 1; i <= count; i++) _write(sequence: i, meritRankMs: 1, dbMs: 1),
];

void main() {
  group('D8 write latency components in JSON', () {
    const components = [
      (
        name: 'main-to-worker transport',
        field: 'MainToWorker',
        p50: 10,
        p95: 100,
      ),
      (
        name: 'scheduler admission wait',
        field: 'AdmissionWait',
        p50: 20,
        p95: 200,
      ),
      (name: 'Drift lane wait', field: 'LaneWait', p50: 9, p95: 90),
      (
        name: 'MeritRank visible-set call',
        field: 'MeritRank',
        p50: 30,
        p95: 300,
      ),
      (name: 'database execution', field: 'Db', p50: 40, p95: 400),
      (
        name: 'execution after lane acquisition',
        field: 'Execution',
        p50: 101,
        p95: 731,
      ),
    ];
    for (final component in components) {
      test('${component.name} reports p50 and p95 of per-write durations', () {
        // Input ordering cannot affect nearest-rank percentiles.
        final writes = _componentSamples().reversed.toList();
        final json = _jsonSummary(_evidence(writes: writes));
        expect(json['writes'], 30);
        expect(json['writeP50Ms'], 237);
        expect(json['writeP95Ms'], 965);
        expect(json['write${component.field}P50Ms'], component.p50);
        expect(json['write${component.field}P95Ms'], component.p95);
      });
    }
  });

  group('D8 unfinished writes at the measurement deadline', () {
    test('completed-only windows explicitly report zero unfinished writes', () {
      final json = _jsonSummary(_evidence(writes: _fastWrites(30)));
      expect(json['writes'], 30);
      expect(json['unfinishedWrites'], 0);
    });

    test('reports the pending total separately from completed failures', () {
      final json = _jsonSummary(
        _evidence(
          writes: _fastWrites(30),
          unfinishedWrites: [
            // Still travelling to the worker.
            {'computationId': 'transport', 'admittedAtMs': 99990.0},
            // Waiting for scheduler admission to dispatch.
            {
              'computationId': 'scheduler',
              'admittedAtMs': 99980.0,
              'receivedAtMs': 99981.0,
              'schedulerAdmittedAtMs': 99982.0,
            },
            // Scheduler dispatched, but Drift's lane is occupied.
            {
              'computationId': 'lane',
              'admittedAtMs': 99970.0,
              'receivedAtMs': 99971.0,
              'schedulerAdmittedAtMs': 99972.0,
              'startedAtMs': 99973.0,
            },
            // Work executed, but the main isolate has not received a response.
            {
              'computationId': 'response',
              'admittedAtMs': 99950.0,
              'receivedAtMs': 99951.0,
              'schedulerAdmittedAtMs': 99952.0,
              'startedAtMs': 99953.0,
              'laneAcquiredAtMs': 99954.0,
              'meritRankStartedAtMs': 99955.0,
              'meritRankCompletedAtMs': 99956.0,
              'dbStartedAtMs': 99957.0,
              'dbCompletedAtMs': 99958.0,
              'executionCompletedAtMs': 99959.0,
              'encodedAtMs': 99960.0,
            },
          ],
          failedWrites: [
            {
              'computationId': 'failed',
              'admittedAtMs': 99000.0,
              'completedAtMs': 99010.0,
              'error': 'write rejected',
            },
          ],
        ),
      );
      expect(json['writes'], 30);
      expect(json['unfinishedWrites'], 4);
      expect(json['failedWrites'], 1);
      // Partial timelines must not become zero-latency percentile samples.
      expect(json['writeP95Ms'], 54);
      expect(json['writeDbP95Ms'], 1);
    });

    test(
      'a response after the deadline remains unfinished for this window',
      () {
        final writes = _fastWrites(29)
          ..add(_write(sequence: 30)..['completedAtMs'] = 100000.0)
          ..add({
            ..._write(sequence: 31),
            'completedAtMs': 100001.0,
          });
        final json = _jsonSummary(_evidence(writes: writes));
        // Completion exactly at the deadline counts; draining after the window
        // must not turn an unfinished write into a completed latency sample.
        expect(json['writes'], 30);
        expect(json['unfinishedWrites'], 1);
        expect(json['writeP95Ms'], 54);
      },
    );

    test(
      'pending writes prevent a passing verdict despite 30 fast responses',
      () {
        final evidence = _evidence(
          writes: _fastWrites(30),
          unfinishedWrites: [
            {'computationId': 'pending', 'admittedAtMs': 99999.0},
          ],
        );
        final withoutPending = _jsonSummary(_evidence(writes: _fastWrites(30)));
        expect(withoutPending['writesHold'], isTrue);
        expect(withoutPending['unfinishedWrites'], 0);
        final json = _jsonSummary(evidence);
        expect(json['writes'], withoutPending['writes']);
        expect(json['writeP95Ms'], withoutPending['writeP95Ms']);
        expect(json['writesWithoutOutstandingRefresh'], 0);
        expect(json['unfinishedWrites'], 1);
        expect(json['failedWrites'], 0);
        expect(json['writesHold'], isFalse);
      },
    );
  });

  group('D8 write p95 requires at least 30 completed samples in JSON', () {
    for (final scenario in D8Scenario.values) {
      for (final level in D8Level.values) {
        test(
          '${scenario.label} ${level.name} accepts 30 and rejects 29 at the report boundary',
          () {
            final enough = _jsonEvidence(
              _evidence(
                writes: _fastWrites(30),
                scenario: scenario,
                level: level,
              ),
            );
            final enoughSummary = enough['summary']! as Map<String, Object?>;
            expect(enoughSummary['writes'], 30);
            expect(enoughSummary['writesHold'], isTrue);
            expect(enoughSummary['unfinishedWrites'], 0);
            expect(enoughSummary['failedWrites'], 0);
            expectD8WriteEvidence(enough, requireMinimumSamples: true);

            for (final pending in [false, true]) {
              final tooFew = _jsonEvidence(
                _evidence(
                  writes: _fastWrites(29),
                  scenario: scenario,
                  level: level,
                  unfinishedWrites: pending
                      ? [
                          {'computationId': 'pending', 'admittedAtMs': 99999.0},
                        ]
                      : [],
                ),
              );
              final summary = tooFew['summary']! as Map<String, Object?>;
              expect(summary['writes'], 29);
              expect(summary['unfinishedWrites'], pending ? 1 : 0);
              expect(summary['failedWrites'], 0);
              expect(summary['writeP95Ms'], lessThan(d8WriteP95BudgetMs));
              expect(summary['writesHold'], isFalse);
              // This is the same assertion used on the real build/perf JSON.
              expect(
                () =>
                    expectD8WriteEvidence(tooFew, requireMinimumSamples: true),
                throwsA(isA<TestFailure>()),
              );
              // Scaled smoke reports may have fewer samples, but must still
              // disclose the shortfall through their JSON verdict and counts.
              expectD8WriteEvidence(tooFew, requireMinimumSamples: false);
            }
          },
        );
      }
    }
  });
}
