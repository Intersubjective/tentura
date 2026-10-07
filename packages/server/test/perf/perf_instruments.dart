import 'dart:convert';

import 'package:postgres/postgres.dart';

import 'perf_report.dart';

/// WAL generated between [WalMeter.start] and [WalMeter.stop], and whether the
/// figure can be attributed to the measured work alone.
final class WalMeasurement {
  const WalMeasurement({required this.bytes, required this.attribution});

  final int bytes;
  final WalAttribution attribution;
}

/// `pg_current_wal_lsn()` delta over a window, read on [_probe].
///
/// WAL is cluster-wide, so the figure is [WalAttribution.quietCluster] only
/// when no other client session was active at either end of the window;
/// otherwise it is labelled [WalAttribution.clusterTotal].
final class WalMeter {
  WalMeter(this._probe);

  final Session _probe;

  String? _startLsn;
  var _busyAtStart = false;

  Future<void> start() async {
    _busyAtStart = await _otherSessionsActive();
    _startLsn =
        (await _probe.execute('SELECT pg_current_wal_lsn()::text')).first.first!
            as String;
  }

  Future<WalMeasurement> stop() async {
    final startLsn = _startLsn;
    if (startLsn == null) throw StateError('WalMeter.stop before start');
    final bytes =
        (await _probe.execute(
              Sql.named(
                'SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), '
                '@start::pg_lsn)::bigint',
              ),
              parameters: {'start': startLsn},
            )).first.first!
            as int;
    final busy = _busyAtStart || await _otherSessionsActive();
    _startLsn = null;
    return WalMeasurement(
      bytes: bytes,
      attribution: busy
          ? WalAttribution.clusterTotal
          : WalAttribution.quietCluster,
    );
  }

  Future<bool> _otherSessionsActive() async {
    final rows = await _probe.execute(
      "SELECT 1 FROM pg_stat_activity WHERE backend_type = 'client backend' "
      "AND state = 'active' AND pid <> pg_backend_pid() LIMIT 1",
    );
    return rows.isNotEmpty;
  }
}

/// Lock waiters in the database [_probe] is connected to.
///
/// Counted from `pg_stat_activity`, scoped to `current_database()`: lock
/// waits in other databases (a schema upgrade elsewhere, another suite's
/// fixture) are not this fixture's contention. Unlike `pg_locks` it also sees
/// row-lock waits, which queue on a `transactionid` lock with no database.
final class PerfLockProbe {
  PerfLockProbe(this._probe);

  final Connection _probe;

  Future<int> waitingLockCount() async {
    final rows = await _probe.execute(
      'SELECT count(*)::int FROM pg_stat_activity '
      "WHERE datname = current_database() AND wait_event_type = 'Lock' "
      'AND pid <> pg_backend_pid()',
    );
    return rows.first.first! as int;
  }
}

/// Runs `EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON)` for [sql] on
/// [connection] and keeps the JSON plan.
///
/// ANALYZE executes the statement, so a [mutating] one runs inside a
/// transaction that is always rolled back.
Future<PerfExplainCapture> captureExplain(
  Connection connection, {
  required String label,
  required String sql,
  bool mutating = false,
}) async {
  final explain = 'EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON) $sql';
  Object? plan;
  if (mutating) {
    await connection.execute('BEGIN');
    try {
      plan = (await connection.execute(explain)).first.first;
    } finally {
      await connection.execute('ROLLBACK');
    }
  } else {
    plan = (await connection.execute(explain)).first.first;
  }
  return PerfExplainCapture(
    label: label,
    plan: plan is String ? jsonDecode(plan) : plan,
    rolledBack: mutating,
  );
}
