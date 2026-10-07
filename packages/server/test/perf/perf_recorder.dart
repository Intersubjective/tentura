import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:postgres/postgres.dart' as pg;

import 'package:tentura_server/data/database/postgres_serialization_retry.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    show TenturaDb;

import 'perf_instruments.dart' hide captureExplain;
import 'perf_instruments.dart' as instruments show captureExplain;
import 'perf_report.dart';

final _attemptKey = Object();

/// What one attempt has observed so far; read through the attempt's [Zone].
final class _AttemptState {
  int queryCount = 0;
  int serializationFailures = 0;
  Duration sessionTime = Duration.zero;
  Duration queueTime = Duration.zero;
  Duration txAge = Duration.zero;
  Duration execution = Duration.zero;
  Duration cursorWait = Duration.zero;
  Duration cursorHold = Duration.zero;
  bool usedExecutionScope = false;
}

_AttemptState? get _currentAttempt =>
    Zone.current[_attemptKey] as _AttemptState?;

/// Meters the statements an attempt sends through a Drift database.
///
/// Wire it on both layers of the database under test:
///
/// ```dart
/// final meter = PerfDbMeter();
/// PgDatabase.opened(meter.instrument(pool)).interceptWith(meter);
/// ```
///
/// The interceptor sees each call from the application's side, so its elapsed
/// time includes waiting for Drift's executor lock; the instrumented session
/// sees only the time spent on the wire. The difference is the connection
/// queue time. Everything is attributed to the attempt in whose zone the
/// call was made, so work outside [PerfRecorder.attempt] is not counted.
final class PerfDbMeter extends QueryInterceptor {
  final _transactions = Expando<(_AttemptState, Stopwatch)>('perf.tx');

  pg.Session? _session;

  /// Wraps [session] so the time spent executing on it is measured.
  pg.Session instrument(pg.Session session) =>
      _session = _InstrumentedSession(session);

  /// The instrumented session, for probes that must not queue behind Drift's
  /// executor lock.
  pg.Session get session =>
      _session ?? (throw StateError('PerfDbMeter.instrument was not called'));

  /// `mr_rpc_attempts()` of the backend behind the instrumented session: a
  /// per-backend counter, so only that backend's own reads see its RPCs. The
  /// database is meant to run on a single pooled connection.
  Future<int> connectorRpcAttempts() async {
    final session = _session;
    if (session == null) return 0;
    try {
      final rows = await session.execute('SELECT mr_rpc_attempts()');
      return (rows.first.first! as num).toInt();
    } on pg.ServerException catch (e) {
      // undefined_function: pgmer2 is not installed in this database.
      if (e.code == '42883') return 0;
      rethrow;
    }
  }

  Future<T> _statement<T>(Future<T> Function() run) async {
    final state = _currentAttempt;
    if (state == null) return run();
    state.queryCount++;
    return _metered(state, run);
  }

  Future<T> _metered<T>(_AttemptState state, Future<T> Function() run) async {
    final onWireBefore = state.sessionTime;
    final clock = Stopwatch()..start();
    try {
      return await run();
    } on Object catch (error) {
      if (isPostgresDeadlockOrSerializationFailure(error)) {
        state.serializationFailures++;
      }
      rethrow;
    } finally {
      final waited = clock.elapsed - (state.sessionTime - onWireBefore);
      if (waited > Duration.zero) state.queueTime += waited;
    }
  }

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    final inner = super.beginTransaction(parent);
    final state = _currentAttempt;
    if (state != null) _transactions[inner] = (state, Stopwatch()..start());
    return inner;
  }

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) {
    final state = _currentAttempt;
    if (state == null) return super.ensureOpen(executor, user);
    return _metered(state, () => super.ensureOpen(executor, user));
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) =>
      _endTransaction(inner, () => super.commitTransaction(inner));

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) =>
      _endTransaction(inner, () => super.rollbackTransaction(inner));

  Future<void> _endTransaction(
    TransactionExecutor inner,
    Future<void> Function() end,
  ) async {
    final tracked = _transactions[inner];
    final state = tracked?.$1 ?? _currentAttempt;
    try {
      if (state == null) return await end();
      await _metered(state, end);
    } finally {
      if (tracked != null) {
        final (owner, clock) = tracked;
        owner.txAge = Duration(
          microseconds: max(owner.txAge.inMicroseconds, clock.elapsedMicroseconds),
        );
        _transactions[inner] = null;
      }
    }
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) => _statement(() => super.runBatched(executor, statements));

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _statement(() => super.runCustom(executor, statement, args));

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _statement(() => super.runInsert(executor, statement, args));

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _statement(() => super.runDelete(executor, statement, args));

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _statement(() => super.runUpdate(executor, statement, args));

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _statement(() => super.runSelect(executor, statement, args));
}

/// Forwards to [_inner], adding the time spent in `execute` to the attempt
/// that issued it.
final class _InstrumentedSession implements pg.Session {
  _InstrumentedSession(this._inner);

  final pg.Session _inner;

  @override
  bool get isOpen => _inner.isOpen;

  @override
  Future<void> get closed => _inner.closed;

  @override
  Future<pg.Statement> prepare(Object query) => _inner.prepare(query);

  @override
  Future<pg.Result> execute(
    Object query, {
    Object? parameters,
    bool ignoreRows = false,
    pg.QueryMode? queryMode,
    Duration? timeout,
  }) async {
    final state = _currentAttempt;
    final clock = Stopwatch()..start();
    try {
      return await _inner.execute(
        query,
        parameters: parameters,
        ignoreRows: ignoreRows,
        queryMode: queryMode,
        timeout: timeout,
      );
    } finally {
      if (state != null) state.sessionTime += clock.elapsed;
    }
  }
}

/// Handed to the body of [PerfRecorder.attempt] to mark the phases the
/// recorder cannot see on its own.
final class PerfAttemptScope {
  PerfAttemptScope._(this._db, this._state);

  final TenturaDb _db;
  final _AttemptState _state;

  /// Times [body] as the work under test, so [PerfAttempt.execution] can be
  /// reported apart from admission and response encoding.
  Future<R> execution<R>(Future<R> Function() body) async {
    _state.usedExecutionScope = true;
    final clock = Stopwatch()..start();
    try {
      return await body();
    } finally {
      _state.execution += clock.elapsed;
    }
  }

  /// Takes a lock with [lockSql] (time to acquire is the cursor wait), then
  /// runs [hold] with it taken (its duration is the cursor hold). Call it
  /// inside the transaction that owns the lock.
  Future<R> cursorLock<R>({
    required String lockSql,
    required Future<R> Function() hold,
  }) async {
    final waitClock = Stopwatch()..start();
    try {
      await _db.customSelect(lockSql).get();
    } finally {
      _state.cursorWait += waitClock.elapsed;
    }
    final holdClock = Stopwatch()..start();
    try {
      return await hold();
    } finally {
      _state.cursorHold += holdClock.elapsed;
    }
  }
}

/// Runs attempts against [db] and records one [PerfAttempt] for each into
/// [report]. [probeConnection] is a separate session on the same database,
/// used only for the WAL, lock and EXPLAIN probes.
final class PerfRecorder {
  PerfRecorder({
    required String fixture,
    required this.db,
    required this.meter,
    required this.probeConnection,
    Map<String, Object?> parameters = const {},
  }) : report = PerfReport(
         fixture: fixture,
         parameters: parameters,
         walAttribution: WalAttribution.quietCluster,
       );

  static const _lockPollInterval = Duration(milliseconds: 50);

  final TenturaDb db;
  final PerfDbMeter meter;
  final pg.Connection probeConnection;
  final PerfReport report;

  /// Runs [action] as one measured attempt. Latency runs from the call of
  /// [action] to its completion, so response encoding done inside it counts;
  /// a failed attempt is recorded too and its error rethrown.
  Future<T> attempt<T>(Future<T> Function(PerfAttemptScope scope) action) async {
    final state = _AttemptState();
    // On the database's own session: the probe connection may be busy in a
    // transaction of its own while an attempt starts or ends.
    final wal = WalMeter(meter.session);
    final lockProbe = PerfLockProbe(probeConnection);
    var lockWaiters = 0;
    var polling = true;

    await wal.start();
    final rpcBefore = await meter.connectorRpcAttempts();
    final poller = () async {
      try {
        while (polling) {
          lockWaiters = max(lockWaiters, await lockProbe.waitingLockCount());
          await Future<void>.delayed(_lockPollInterval);
        }
      } on pg.PgException {
        // Best effort: a probe connection busy in a transaction of its own
        // cannot be polled, and that must not fail the attempt.
      }
    }();

    var failed = false;
    Object? failure;
    final latency = Stopwatch()..start();
    try {
      return await runZoned(
        () => action(PerfAttemptScope._(db, state)),
        zoneValues: {_attemptKey: state},
      );
    } on Object catch (error) {
      failed = true;
      failure = error;
      rethrow;
    } finally {
      latency.stop();
      polling = false;
      await poller;
      final rpcAfter = await meter.connectorRpcAttempts();
      final walMeasurement = await wal.stop();
      if (walMeasurement.attribution == WalAttribution.clusterTotal) {
        report.walAttribution = WalAttribution.clusterTotal;
      }
      // The failure that ends an attempt was not retried.
      final retries = max(
        0,
        state.serializationFailures -
            (failure != null && isPostgresDeadlockOrSerializationFailure(failure)
                ? 1
                : 0),
      );
      report.add(
        PerfAttempt(
          latency: latency.elapsed,
          execution: state.usedExecutionScope
              ? state.execution
              : latency.elapsed,
          failed: failed,
          queryCount: state.queryCount,
          // A backend swapped out mid-attempt restarts its counter.
          connectorRpcs: rpcAfter >= rpcBefore ? rpcAfter - rpcBefore : rpcAfter,
          cursorWait: state.cursorWait,
          cursorHold: state.cursorHold,
          connectionQueueTime: state.queueTime,
          txAge: state.txAge,
          retryCount: retries,
          walBytes: walMeasurement.bytes,
          lockWaiters: lockWaiters,
        ),
      );
    }
  }

  Future<void> captureExplain({
    required String label,
    required String sql,
    bool mutating = false,
  }) async => report.addExplain(
    await instruments.captureExplain(
      probeConnection,
      label: label,
      sql: sql,
      mutating: mutating,
    ),
  );

  Future<File> writeReport([Directory? directory]) =>
      report.writeTo(directory ?? PerfReport.defaultOutputDirectory);
}
