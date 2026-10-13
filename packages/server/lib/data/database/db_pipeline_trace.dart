import 'dart:async';

import 'package:drift/backends.dart' show DelegatedDatabase;
import 'package:drift/drift.dart';
import 'package:postgres/postgres.dart' show ServerException, Session;
import 'package:sentry/sentry.dart';

import 'package:tentura_server/app/sentry/sentry_db_span.dart';

const _queryCanceled = '57014';

/// Captures Drift's transaction callback without overriding transaction or
/// changing connection ownership. Ordinary statements create no lifetime span.
final class DbSpanConnectionUser extends DatabaseConnectionUser {
  DbSpanConnectionUser(this.attachedDatabase)
    : super.delegate(attachedDatabase);

  @override
  final GeneratedDatabase attachedDatabase;

  @override
  Future<T> doWhenOpened<T>(FutureOr<T> Function(QueryExecutor) fn) {
    if (DbTransactionTrace.current != null) return super.doWhenOpened(fn);
    final scope = _DbTransactionTraceScope(attachedDatabase);
    Future<T> run() async {
      Object? failure;
      try {
        return await super.doWhenOpened(fn);
      } on Object catch (error) {
        failure = error;
        rethrow;
      } finally {
        await scope.trace?._finish(failure);
      }
    }

    return runZoned(run, zoneValues: {DbTransactionTrace._zoneKey: scope});
  }
}

final class _DbTransactionTraceScope {
  _DbTransactionTraceScope(this.database);

  final GeneratedDatabase database;
  DbTransactionTrace? trace;
}

/// The Sentry spans of one outermost database transaction: its lifetime
/// (`db.transaction`, BEGIN to COMMIT/ROLLBACK), the wait for its pool
/// connection (`db.pool.acquire`) and, after a statement the server cancelled,
/// the time until the connection is rolled back and released
/// (`db.cancel.drain`). Statements run inside it nest under its span.
final class DbTransactionTrace {
  DbTransactionTrace._(this._db, this._span, this._acquire);

  static final Object _zoneKey = Object();

  /// The trace of the transaction the caller is running in, if any.
  static DbTransactionTrace? get current => switch (Zone.current[_zoneKey]) {
    final DbTransactionTrace trace => trace,
    final _DbTransactionTraceScope scope => scope.trace,
    _ => null,
  };

  /// Starts the trace of a transaction on [db], or returns null when no
  /// Sentry transaction is active or the caller already runs inside a
  /// transaction of [db] (a nested one is a savepoint, not a new lifetime).
  /// [leasesConnection] adds the pool acquire span.
  static DbTransactionTrace? begin(
    Object db, {
    required bool leasesConnection,
  }) {
    final enclosing = current;
    if (enclosing != null && !enclosing._done && identical(enclosing._db, db)) {
      return null;
    }
    final span = startSentryDbSpan('db.transaction');
    if (span == null) return null;
    return DbTransactionTrace._(
      db,
      span,
      leasesConnection ? span.startChild('db.pool.acquire') : null,
    );
  }

  final Object _db;
  final ISentrySpan _span;
  ISentrySpan? _acquire;
  ISentrySpan? _drain;
  bool _done = false;

  /// Runs [body] with this trace as the current one and finishes the spans
  /// when it completes or fails.
  Future<T> run<T>(Future<T> Function() body) async {
    Object? failure;
    try {
      return await _inZone(body);
    } on Object catch (error) {
      failure = error;
      rethrow;
    } finally {
      await _finish(failure);
    }
  }

  Future<T> _inZone<T>(Future<T> Function() body) => runZoned(
    body,
    zoneValues: {_zoneKey: this, kSentryParentSpanZoneKey: _span},
  );

  Future<void> _finish(Object? failure) async {
    _done = true;
    await finishSentryDbSpan(_drain);
    await finishSentryDbSpan(_acquire, failure);
    await finishSentryDbSpan(_span, failure);
  }

  /// The backend PID serving [connection], or null if it cannot be read.
  /// Only for a connection the caller has to itself: a statement sent to one
  /// that another transaction has begun lands inside that transaction.
  static Future<String?> backendPid(Session connection) async {
    try {
      final rows = await connection.execute('SELECT pg_backend_pid()');
      return '${rows.first.first}';
    } on Object catch (_) {
      // Diagnostics only: a broken connection fails the next statement anyway.
      return null;
    }
  }

  /// The connection was acquired: ends the acquire span and tags the
  /// transaction span with the backend PID, given or read from [connection].
  Future<void> acquired({Session? connection, String? backendPid}) async {
    final acquire = _acquire;
    _acquire = null;
    await finishSentryDbSpan(acquire);
    final pid =
        backendPid ??
        (connection == null
            ? null
            : await DbTransactionTrace.backendPid(connection));
    if (pid != null) _span.setTag('db.backend_pid', pid);
  }

  /// A statement of this transaction was cancelled by the server.
  void statementCancelled() {
    _drain ??= _span.startChild('db.cancel.drain');
  }
}

/// Traces a delegated database without hiding its direct delegate access.
/// Ordinary pool queries can still bypass Drift's transaction/statement lock.
final class DbSpanDatabase extends DelegatedDatabase {
  DbSpanDatabase(DelegatedDatabase database)
    : _dialect = database.dialect,
      super(
        database.delegate,
        isSequential: database.isSequential,
        logStatements: database.logStatements,
      );

  final SqlDialect _dialect;
  final _spans = DbSpanInterceptor();

  @override
  SqlDialect get dialect => _dialect;

  @override
  TransactionExecutor beginTransaction() =>
      super.beginTransaction().interceptWith(_spans) as TransactionExecutor;

  @override
  QueryExecutor beginExclusive() =>
      super.beginExclusive().interceptWith(_spans);

  @override
  Future<void> runBatched(BatchedStatements statements) => _spans._traced(
    statements.statements.join(';\n'),
    () => super.runBatched(statements),
  );

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _spans._traced(statement, () => super.runCustom(statement, args));

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _spans._traced(statement, () => super.runInsert(statement, args));

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _spans._traced(statement, () => super.runDelete(statement, args));

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _spans._traced(statement, () => super.runUpdate(statement, args));

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _spans._traced(statement, () => super.runSelect(statement, args));
}

/// Records every statement as a `db.sql` span with its SQL text (never the
/// bound arguments), nested under the current transaction span if any.
final class DbSpanInterceptor extends QueryInterceptor {
  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    final scope = Zone.current[DbTransactionTrace._zoneKey];
    if (scope is _DbTransactionTraceScope) {
      scope.trace ??= DbTransactionTrace.begin(
        scope.database,
        leasesConnection: false,
      );
    }
    return super.beginTransaction(parent);
  }

  Future<T> _traced<T>(String sql, Future<T> Function() run) {
    final trace = DbTransactionTrace.current;
    return trace == null
        ? _runTraced(sql, run)
        : trace._inZone(() => _runTraced(sql, run));
  }

  Future<T> _runTraced<T>(String sql, Future<T> Function() run) async {
    final span = startSentryDbSpan('db.sql', description: sql);
    if (span == null) return run();
    try {
      final result = await run();
      await finishSentryDbSpan(span);
      return result;
    } on Object catch (error) {
      await finishSentryDbSpan(span, error);
      if (error is ServerException && error.code == _queryCanceled) {
        DbTransactionTrace.current?.statementCancelled();
      }
      rethrow;
    }
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) => _traced(
    statements.statements.join(';\n'),
    () => super.runBatched(executor, statements),
  );

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _traced(statement, () => super.runCustom(executor, statement, args));

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _traced(statement, () => super.runInsert(executor, statement, args));

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _traced(statement, () => super.runDelete(executor, statement, args));

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _traced(statement, () => super.runUpdate(executor, statement, args));

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _traced(statement, () => super.runSelect(executor, statement, args));
}
