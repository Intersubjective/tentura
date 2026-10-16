// Pure parts of the D8 load test (#235 U26): the declared contract, the
// scenario timelines, the client refresh policy the simulated sessions follow
// and the metrics computed from the recorded events. No I/O here, so the
// policy and the metrics are unit-tested (constellation_d8_load_model_test).

import 'perf_report.dart' show nearestRankPercentile;

/// ARCH §0 D8 (owner-confirmed 2026-10-06): declared active sessions.
const d8Sessions = 1000;

/// ARCH §0 D8: staleness bound for global invalidations while visible.
const d8StalenessMs = 5 * 60 * 1000;

/// ARCH §7.3: the demand if every session refreshes once per D8 window.
const d8DemandFullPerSecond = d8Sessions * 1000 / d8StalenessMs;

/// U26: sustainable capacity must exceed D8 demand by at least this share.
const d8MinimumHeadroom = 0.30;

/// The frozen U41 budget a write is held to (1-op apply, warm MR, p95).
const d8WriteP95BudgetMs = 70.0;

/// One write per this many FULL requests, as the U47 / U26 acceptance states.
const d8ReadsPerWrite = 100;

/// Completed writes a scenario needs before its nearest-rank p95 means
/// anything (with fewer, the p95 is just the slowest write).
const d8WriteMinimumSamples = 30;

/// Write latency components: the recorded clock endpoints each is measured
/// between. `schedulerAdmittedAtMs` is the entry to the main-pool connection
/// scope, `startedAtMs` the moment the pool admission granted it a slot and
/// leased a connection (BEFORE the transaction), `laneAcquiredAtMs` the first
/// moment the transaction runs. The MR call is the visible-set statement (none
/// in a write since U50); the DB span runs from the first to the last
/// statement of the transaction.
const d8WriteComponents = {
  'MainToWorker': ('admittedAtMs', 'receivedAtMs'),
  'AdmissionWait': ('schedulerAdmittedAtMs', 'startedAtMs'),
  'LaneWait': ('startedAtMs', 'laneAcquiredAtMs'),
  'MeritRank': ('meritRankStartedAtMs', 'meritRankCompletedAtMs'),
  'Db': ('dbStartedAtMs', 'dbCompletedAtMs'),
  'Execution': ('laneAcquiredAtMs', 'executionCompletedAtMs'),
};

enum D8Scenario {
  publicationBurst('publication burst', 'publication_burst'),
  reconnectBurst('reconnect burst', 'reconnect_burst'),
  concurrentTabs('concurrent tabs', 'concurrent_tabs');

  const D8Scenario(this.label, this.slug);

  final String label;
  final String slug;

  int get tabsPerViewer => this == D8Scenario.concurrentTabs ? 2 : 1;

  static D8Scenario fromSlug(String slug) =>
      values.singleWhere((s) => s.slug == slug.trim());
}

/// `load`: four publication bursts one staleness window apart (each session
/// refreshes once per burst). `capacity`: a burst every window for 30 minutes,
/// the most the client policy can request (one FULL per session per window).
enum D8Level { load, capacity }

/// A scenario timeline in milliseconds from the run's start (t0 = the first
/// publication). The run lasts until a full D8 window after the last
/// publication, so every publication's freshness deadline is observed.
final class D8Plan {
  const D8Plan({
    required this.publicationsAtMs,
    required this.durationMs,
    this.disconnectAtMs,
    this.reconnectAtMs,
  });

  final List<int> publicationsAtMs;
  final int durationMs;
  final int? disconnectAtMs;
  final int? reconnectAtMs;

  Map<String, Object?> toJson() => {
    'publicationsAtMs': publicationsAtMs,
    'durationMs': durationMs,
    'disconnectAtMs': disconnectAtMs,
    'reconnectAtMs': reconnectAtMs,
  };
}

/// Publications per burst and their spacing: several trust changes in a few
/// seconds, which the server coalesces into one broadcast.
const d8BurstSize = 5;
const d8BurstSpacingMs = 1000;

/// [scale] < 1 compresses every time of the plan, for a smoke run of the
/// harness only (a scaled run is not D8 evidence).
D8Plan d8PlanFor(D8Scenario scenario, D8Level level, {double scale = 1}) {
  int at(int ms) => (ms * scale).round();
  final bursts = switch (level) {
    D8Level.load => [for (var i = 0; i < 4; i++) i * d8StalenessMs],
    D8Level.capacity => [for (var i = 0; i < 7; i++) i * d8StalenessMs],
  };
  final publications = [
    for (final start in bursts)
      for (var i = 0; i < d8BurstSize; i++) at(start + i * d8BurstSpacingMs),
  ];
  final reconnect = scenario == D8Scenario.reconnectBurst;
  final load = level == D8Level.load;
  return D8Plan(
    publicationsAtMs: publications,
    durationMs: publications.last + at(d8StalenessMs + 1000),
    // Offline across one burst (load) or two (capacity), then every session
    // reconnects at once and catches up.
    disconnectAtMs: reconnect ? at(load ? 150000 : 450000) : null,
    reconnectAtMs: reconnect ? at(load ? 450000 : 750000) : null,
  );
}

/// Stable stand-in for the client's `accountId.hashCode.abs() % 3001` jitter
/// (Dart string hash codes are not stable across runs): FNV-1a, 32 bit.
int d8JitterMs(String accountId) {
  var hash = 0x811c9dc5;
  for (final unit in accountId.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash % 3001;
}

typedef D8TimerHandle = ({void Function() cancel});

/// The FULL scheduling of the client `ConstellationFieldStoreCase`
/// (packages/client .../constellation_field_store_case.dart) for a visible
/// field: global field hints are non-urgent (220 ms debounce, never sooner
/// than the D8 window (5 min) plus per-account jitter after the previous FULL dispatch); a
/// load or catch-up dispatches at once (joining a FULL in flight); a hint
/// during a FULL queues one more; RETRY_LATER is honoured as a not-before.
final class D8ClientPolicy {
  D8ClientPolicy({
    required this.jitterMs,
    required this.nowMs,
    required this.schedule,
    required this.startFull,
  });

  static const debounceMs = 220;
  static const urgentSpacingMs = 2000;
  static const lazySpacingMs = d8StalenessMs;

  final int jitterMs;
  final double Function() nowMs;
  final D8TimerHandle Function(double delayMs, void Function() callback)
  schedule;
  final void Function() startFull;

  double? lastFullAtMs;
  double? retryNotBeforeMs;
  bool inFlight = false;
  bool _queued = false;
  bool _queuedUrgent = false;
  D8TimerHandle? _timer;
  double? _dueAtMs;

  bool get hasPendingTimer => _timer != null;

  /// A global `constellation_field` hint (non-urgent).
  void onHint() => _schedule(urgent: false);

  /// Opening the field, resume or reconnect catch-up.
  void onLoadOrCatchUp() => _dispatch();

  void onFullCompleted({required bool ok, double? retryAfterMs}) {
    inFlight = false;
    if (ok) {
      retryNotBeforeMs = null;
    } else if (retryAfterMs != null) {
      retryNotBeforeMs = nowMs() + retryAfterMs;
      _queued = true;
    }
    if (_queued) {
      final urgent = _queuedUrgent;
      _queued = false;
      _queuedUrgent = false;
      _schedule(urgent: urgent, immediate: retryNotBeforeMs != null);
    }
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _dueAtMs = null;
  }

  void _schedule({bool urgent = true, bool immediate = false}) {
    if (inFlight) {
      _queued = true;
      _queuedUrgent |= urgent;
      return;
    }
    final now = nowMs();
    final spacing = urgent ? urgentSpacingMs : lazySpacingMs + jitterMs;
    final last = lastFullAtMs;
    var due = immediate ? now : now + debounceMs;
    if (!immediate && last != null && last + spacing > due) {
      due = last + spacing;
    }
    final retry = retryNotBeforeMs;
    if (retry != null && retry > due) due = retry;
    final pending = _dueAtMs;
    if (_timer != null && pending != null && pending <= due) return;
    _timer?.cancel();
    _dueAtMs = due;
    _timer = schedule(due - now, () {
      _timer = null;
      _dueAtMs = null;
      _dispatch();
    });
  }

  void _dispatch() {
    if (inFlight) return;
    final retry = retryNotBeforeMs;
    if (retry != null && nowMs() < retry) {
      _schedule(immediate: true);
      return;
    }
    cancel();
    lastFullAtMs = nowMs();
    inFlight = true;
    startFull();
  }
}

/// What the run measured, computed from its event records exactly as the
/// release evidence is read: FULL/s counts completed responses; staleness runs
/// from each publication (or from reconnecting, for one missed while offline)
/// until the session's first FULL of that generation or newer that started
/// after it; queue age is admission to execution; write latency is request to
/// response, over the writes answered within the window. A write without a
/// response by the window's end is counted as unfinished, never sampled.
final class D8RunSummary {
  const D8RunSummary({
    required this.durationMs,
    required this.completedFulls,
    required this.fullPerSecond,
    required this.maxStalenessMs,
    required this.stalenessP95Ms,
    required this.unacknowledged,
    required this.maxQueueAgeMs,
    required this.writes,
    required this.writeP50Ms,
    required this.writeP95Ms,
    required this.writeComponentsMs,
    required this.unfinishedWrites,
    required this.failedWrites,
    required this.writesWithoutOutstandingRefresh,
    required this.peakFullPerSecond10s,
  });

  final double durationMs;
  final int completedFulls;
  final double fullPerSecond;
  final double maxStalenessMs;
  final double stalenessP95Ms;

  /// (session, publication) pairs never acknowledged within the run.
  final int unacknowledged;
  final double maxQueueAgeMs;
  final int writes;
  final double writeP50Ms;
  final double writeP95Ms;

  /// Per [d8WriteComponents] name, the (p50, p95) of that component's
  /// per-write duration over the completed writes that recorded both endpoints.
  final Map<String, (double, double)> writeComponentsMs;

  /// Writes dispatched in the window that had no response by its end.
  final int unfinishedWrites;

  /// Writes answered within the window with an error.
  final int failedWrites;
  final int writesWithoutOutstandingRefresh;

  /// Most FULLs completed in any 10 s bucket, per second.
  final double peakFullPerSecond10s;

  bool get freshnessHolds =>
      unacknowledged == 0 && maxStalenessMs <= d8StalenessMs;

  bool get writesHold =>
      writes >= d8WriteMinimumSamples &&
      unfinishedWrites == 0 &&
      writeP95Ms <= d8WriteP95BudgetMs;

  Map<String, Object?> toJson() => {
    'durationMs': durationMs,
    'completedFulls': completedFulls,
    'fullPerSecond': fullPerSecond,
    'peakFullPerSecond10s': peakFullPerSecond10s,
    'maxStalenessMs': maxStalenessMs,
    'stalenessP95Ms': stalenessP95Ms,
    'unacknowledged': unacknowledged,
    'maxQueueAgeMs': maxQueueAgeMs,
    'writes': writes,
    'writeP50Ms': writeP50Ms,
    'writeP95Ms': writeP95Ms,
    for (final entry in writeComponentsMs.entries) ...{
      'write${entry.key}P50Ms': entry.value.$1,
      'write${entry.key}P95Ms': entry.value.$2,
    },
    'unfinishedWrites': unfinishedWrites,
    'failedWrites': failedWrites,
    'writesWithoutOutstandingRefresh': writesWithoutOutstandingRefresh,
    'freshnessHolds': freshnessHolds,
    'writesHold': writesHold,
  };
}

double _num(Map<String, Object?> event, String key) =>
    (event[key]! as num).toDouble();

List<Map<String, Object?>> _list(Map<String, Object?> data, String key) => [
  for (final e in data[key]! as List<Object?>) e! as Map<String, Object?>,
];

D8RunSummary summarizeD8Run(Map<String, Object?> evidence) {
  final duration = _num(evidence, 'durationMs');
  final sessions = [
    for (final s in _list(evidence, 'sessions')) s['sessionId']! as String,
  ];
  final completed = _list(evidence, 'completedRefreshes');
  final publications = _list(evidence, 'publications')
    ..sort(
      (a, b) => _num(a, 'publishedAtMs').compareTo(_num(b, 'publishedAtMs')),
    );
  final reconnects = evidence['scenario'] == D8Scenario.reconnectBurst.label
      ? _list(evidence, 'reconnects')
      : const <Map<String, Object?>>[];
  final bySession = <String, List<Map<String, Object?>>>{};
  for (final r in completed) {
    bySession.putIfAbsent(r['sessionId']! as String, () => []).add(r);
  }
  final reconnectsBySession = <String, List<Map<String, Object?>>>{};
  for (final r in reconnects) {
    reconnectsBySession.putIfAbsent(r['sessionId']! as String, () => []).add(r);
  }

  var maximum = 0.0;
  var unacknowledged = 0;
  final ages = <double>[];
  for (final publication in publications) {
    final published = _num(publication, 'publishedAtMs');
    final generation = _num(publication, 'generation');
    for (final session in sessions) {
      var visibleSince = published;
      for (final r
          in reconnectsBySession[session] ?? const <Map<String, Object?>>[]) {
        if (_num(r, 'disconnectedAtMs') < published &&
            _num(r, 'reconnectedAtMs') >= published) {
          visibleSince = _num(r, 'reconnectedAtMs');
        }
      }
      double? first;
      for (final r in bySession[session] ?? const <Map<String, Object?>>[]) {
        if (_num(r, 'generation') >= generation &&
            _num(r, 'startedAtMs') >= visibleSince) {
          final end = _num(r, 'completedAtMs');
          if (first == null || end < first) first = end;
        }
      }
      if (first == null) {
        unacknowledged++;
        continue;
      }
      final age = first - visibleSince;
      ages.add(age);
      if (age > maximum) maximum = age;
    }
  }

  var maxQueue = 0.0;
  final buckets = <int, int>{};
  for (final r in completed) {
    final queue = _num(r, 'startedAtMs') - _num(r, 'admittedAtMs');
    if (queue > maxQueue) maxQueue = queue;
    final bucket = _num(r, 'completedAtMs') ~/ 10000;
    buckets[bucket] = (buckets[bucket] ?? 0) + 1;
  }

  // A response after the deadline is not a sample of this window.
  final answered = _list(evidence, 'writes');
  final writes = [
    for (final w in answered)
      if (_num(w, 'completedAtMs') <= duration) w,
  ];
  final unfinished =
      (evidence['unfinishedWrites'] as List<Object?>? ?? const []).length +
      answered.length -
      writes.length;
  final failed =
      (evidence['failedWrites'] as List<Object?>? ?? const []).length;
  final writeMs = [
    for (final w in writes) _num(w, 'completedAtMs') - _num(w, 'admittedAtMs'),
  ];
  var unloaded = 0;
  for (final w in writes) {
    final admitted = _num(w, 'admittedAtMs');
    final outstanding = completed.any(
      (r) =>
          _num(r, 'admittedAtMs') <= admitted &&
          _num(r, 'completedAtMs') >= admitted,
    );
    if (!outstanding) unloaded++;
  }

  return D8RunSummary(
    durationMs: duration,
    completedFulls: completed.length,
    fullPerSecond: completed.length * 1000 / duration,
    maxStalenessMs: maximum,
    stalenessP95Ms: nearestRankPercentile(ages, 0.95),
    unacknowledged: unacknowledged,
    maxQueueAgeMs: maxQueue,
    writes: writes.length,
    writeP50Ms: nearestRankPercentile(writeMs, 0.50),
    writeP95Ms: nearestRankPercentile(writeMs, 0.95),
    writeComponentsMs: {
      for (final MapEntry(key: name, value: (from, to))
          in d8WriteComponents.entries)
        name: () {
          final durations = [
            for (final w in writes)
              if (w[from] != null && w[to] != null) _num(w, to) - _num(w, from),
          ];
          return (
            nearestRankPercentile(durations, 0.50),
            nearestRankPercentile(durations, 0.95),
          );
        }(),
    },
    unfinishedWrites: unfinished,
    failedWrites: failed,
    writesWithoutOutstandingRefresh: unloaded,
    peakFullPerSecond10s: buckets.isEmpty
        ? 0
        : buckets.values.reduce((a, b) => a > b ? a : b) / 10,
  );
}
