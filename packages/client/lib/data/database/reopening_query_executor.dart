import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:logging/logging.dart';
import 'package:sqlite3/common.dart' show SqliteException;

/// Creates a fresh, not yet opened connection to the local database.
typedef QueryExecutorFactory = QueryExecutor Function();

/// Told about a failed open just before the executor tries again.
///
/// [attempt] counts the failed attempts so far (1 for the first failure).
typedef DatabaseReopenListener =
    void Function(int attempt, Object error, StackTrace stackTrace);

/// Where the local database stood when a statement ran (#703).
enum LocalDatabaseState {
  /// Not open yet, or between a failed open and the next attempt.
  opening,

  /// Open; statements go to the current connection.
  open,

  /// Closed for good; reads are dropped, writes and transactions throw
  /// [LocalDatabaseClosedException].
  closed,
}

/// A statement that failed, or was refused because the database was closed.
///
/// Its [toString] carries the SQL text, the error's type and SQLite result
/// code only — never the error's own text: a `SqliteException` prints the
/// statement's bound parameters (user data) in its `toString()` (#703).
final class DatabaseStatementFailure {
  const DatabaseStatementFailure({
    required this.statement,
    required this.state,
    required this.connection,
    required this.failedOpens,
    required this.error,
    required this.stackTrace,
  });

  final String statement;

  final LocalDatabaseState state;

  /// Which connection ran it: 1 for the first, counting every reopen.
  final int connection;

  /// How many opens failed before this connection.
  final int failedOpens;

  final Object error;

  final StackTrace stackTrace;

  /// The error's type and, for SQLite errors, the extended result code —
  /// e.g. `SqliteException(1555)`. On the web the error arrives wrapped in a
  /// [DriftRemoteException]; its cause is described instead.
  String get errorSummary {
    final cause = switch (error) {
      final DriftRemoteException e => e.remoteCause,
      final other => other,
    };
    // Only the code is taken from the text; the rest of it is never kept.
    final code = _sqliteResultCode.firstMatch(cause.toString())?.group(1);
    return code == null ? '${cause.runtimeType}' : 'SqliteException($code)';
  }

  static final _sqliteResultCode = RegExp(r'^SqliteException\((\d+)\)');

  @override
  String toString() =>
      'statement "$statement" (database ${state.name}, connection '
      '$connection, failed opens $failedOpens): $errorSummary';
}

/// Logs [failure] as a warning on [logger]: the SQL, the state and the
/// error's type and result code (#703). The error object itself is not passed
/// on, so neither the log nor the Sentry breadcrumb built from it can carry
/// the error's text (with the statement's arguments).
void logDatabaseStatementFailure(
  Logger logger,
  DatabaseStatementFailure failure,
) => logger.warning('Local database $failure', null, failure.stackTrace);

/// Told about a [DatabaseStatementFailure]; the failure is still thrown
/// (after close a read is dropped instead).
typedef DatabaseStatementListener =
    void Function(DatabaseStatementFailure failure);

/// A write or a transaction reached the local database after it was closed
/// (#703) — e.g. work that outlived a logout. Thrown so the caller does not
/// take the write for done.
final class LocalDatabaseClosedException implements Exception {
  const LocalDatabaseClosedException(this.statement);

  /// The SQL that was refused.
  final String statement;

  @override
  String toString() =>
      'LocalDatabaseClosedException: the local database is closed; '
      'refused "$statement"';
}

/// The local database could not be opened, even after reopening it.
final class LocalDatabaseOpenException implements Exception {
  const LocalDatabaseOpenException({
    required this.attempts,
    required this.cause,
    required this.causeStackTrace,
  });

  /// How many times opening was tried.
  final int attempts;

  /// The error of the last attempt.
  final Object cause;

  final StackTrace causeStackTrace;

  @override
  String toString() =>
      'LocalDatabaseOpenException: could not open the local database '
      'after $attempts attempts: $cause';
}

/// A [QueryExecutor] that opens the local database again, on a brand-new
/// connection, when opening fails (#674).
///
/// On the web the database lives in OPFS behind drift's workers. Right after a
/// reload or a same-tab navigation the previous page's workers may still hold
/// the database file while they shut down, and the new page's open fails at
/// once with `SqliteException(1): while opening the database`. A reload a
/// moment later works, so this executor does what that reload does: it drops
/// the failed connection, waits a little and opens a new one. After the last
/// retry delay it gives up with [LocalDatabaseOpenException] — the
/// app then shows an error with a Reload action instead of hanging on the
/// splash screen.
///
/// Once open, every call goes straight to the current connection; a failing
/// statement is reported to `onStatementError` with its SQL and the
/// executor's state, then rethrown (#703). A storage error (see
/// [isStorageError]) leaves the connection failing every later statement
/// (#853): the executor drops that connection, opens a new one and runs the
/// statement once more. A statement outside a transaction that failed
/// changed nothing, so running it again is safe. After
/// [close] nothing reaches the closed connection: a late read (from work that
/// outlived the database) is reported and dropped, while a late write or
/// transaction is reported and throws [LocalDatabaseClosedException].
final class ReopeningQueryExecutor extends QueryExecutor {
  ReopeningQueryExecutor(
    this._open, {
    List<Duration> retryDelays = defaultRetryDelays,
    this._onRetry,
    this._onStatementError,
    Future<void> Function(Duration delay)? delay,
    this._closeTimeout = const Duration(seconds: 2),
  }) : _inner = _open(),
       _retryDelays = List.unmodifiable(retryDelays),
       _delay = delay ?? Future<void>.delayed;

  /// About 8 s in all: longer than the old page's workers need to let go of
  /// the database file, short enough that a stuck open reaches the error
  /// screen quickly.
  static const defaultRetryDelays = [
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  final QueryExecutorFactory _open;

  final List<Duration> _retryDelays;

  final DatabaseReopenListener? _onRetry;

  final DatabaseStatementListener? _onStatementError;

  final Future<void> Function(Duration delay) _delay;

  final Duration _closeTimeout;

  QueryExecutor _inner;

  Future<void>? _opening;

  var _isOpen = false;

  var _isClosed = false;

  var _connection = 1;

  var _failedOpens = 0;

  QueryExecutorUser? _user;

  /// Whether [error] came from the storage under SQLite rather than from the
  /// statement (#853): an I/O error (result code 10), or result code 1 with
  /// only SQLite's generic "SQL logic error" text. A bad statement (no such
  /// column, a syntax error) carries its own text and is not retried.
  static bool isStorageError(Object error) => switch (error) {
    DriftRemoteException(:final remoteCause) => isStorageError(remoteCause),
    SqliteException(resultCode: 10) => true,
    SqliteException(resultCode: 1, :final message) =>
      message == 'SQL logic error',
    _ => false,
  };

  LocalDatabaseState get _state => _isClosed
      ? LocalDatabaseState.closed
      : _isOpen
      ? LocalDatabaseState.open
      : LocalDatabaseState.opening;

  @override
  SqlDialect get dialect => _inner.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async {
    if (_isClosed) {
      // The statement that follows is dropped and reported.
      return false;
    }
    _user = user;
    if (!_isOpen) {
      final opening = _opening ??= _openWithRetry(user);
      try {
        await opening;
      } catch (_) {
        // Let a later call start a new round instead of failing forever.
        if (identical(_opening, opening)) {
          _opening = null;
        }
        rethrow;
      }
    }
    return _inner.ensureOpen(user);
  }

  Future<void> _openWithRetry(QueryExecutorUser user) async {
    for (var attempt = 1; ; attempt++) {
      try {
        await _inner.ensureOpen(user);
        _isOpen = true;
        return;
      } catch (error, stackTrace) {
        _failedOpens++;
        if (_isClosed) {
          rethrow;
        }
        if (attempt > _retryDelays.length) {
          // A later call starts over on a fresh connection.
          await _closeQuietly(_inner);
          if (!_isClosed) {
            _inner = _open();
            _connection++;
          }
          throw LocalDatabaseOpenException(
            attempts: attempt,
            cause: error,
            causeStackTrace: stackTrace,
          );
        }
        _onRetry?.call(attempt, error, stackTrace);
        await _closeQuietly(_inner);
        await _delay(_retryDelays[attempt - 1]);
        if (_isClosed) {
          rethrow;
        }
        _inner = _open();
        _connection++;
      }
    }
  }

  Future<void> _closeQuietly(QueryExecutor executor) async {
    try {
      await executor.close().timeout(_closeTimeout);
    } on Object {
      // The connection is already broken; nothing more to release.
    }
  }

  /// Runs [run] on the current connection, reporting a failure with its
  /// [statement] and the state. After [close] a read is reported and
  /// [dropped] is returned instead.
  Future<T> _guardRead<T>(
    String statement,
    T dropped,
    Future<T> Function(QueryExecutor executor) run,
  ) async {
    if (_isClosed) {
      _report(
        statement,
        LocalDatabaseClosedException(statement),
        StackTrace.current,
      );
      return dropped;
    }
    return _run(statement, run);
  }

  /// Like [_guardRead], but after [close] a write is reported and throws
  /// [LocalDatabaseClosedException]: the caller must not take it for done.
  Future<T> _guardWrite<T>(
    String statement,
    Future<T> Function(QueryExecutor executor) run,
  ) async {
    if (_isClosed) _refuseClosed(statement);
    return _run(statement, run);
  }

  Future<T> _run<T>(
    String statement,
    Future<T> Function(QueryExecutor executor) run,
  ) async {
    final user = _user;
    if (!_isOpen && user != null) {
      // Another statement is reopening after a storage error.
      await ensureOpen(user);
    }
    final executor = _inner;
    try {
      return await run(executor);
    } catch (error, stackTrace) {
      _report(statement, error, stackTrace);
      if (!isStorageError(error) || !await _reopenAfter(executor)) rethrow;
    }
    try {
      return await run(_inner);
    } catch (error, stackTrace) {
      _report(statement, error, stackTrace);
      rethrow;
    }
  }

  /// Replaces [failed] with a new, opened connection after a storage error —
  /// unless a concurrent statement already did. False when there is nothing
  /// to run the statement on again: never opened, or closed meanwhile.
  Future<bool> _reopenAfter(QueryExecutor failed) async {
    final user = _user;
    if (_isClosed || user == null) return false;
    if (identical(_inner, failed)) {
      _isOpen = false;
      _inner = _open();
      _connection++;
      await _closeQuietly(failed);
    }
    return ensureOpen(user);
  }

  Never _refuseClosed(String statement) {
    final error = LocalDatabaseClosedException(statement);
    final stackTrace = StackTrace.current;
    _report(statement, error, stackTrace);
    Error.throwWithStackTrace(error, stackTrace);
  }

  void _report(String statement, Object error, StackTrace stackTrace) =>
      _onStatementError?.call(
        DatabaseStatementFailure(
          statement: statement,
          state: _state,
          connection: _connection,
          failedOpens: _failedOpens,
          error: error,
          stackTrace: stackTrace,
        ),
      );

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _guardRead(statement, const [], (e) => e.runSelect(statement, args));

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _guardWrite(statement, (e) => e.runInsert(statement, args));

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _guardWrite(statement, (e) => e.runUpdate(statement, args));

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _guardWrite(statement, (e) => e.runDelete(statement, args));

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _guardWrite(statement, (e) => e.runCustom(statement, args));

  @override
  Future<void> runBatched(BatchedStatements statements) => _guardWrite(
    statements.statements.join('; '),
    (e) => e.runBatched(statements),
  );

  @override
  TransactionExecutor beginTransaction() => _isClosed
      ? _ClosedTransactionExecutor(this)
      : _RecoveringTransactionExecutor(this);

  @override
  QueryExecutor beginExclusive() =>
      _isClosed ? _ClosedTransactionExecutor(this) : _inner.beginExclusive();

  @override
  Future<void> close() {
    _isClosed = true;
    return _inner.close();
  }
}

/// A transaction on the current connection that starts over on a new one when
/// its first statement hits a storage error (#853). Nothing in it has run at
/// that point, so the new transaction does exactly what the failed one would
/// have. drift's table managers run even a single read in a transaction.
/// A later statement's failure fails the transaction, as before.
final class _RecoveringTransactionExecutor extends TransactionExecutor {
  _RecoveringTransactionExecutor(this._owner)
    : _connection = _owner._inner,
      _transaction = _owner._inner.beginTransaction();

  final ReopeningQueryExecutor _owner;

  /// The connection [_transaction] runs on.
  QueryExecutor _connection;

  TransactionExecutor _transaction;

  QueryExecutorUser? _user;

  var _ran = false;

  @override
  SqlDialect get dialect => _transaction.dialect;

  @override
  bool get supportsNestedTransactions =>
      _transaction.supportsNestedTransactions;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) {
    _user = user;
    return _transaction.ensureOpen(user);
  }

  Future<T> _run<T>(
    String statement,
    Future<T> Function(QueryExecutor executor) run,
  ) async {
    final first = !_ran;
    _ran = true;
    try {
      return await run(_transaction);
    } catch (error, stackTrace) {
      _owner._report(statement, error, stackTrace);
      if (!first || !await _restart(error)) rethrow;
    }
    try {
      return await run(_transaction);
    } catch (error, stackTrace) {
      _owner._report(statement, error, stackTrace);
      rethrow;
    }
  }

  /// Begins this transaction again on a reopened connection; false when
  /// [error] is not a storage error or there is no connection to reopen.
  Future<bool> _restart(Object error) async {
    final user = _user;
    if (user == null || !ReopeningQueryExecutor.isStorageError(error)) {
      return false;
    }
    try {
      // Lets go of the failed connection's lock so that it can be closed.
      await _transaction.rollback();
    } on Object {
      // The connection is replaced next; it has nothing left to undo.
    }
    if (!await _owner._reopenAfter(_connection)) return false;
    _connection = _owner._inner;
    _transaction = _connection.beginTransaction();
    return _transaction.ensureOpen(user);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _run(statement, (e) => e.runSelect(statement, args));

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _run(statement, (e) => e.runInsert(statement, args));

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _run(statement, (e) => e.runUpdate(statement, args));

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _run(statement, (e) => e.runDelete(statement, args));

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _run(statement, (e) => e.runCustom(statement, args));

  @override
  Future<void> runBatched(BatchedStatements statements) => _run(
    statements.statements.join('; '),
    (e) => e.runBatched(statements),
  );

  @override
  TransactionExecutor beginTransaction() {
    _ran = true;
    return _transaction.beginTransaction();
  }

  @override
  QueryExecutor beginExclusive() {
    _ran = true;
    return _transaction.beginExclusive();
  }

  @override
  Future<void> send() => _transaction.send();

  @override
  Future<void> rollback() => _transaction.rollback();
}

/// Stands in for a transaction or exclusive block begun after the database
/// was closed (#703): a read in it is dropped, a write throws
/// [LocalDatabaseClosedException], and so does committing it — a transaction
/// never looks done after close.
final class _ClosedTransactionExecutor extends TransactionExecutor {
  _ClosedTransactionExecutor(this._owner);

  final ReopeningQueryExecutor _owner;

  @override
  SqlDialect get dialect => _owner.dialect;

  @override
  bool get supportsNestedTransactions => true;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async => false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _owner.runSelect(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _owner.runInsert(statement, args);

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _owner.runUpdate(statement, args);

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _owner.runDelete(statement, args);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _owner.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _owner.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() => _ClosedTransactionExecutor(_owner);

  @override
  QueryExecutor beginExclusive() => _ClosedTransactionExecutor(_owner);

  @override
  Future<void> send() async => _owner._refuseClosed('COMMIT');

  @override
  Future<void> rollback() async {}

  @override
  Future<void> close() async {}
}
