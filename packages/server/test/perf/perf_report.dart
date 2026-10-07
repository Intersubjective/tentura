import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// How the WAL byte figures of a [PerfReport] are to be read.
enum WalAttribution {
  /// No other client session was active around the measured windows, so the
  /// delta belongs to the measured work.
  quietCluster('quiet-cluster'),

  /// Other sessions were active; the delta is the cluster's total WAL.
  clusterTotal('cluster-total');

  const WalAttribution(this.label);

  final String label;
}

/// Nearest-rank percentile ([p] in 0..1) of [samples]; 0 when there are none.
/// Does not reorder [samples].
double nearestRankPercentile(List<double> samples, double p) {
  if (samples.isEmpty) return 0;
  final sorted = [...samples]..sort();
  final rank = (p * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}

/// One measured attempt: admission through response encoding, successful or
/// not. [execution] is the part spent in the work under test itself.
final class PerfAttempt {
  const PerfAttempt({
    required this.latency,
    required this.execution,
    required this.failed,
    required this.queryCount,
    required this.connectorRpcs,
    required this.cursorWait,
    required this.cursorHold,
    required this.connectionQueueTime,
    required this.txAge,
    required this.retryCount,
    required this.walBytes,
    this.lockWaiters = 0,
  });

  final Duration latency;
  final Duration execution;
  final bool failed;
  final int queryCount;
  final int connectorRpcs;
  final Duration cursorWait;
  final Duration cursorHold;
  final Duration connectionQueueTime;
  final Duration txAge;
  final int retryCount;
  final int walBytes;

  /// Most sessions seen queued on a lock in the probed database meanwhile.
  final int lockWaiters;
}

/// A kept `EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON)` result.
final class PerfExplainCapture {
  const PerfExplainCapture({
    required this.label,
    required this.plan,
    required this.rolledBack,
  });

  final String label;
  final Object? plan;

  /// Whether the statement ran inside a transaction that was rolled back.
  final bool rolledBack;

  Map<String, Object?> toJson() => {
    'label': label,
    'rolledBack': rolledBack,
    'plan': plan,
  };
}

/// Aggregates [PerfAttempt]s of one fixture into the JSON written to
/// `build/perf/<fixture>.json`.
final class PerfReport {
  PerfReport({
    required this.fixture,
    this.parameters = const {},
    this.walAttribution = WalAttribution.clusterTotal,
  }) {
    if (!_fixtureName.hasMatch(fixture)) {
      throw ArgumentError.value(
        fixture,
        'fixture',
        'must match ${_fixtureName.pattern}',
      );
    }
  }

  static final _fixtureName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$');

  static Directory get defaultOutputDirectory => Directory('build/perf');

  final String fixture;
  final Map<String, Object?> parameters;
  WalAttribution walAttribution;

  final _attempts = <PerfAttempt>[];
  final _explains = <PerfExplainCapture>[];

  void add(PerfAttempt attempt) => _attempts.add(attempt);

  void addExplain(PerfExplainCapture capture) => _explains.add(capture);

  Map<String, Object?> toJson() {
    final failed = _attempts.where((a) => a.failed).length;
    return {
      'fixture': fixture,
      'parameters': parameters,
      'walAttribution': walAttribution.label,
      'attempts': {
        'total': _attempts.length,
        'failed': failed,
        'succeeded': _attempts.length - failed,
      },
      'latencyMs': _durations((a) => a.latency),
      'executionMs': _durations((a) => a.execution),
      'cursorWaitMs': _durations((a) => a.cursorWait),
      'cursorHoldMs': _durations((a) => a.cursorHold),
      'connectionQueueMs': _durations((a) => a.connectionQueueTime),
      'txAgeMs': _durations((a) => a.txAge),
      'queryCount': _counter((a) => a.queryCount),
      'connectorRpcs': _counter((a) => a.connectorRpcs),
      'retryCount': _counter((a) => a.retryCount),
      'walBytes': _counter((a) => a.walBytes),
      'lockWaiters': {
        'max': _attempts.fold<int>(0, (m, a) => max(m, a.lockWaiters)),
      },
      'explain': [for (final e in _explains) e.toJson()],
    };
  }

  /// Writes `<fixture>.json` into [directory], creating it when needed.
  Future<File> writeTo(Directory directory) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/$fixture.json');
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n',
    );
    return file;
  }

  Map<String, Object?> _durations(Duration Function(PerfAttempt) pick) {
    final ms = [for (final a in _attempts) pick(a).inMicroseconds / 1000];
    return {
      'p50': nearestRankPercentile(ms, 0.50),
      'p95': nearestRankPercentile(ms, 0.95),
    };
  }

  Map<String, Object?> _counter(int Function(PerfAttempt) pick) {
    final values = [for (final a in _attempts) pick(a)];
    final asDouble = [for (final v in values) v.toDouble()];
    return {
      'total': values.fold<int>(0, (sum, v) => sum + v),
      'p50': nearestRankPercentile(asDouble, 0.50),
      'p95': nearestRankPercentile(asDouble, 0.95),
    };
  }
}
