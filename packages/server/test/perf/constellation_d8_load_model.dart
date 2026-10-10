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

/// `load`: four publication bursts 80 s apart (each session refreshes once
/// per burst). `capacity`: a burst every 30 s for 5 minutes, the most the
/// client policy can request (one FULL per session per ~30–33 s).
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
    D8Level.load => const [0, 80000, 160000, 240000],
    D8Level.capacity => [for (var t = 0; t <= 300000; t += 30000) t],
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
    disconnectAtMs: reconnect ? at(load ? 40000 : 95000) : null,
    reconnectAtMs: reconnect ? at(load ? 120000 : 155000) : null,
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
/// than 30 s plus per-account jitter after the previous FULL dispatch); a
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
  static const lazySpacingMs = 30000;

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
/// response.
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
  final int writesWithoutOutstandingRefresh;

  /// Most FULLs completed in any 10 s bucket, per second.
  final double peakFullPerSecond10s;

  bool get freshnessHolds =>
      unacknowledged == 0 && maxStalenessMs <= d8StalenessMs;

  bool get writesHold => writes > 0 && writeP95Ms <= d8WriteP95BudgetMs;

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

  final writes = _list(evidence, 'writes');
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
    writesWithoutOutstandingRefresh: unloaded,
    peakFullPerSecond10s: buckets.isEmpty
        ? 0
        : buckets.values.reduce((a, b) => a > b ? a : b) / 10,
  );
}
