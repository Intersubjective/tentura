import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:tentura_server/data/service/constellation_db_scheduler.dart';

import '../../perf/perf_report.dart' show nearestRankPercentile;

/// Architecture §7.6: 1-op apply p95 budget.
const _writeP95Budget = Duration(milliseconds: 100);

/// Architecture D8: staleness bound for global invalidations.
const _d8Staleness = Duration(minutes: 5);

const _sessions = 1000;
const _applyService = Duration(milliseconds: 10);
const _fullService = Duration(milliseconds: 2);

/// Virtual time: work bodies advance it by their service time, so a run that
/// models minutes of sustained load finishes in milliseconds and every
/// measured age is deterministic.
final class _VirtualClock {
  Duration elapsed = Duration.zero;

  DateTime now() => DateTime.utc(2026).add(elapsed);

  Future<void> serve(Duration service) async => elapsed += service;
}

ConstellationDbScheduler _scheduler(_VirtualClock clock) =>
    ConstellationDbScheduler(
      now: clock.now,
      config: const ConstellationDbSchedulerConfig(
        maxConcurrent: 1,
        maxQueued: 5000,
        queueDeadline: Duration(hours: 1),
      ),
    );

/// Submits work and returns virtual time from submission to completion.
Future<Duration> _timed(
  _VirtualClock clock,
  ConstellationDbScheduler s,
  ConstellationDbWorkKind kind,
  Duration service, {
  void Function()? onStart,
}) async {
  final submitted = clock.elapsed;
  return s.run(kind, () async {
    onStart?.call();
    await clock.serve(service);
    // A later caller continuation can observe the next work's service time.
    return clock.elapsed - submitted;
  });
}

Duration _max(Iterable<Duration> ds) => ds.reduce((a, b) => a > b ? a : b);

void main() {
  group('ConstellationDbScheduler under load', () {
    test('keeps write p95 within budget during a publication storm of 1k '
        'sessions', () async {
      final clock = _VirtualClock();
      final s = _scheduler(clock);
      final writes = <Future<Duration>>[];
      var started = 0;
      final storm = [
        for (var i = 0; i < _sessions; i++)
          _timed(
            clock,
            s,
            ConstellationDbWorkKind.full,
            _fullService,
            onStart: () {
              // An interactive write arrives while every fifth refresh runs.
              if (started++ % 5 == 0) {
                writes.add(
                  _timed(
                    clock,
                    s,
                    ConstellationDbWorkKind.apply,
                    _applyService,
                  ),
                );
              }
            },
          ),
      ];
      await Future.wait(storm);
      final writeMs = [
        for (final d in await Future.wait(writes)) d.inMicroseconds / 1000,
      ];

      expect(writeMs, hasLength(_sessions ~/ 5));
      expect(
        nearestRankPercentile(writeMs, 0.95),
        lessThanOrEqualTo(_writeP95Budget.inMilliseconds),
      );
    });

    test('finishes every refresh within the freshness bound while writes '
        'keep the worker saturated', () async {
      final clock = _VirtualClock();
      final s = _scheduler(clock);
      var writing = true;
      var writesSubmitted = 0;
      void submitWrite() {
        writesSubmitted++;
        unawaited(
          s
              .run(
                ConstellationDbWorkKind.apply,
                () => clock.serve(_applyService),
              )
              .whenComplete(() {
                // Writes saturate the worker for twice the D8 bound.
                if (clock.elapsed >= _d8Staleness * 2) writing = false;
                if (writing) submitWrite();
              }),
        );
      }

      // Every session is invalidated at t=0 by one publication.
      final refreshes = [
        for (var i = 0; i < _sessions; i++)
          _timed(clock, s, ConstellationDbWorkKind.full, _fullService),
      ];
      for (var i = 0; i < 20; i++) {
        submitWrite();
      }
      final staleness = await Future.wait(refreshes);
      final writesStillRunning = writing;
      final finishedAt = clock.elapsed;
      while (writing) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(writesSubmitted, greaterThan(_sessions), reason: 'not saturated');
      expect(
        writesStillRunning,
        isTrue,
        reason: 'refreshes were starved until the writes stopped',
      );
      expect(_max(staleness), lessThan(_d8Staleness));
      expect(finishedAt, lessThan(_d8Staleness));
      expect(s.stats.completedFull, _sessions);
      // The scheduler's own measurement agrees with what was observed.
      expect(s.stats.maxFullStaleness, _max(staleness));
    });

    test('journals FULL rate, queue age and maximum staleness for a 1k '
        'session burst from the scheduler statistics', () async {
      final clock = _VirtualClock();
      final s = _scheduler(clock);
      final staleness = await Future.wait([
        for (var i = 0; i < _sessions; i++)
          _timed(clock, s, ConstellationDbWorkKind.full, _fullService),
      ]);

      // Back to back on one worker: the last refresh waits for the other 999.
      expect(s.stats.completedFull, _sessions);
      expect(s.stats.maxQueueAge, _fullService * (_sessions - 1));
      expect(s.stats.maxFullStaleness, _max(staleness));
      expect(s.stats.maxFullStaleness, _fullService * _sessions);

      final report = {
        'fixture': 'constellation_db_scheduler_publication_burst',
        'sessions': _sessions,
        'fullPerSecond':
            s.stats.completedFull / (clock.elapsed.inMicroseconds / 1e6),
        'maxQueueAgeMs': s.stats.maxQueueAge.inMilliseconds,
        'maxStalenessMs': s.stats.maxFullStaleness.inMilliseconds,
      };
      final file = File(
        'build/perf/constellation_db_scheduler_publication_burst.json',
      )
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(report));

      final back = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(back['fullPerSecond'], 500);
      expect(back['maxQueueAgeMs'], 1998);
      expect(back['maxStalenessMs'], 2000);
    });
  });
}
