import 'dart:async';

import 'package:drift/drift.dart';
import 'package:postgres/postgres.dart';
import 'package:tentura_server/domain/request_context.dart';

import 'main_db_pool.dart';

/// A cancellation target exists only while this scope owns its backend. SQL,
/// control cancellation and rollback all drain before the lease is returned.
final class RequestDbScope extends QueryInterceptor implements Session {
  RequestDbScope._(this._connection, this._pool, this._request, this._pid) {
    _unregister = _request.onCancel(() {
      if (!_ownsBackend || !_statementActive) return;
      _cancelDrain = _pool
          .cancelBackend(_pid, () => _ownsBackend && _statementActive)
          .catchError((Object _) async {
            // An unavailable control path must not leave SQL running.
            await _connection.close();
          });
    });
  }

  static Future<RequestDbScope> open(
    Connection connection,
    MainDbPool pool,
    RequestContext request,
  ) async {
    request.check();
    final rows = await connection.execute(
      'SELECT pg_backend_pid()',
      timeout: request.remaining,
    );
    request.check();
    return RequestDbScope._(
      connection,
      pool,
      request,
      rows.single.single! as int,
    );
  }

  final Connection _connection;
  final MainDbPool _pool;
  final RequestContext _request;
  final int _pid;
  late final void Function() _unregister;
  Future<void> _cancelDrain = Future.value();
  bool _ownsBackend = true;
  bool _statementActive = false;
  bool _rollingBack = false;
  bool _firstInTransaction = false;

  @override
  bool get isOpen => _connection.isOpen;

  @override
  Future<void> get closed => _connection.closed;

  Duration _budget([Duration? localCap]) {
    _request.check();
    var budget = _request.remaining;
    for (final cap in [_pool.statementTimeout, localCap]) {
      if (cap != null && cap > Duration.zero && cap < budget) budget = cap;
    }
    return budget;
  }

  Future<T> _run<T>(
    Future<T> Function(Duration timeout) action, [
    Duration? localCap,
    bool budgetStatement = true,
  ]) async {
    if (_rollingBack) return action(const Duration(seconds: 2));
    final budget = _budget(localCap);
    _statementActive = true;
    try {
      // SET TRANSACTION ISOLATION LEVEL must be the first query after BEGIN.
      if (budgetStatement) {
        final lockMs = budget.inMilliseconds.clamp(1, 1000);
        await _connection.execute(
          Sql.named('''
            SELECT set_config('statement_timeout', @statement, false),
                   set_config('lock_timeout', @lock, false)
          '''),
          parameters: {
            'statement': '${budget.inMilliseconds.clamp(1, 2147483647)}',
            'lock': '$lockMs',
          },
          timeout: budget,
        );
      }
      final result = await action(_budget(localCap));
      _request.check();
      return result;
    } finally {
      _statementActive = false;
      await _cancelDrain;
    }
  }

  @override
  Future<Result> execute(
    Object query, {
    Object? parameters,
    bool ignoreRows = false,
    QueryMode? queryMode,
    Duration? timeout,
  }) => _run(
    (budget) => _connection.execute(
      query,
      parameters: parameters,
      ignoreRows: ignoreRows,
      queryMode: queryMode,
      timeout: budget,
    ),
    timeout,
    !_firstInTransaction,
  );

  @override
  Future<Statement> prepare(Object query) async {
    _request.check();
    final statement = await _connection.prepare(query);
    return _RequestStatement(this, statement);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (statement.trimLeft().toUpperCase().startsWith('ROLLBACK')) {
      await _cancelDrain;
      _rollingBack = true;
      try {
        await executor.runCustom(statement, args);
      } finally {
        _rollingBack = false;
      }
    } else {
      _request.check();
      _firstInTransaction = statement.trimLeft().toUpperCase().startsWith(
        'SET TRANSACTION',
      );
      try {
        await executor.runCustom(statement, args);
      } finally {
        _firstInTransaction = false;
      }
    }
  }

  Future<void> release() async {
    _unregister();
    // Disarm before any await, and wait for previously dispatched signals.
    _ownsBackend = false;
    await _cancelDrain;
    if (_connection.isOpen) {
      try {
        await _connection.execute(
          'SET statement_timeout = ${_pool.statementTimeout.inMilliseconds}',
          timeout: const Duration(seconds: 2),
        );
        await _connection.execute(
          'SET lock_timeout = 0',
          timeout: const Duration(seconds: 2),
        );
      } on Object {
        await _connection.close();
      }
    }
  }
}

final class _RequestStatement implements Statement {
  _RequestStatement(this._scope, this._statement);

  final RequestDbScope _scope;
  final Statement _statement;

  @override
  ResultStream bind(Object? parameters) {
    _scope._request.check();
    return _statement.bind(parameters);
  }

  @override
  Future<Result> run(Object? parameters, {Duration? timeout}) => _scope._run(
    (budget) => _statement.run(parameters, timeout: budget),
    timeout,
  );

  @override
  Future<void> dispose() => _statement.dispose();
}
