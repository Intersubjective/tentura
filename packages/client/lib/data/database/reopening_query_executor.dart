import 'dart:async';

import 'package:drift/drift.dart';

/// Creates a fresh, not yet opened connection to the local database.
typedef QueryExecutorFactory = QueryExecutor Function();

/// Told about a failed open just before the executor tries again.
///
/// [attempt] counts the failed attempts so far (1 for the first failure).
typedef DatabaseReopenListener =
    void Function(int attempt, Object error, StackTrace stackTrace);

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
/// Only opening is retried. Once open, every call goes straight to the
/// current connection.
final class ReopeningQueryExecutor extends QueryExecutor {
  ReopeningQueryExecutor(
    this._open, {
    List<Duration> retryDelays = defaultRetryDelays,
    this._onRetry,
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

  final Future<void> Function(Duration delay) _delay;

  final Duration _closeTimeout;

  QueryExecutor _inner;

  Future<void>? _opening;

  var _isOpen = false;

  var _isClosed = false;

  @override
  SqlDialect get dialect => _inner.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async {
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
        if (_isClosed) {
          rethrow;
        }
        if (attempt > _retryDelays.length) {
          // A later call starts over on a fresh connection.
          await _closeQuietly(_inner);
          if (!_isClosed) {
            _inner = _open();
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

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _inner.runSelect(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _inner.runInsert(statement, args);

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _inner.runUpdate(statement, args);

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _inner.runDelete(statement, args);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _inner.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _inner.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() => _inner.beginTransaction();

  @override
  QueryExecutor beginExclusive() => _inner.beginExclusive();

  @override
  Future<void> close() {
    _isClosed = true;
    return _inner.close();
  }
}
