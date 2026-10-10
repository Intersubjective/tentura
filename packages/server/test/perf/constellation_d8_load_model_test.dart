import 'package:test/test.dart';

import 'constellation_d8_load_model.dart';

/// Virtual time for [D8ClientPolicy]: timers fire in due order on [advance].
final class _FakeTime {
  double now = 0;
  final _timers = <({double due, void Function() callback, int id})>[];
  final _cancelled = <int>{};
  var _seq = 0;

  D8TimerHandle schedule(double delayMs, void Function() callback) {
    final id = ++_seq;
    _timers.add((due: now + delayMs, callback: callback, id: id));
    return (cancel: () => _cancelled.add(id));
  }

  void advance(double toMs) {
    while (true) {
      final due = [
        for (final t in _timers)
          if (!_cancelled.contains(t.id) && t.due <= toMs) t,
      ];
      if (due.isEmpty) break;
      final next = due.reduce((a, b) => a.due <= b.due ? a : b);
      _timers.remove(next);
      now = next.due;
      next.callback();
    }
    now = toMs;
  }
}

({D8ClientPolicy policy, List<double> starts, _FakeTime time}) _policy({
  int jitterMs = 0,
}) {
  final time = _FakeTime();
  final starts = <double>[];
  late final D8ClientPolicy policy;
  policy = D8ClientPolicy(
    jitterMs: jitterMs,
    nowMs: () => time.now,
    schedule: time.schedule,
    startFull: () => starts.add(time.now),
  );
  return (policy: policy, starts: starts, time: time);
}

Map<String, Object?> _refresh(
  String session,
  int generation,
  double admitted,
  double started,
  double completed,
) => {
  'sessionId': session,
  'generation': generation,
  'admittedAtMs': admitted,
  'startedAtMs': started,
  'completedAtMs': completed,
};

void main() {
  group('D8 plans', () {
    for (final scenario in D8Scenario.values) {
      for (final level in D8Level.values) {
        test('${scenario.label} ${level.name} observes a full D8 window', () {
          final plan = d8PlanFor(scenario, level);

          expect(plan.publicationsAtMs.first, 0);
          expect(
            plan.durationMs - plan.publicationsAtMs.last,
            greaterThanOrEqualTo(d8StalenessMs),
          );
          if (scenario == D8Scenario.reconnectBurst) {
            final offline = plan.publicationsAtMs.where(
              (t) => t > plan.disconnectAtMs! && t <= plan.reconnectAtMs!,
            );
            expect(offline, isNotEmpty, reason: 'a publication is missed');
          } else {
            expect(plan.disconnectAtMs, isNull);
          }
        });
      }
    }

    test('capacity asks for more refresh rounds than load', () {
      expect(
        d8PlanFor(
          D8Scenario.publicationBurst,
          D8Level.capacity,
        ).publicationsAtMs.length,
        greaterThan(
          d8PlanFor(
            D8Scenario.publicationBurst,
            D8Level.load,
          ).publicationsAtMs.length,
        ),
      );
    });

    test('two tabs per viewer only for concurrent tabs', () {
      expect(D8Scenario.concurrentTabs.tabsPerViewer, 2);
      expect(D8Scenario.publicationBurst.tabsPerViewer, 1);
      expect(D8Scenario.fromSlug('reconnect_burst'), D8Scenario.reconnectBurst);
    });

    test('jitter is stable and within the client 0..3000 ms range', () {
      expect(d8JitterMs('Ud8000000001'), d8JitterMs('Ud8000000001'));
      for (var i = 0; i < 200; i++) {
        expect(d8JitterMs('U$i'), inInclusiveRange(0, 3000));
      }
    });
  });

  group('D8 client policy', () {
    test('a hint dispatches after the 220 ms debounce', () {
      final p = _policy();

      p.policy.onHint();
      p.time.advance(219);
      expect(p.starts, isEmpty);
      p.time.advance(220);

      expect(p.starts, [220]);
    });

    test('a hint soon after a FULL waits for 30 s plus jitter', () {
      final p = _policy(jitterMs: 1500);
      p.policy.onLoadOrCatchUp();
      p.policy.onFullCompleted(ok: true);

      p.time.advance(5000);
      p.policy.onHint();
      p.time.advance(31499);
      expect(p.starts, [0]);
      p.time.advance(31500);

      expect(p.starts, [0, 31500]);
    });

    test('a hint during a FULL queues exactly one more, spaced', () {
      final p = _policy();
      p.policy.onLoadOrCatchUp();

      p.policy
        ..onHint()
        ..onHint();
      p.time.advance(1000);
      p.policy.onFullCompleted(ok: true);
      p.time.advance(100000);

      expect(p.starts, [0, 30000]);
    });

    test('RETRY_LATER is retried once its not-before passes', () {
      final p = _policy();
      p.policy.onLoadOrCatchUp();

      p.time.advance(100);
      p.policy.onFullCompleted(ok: false, retryAfterMs: 2000);
      p.time.advance(2099);
      expect(p.starts, [0]);
      p.time.advance(2100);

      expect(p.starts, [0, 2100]);
      expect(p.policy.retryNotBeforeMs, 2100);
      p.policy.onFullCompleted(ok: true);
      expect(p.policy.retryNotBeforeMs, isNull);
    });

    test('a catch-up joins a FULL in flight instead of starting one', () {
      final p = _policy();
      p.policy
        ..onLoadOrCatchUp()
        ..onLoadOrCatchUp();

      expect(p.starts, [0]);
      p.policy.onFullCompleted(ok: true);
      p.policy.onLoadOrCatchUp();
      expect(p.starts, [0, 0]);
    });
  });

  group('D8 run summary', () {
    Map<String, Object?> evidence({
      List<Map<String, Object?>> reconnects = const [],
      String scenario = 'publication burst',
    }) => {
      'scenario': scenario,
      'durationMs': 400000.0,
      'sessions': [
        {'sessionId': 'a'},
        {'sessionId': 'b'},
      ],
      'publications': [
        {'generation': 1, 'publishedAtMs': 0.0},
        {'generation': 2, 'publishedAtMs': 1000.0},
      ],
      'completedRefreshes': [
        _refresh('a', 2, 30000, 30500, 31000),
        _refresh('b', 1, 500, 900, 1200),
        _refresh('b', 2, 40000, 45000, 46000),
      ],
      'reconnects': reconnects,
      'writes': [
        for (var i = 0; i < 20; i++)
          {'admittedAtMs': 40000.0 + i, 'completedAtMs': 40010.0 + i * 5},
      ],
    };

    test('ages each publication until the first FULL covering it', () {
      final s = summarizeD8Run(evidence());

      // a: generation 1 first covered at 31000; b: generation 2 at 46000,
      // 45000 ms after its publication at 1000.
      expect(s.maxStalenessMs, 45000);
      expect(s.unacknowledged, 0);
      expect(s.completedFulls, 3);
      expect(s.fullPerSecond, closeTo(3 * 1000 / 400000, 1e-12));
      expect(s.maxQueueAgeMs, 5000);
      expect(s.freshnessHolds, isTrue);
    });

    test('write latency runs from request to response', () {
      final s = summarizeD8Run(evidence());

      expect(s.writes, 20);
      expect(s.writeP95Ms, 10 + 18 * 4);
      expect(s.writesWithoutOutstandingRefresh, 0);
    });

    test('a publication missed while offline ages from the reconnect', () {
      final s = summarizeD8Run(
        evidence(
          scenario: 'reconnect burst',
          reconnects: [
            {
              'sessionId': 'b',
              'disconnectedAtMs': 600.0,
              'reconnectedAtMs': 44000.0,
            },
          ],
        ),
      );

      // b missed generation 2 while offline, so it ages 46000 - 44000; the
      // maximum is now a's generation 1 at 31000.
      expect(s.maxStalenessMs, 31000);
    });

    test('an unacknowledged publication fails freshness', () {
      final data = evidence()
        ..['publications'] = [
          {'generation': 1, 'publishedAtMs': 0.0},
          {'generation': 2, 'publishedAtMs': 1000.0},
          {'generation': 3, 'publishedAtMs': 50000.0},
        ];

      final s = summarizeD8Run(data);

      expect(s.unacknowledged, 2);
      expect(s.freshnessHolds, isFalse);
    });
  });
}
