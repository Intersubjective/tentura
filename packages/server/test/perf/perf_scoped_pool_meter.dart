import 'dart:async';

import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import 'perf_report.dart';

/// A [TenturaDb] over the production scoped [MainDbPool] that times each
/// outermost connection scope opened by measured work.
///
/// Only scopes opened inside [collect] are sampled. Per scope it records the
/// wait before the body runs (split into admission wait when the admission had
/// no free slot at entry, lease wait otherwise: the lease is not observable
/// from outside the pool), the time the body holds the leased connection (the
/// serialised lane) and, from the viewer cursor `FOR UPDATE` statement to the
/// end of the body, the cursor hold (an upper bound: it includes the lock wait).
final class MeteredScopedDb extends TenturaDb {
  MeteredScopedDb(this.mainPool) : super.scoped(mainPool);

  static final Object _collectKey = Object();
  static final Object _inScopeKey = Object();
  static final _cursorLock = RegExp(
    r'constellation_anchor_cursor\s+WHERE\s+viewer_id\s*=\s*\$1\s+FOR UPDATE',
    caseSensitive: false,
  );

  final MainDbPool mainPool;
  final leaseWaitMs = <double>[];
  final admissionWaitMs = <double>[];
  final laneBusyMs = <double>[];
  Duration _cursorHold = Duration.zero;
  Stopwatch? _cursorClock;

  /// Runs [work] with its connection scopes sampled.
  Future<T> collect<T>(Future<T> Function() work) =>
      runZoned(work, zoneValues: {_collectKey: true});

  /// Cursor hold of the scopes since the last call, and resets it.
  Duration takeCursorHold() {
    final hold = _cursorHold;
    _cursorHold = Duration.zero;
    return hold;
  }

  void clear() {
    leaseWaitMs.clear();
    admissionWaitMs.clear();
    laneBusyMs.clear();
    _cursorHold = Duration.zero;
  }

  @override
  Future<T> withConnectionScope<T>(
    Future<T> Function() action, {
    String? actorUserId,
    MainDbWorkKind? kind,
  }) {
    if (Zone.current[_collectKey] != true ||
        Zone.current[_inScopeKey] == true) {
      return super.withConnectionScope(
        action,
        actorUserId: actorUserId,
        kind: kind,
      );
    }
    final admission = mainPool.admission;
    final admitsNow =
        admission.queued == 0 && admission.running < admission.maxConcurrent;
    final entry = Stopwatch()..start();
    Stopwatch? lane;
    return super.withConnectionScope(
      () async {
        final wait = entry.elapsedMicroseconds / 1000;
        (admitsNow ? leaseWaitMs : admissionWaitMs).add(wait);
        (admitsNow ? admissionWaitMs : leaseWaitMs).add(0);
        lane = Stopwatch()..start();
        _cursorClock = null;
        try {
          return await runZoned(action, zoneValues: {_inScopeKey: true});
        } finally {
          laneBusyMs.add(lane!.elapsedMicroseconds / 1000);
          final holding = _cursorClock;
          if (holding != null) _cursorHold += holding.elapsed;
          _cursorClock = null;
        }
      },
      actorUserId: actorUserId,
      kind: kind,
    );
  }

  @override
  Selectable<QueryRow> customSelect(
    String query, {
    List<Variable<Object>> variables = const [],
    Set<ResultSetImplementation<dynamic, dynamic>> readsFrom = const {},
  }) {
    if (Zone.current[_inScopeKey] == true && _cursorLock.hasMatch(query)) {
      _cursorClock = Stopwatch()..start();
    }
    return super.customSelect(
      query,
      variables: variables,
      readsFrom: readsFrom,
    );
  }

  /// The `poolDiagnostics` section of a report: per-scope wait and lane time
  /// and what dominates them at the 95th percentile.
  Map<String, Object?> diagnostics() {
    Map<String, Object?> stat(List<double> ms) => {
      'p50': nearestRankPercentile(ms, 0.50),
      'p95': nearestRankPercentile(ms, 0.95),
      'max': ms.isEmpty ? 0 : ms.reduce((a, b) => a > b ? a : b),
      'scopes': ms.length,
    };
    final lease = nearestRankPercentile(leaseWaitMs, 0.95);
    final admit = nearestRankPercentile(admissionWaitMs, 0.95);
    final lane = nearestRankPercentile(laneBusyMs, 0.95);
    final String cause;
    if (lease == 0 && admit == 0 && lane == 0) {
      cause = 'none';
    } else if (lane >= lease + admit) {
      cause = 'serialised-lane';
    } else {
      cause = lease >= admit ? 'lease-wait' : 'admission-wait';
    }
    return {
      'leaseWaitMs': stat(leaseWaitMs),
      'admissionWaitMs': stat(admissionWaitMs),
      'laneBusyMs': stat(laneBusyMs),
      'dominantLatencyCause': cause,
    };
  }
}
