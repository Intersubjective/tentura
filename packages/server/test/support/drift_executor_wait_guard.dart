import 'dart:async';
import 'dart:io' show stdout;

import 'package:drift/drift.dart'
    show
        BatchedStatements,
        QueryExecutor,
        QueryExecutorUser,
        QueryInterceptor,
        TransactionExecutor;
import 'package:postgres/postgres.dart' show Connection, Sql;

import 'disposable_pg_target.dart';

/// How long a disposable-database statement or transaction boundary may wait
/// before [DbWaitGuard] fails it. Under the runner's own 30 s test timeout, and
/// over every legitimate statement the suites run.
const defaultDbWaitDeadline = Duration(seconds: 12);

/// How long a backend must have been stuck before the harness monitor dumps it.
const stuckBackendDumpAfter = Duration(seconds: 8);

const _stuckBackendPollEvery = Duration(seconds: 3);

/// Rollback and commit after the connection was aborted are bounded harder:
/// there is nothing left to wait for.
const _afterAbortDeadline = Duration(seconds: 1);

/// Called once, before the wait failure surfaces, to record diagnostics on the
/// [DbWaitTimeoutException] and abort the connection that is waiting.
typedef DbWaitExpiry = Future<void> Function(DbWaitTimeoutException timeout);

/// An executor operation did not complete within the guard's deadline.
final class DbWaitTimeoutException implements Exception {
  DbWaitTimeoutException({
    required this.operation,
    required this.deadline,
    required this.scopeStack,
    this.sql,
  });

  final String operation;
  final Duration deadline;
  final String? sql;

  /// Open transactions and savepoints of the guard, outermost first.
  final List<String> scopeStack;

  /// `pg_stat_activity` rows of the test database, set by the guard's expiry
  /// callback before the exception surfaces.
  List<Map<String, Object?>> activity = const [];

  String get report => formatDbHangReport(
    headline:
        '$operation waited longer than ${deadline.inMilliseconds} ms'
        '${sql == null ? '' : ' for: $sql'}',
    scopeStacks: [scopeStack],
    activity: activity,
  );

  @override
  String toString() => 'DbWaitTimeoutException: $report';
}

final class _OpenScope {
  _OpenScope(this.executor, {required this.savepoint});

  final QueryExecutor executor;
  final bool savepoint;
  final Stopwatch age = Stopwatch()..start();

  @override
  String toString() =>
      '${savepoint ? 'savepoint' : 'transaction'} open '
      '${(age.elapsedMilliseconds / 1000).toStringAsFixed(1)} s';
}

/// Test-only [QueryInterceptor] that bounds every executor operation a
/// statement or transaction boundary can wait in. A Drift executor lock held by
/// the caller itself never times out on its own; this turns that wait into a
/// [DbWaitTimeoutException] with the open scope stack, and aborts the owning
/// connection through [onExpired].
final class DbWaitGuard extends QueryInterceptor {
  DbWaitGuard({required this.deadline, this.onExpired});

  /// A guard that, on expiry, snapshots `pg_stat_activity` of [target] through
  /// a separate admin connection and terminates the backend that is waiting.
  factory DbWaitGuard.forTarget(
    DisposablePgTarget target, {
    Duration deadline = defaultDbWaitDeadline,
  }) {
    final guard = DbWaitGuard(
      deadline: deadline,
      onExpired: (timeout) => _recordAndAbort(target, timeout),
    );
    (_liveByDatabase[target.databaseName] ??= {}).add(guard);
    guard._database = target.databaseName;
    return guard;
  }

  /// Guards created for each database that still have an open executor.
  static final _liveByDatabase = <String, Set<DbWaitGuard>>{};

  final Duration deadline;
  final DbWaitExpiry? onExpired;
  final List<_OpenScope> _scopes = [];
  String? _database;
  bool _expired = false;

  /// Open transactions and savepoints, outermost first.
  List<String> get activeScopeStack => [
    for (final (index, scope) in _scopes.indexed) '#${index + 1} $scope',
  ];

  Future<T> _bounded<T>(
    String operation,
    String? sql,
    Future<T> Function() run, {
    Duration? limit,
  }) {
    final result = Completer<T>();
    var expired = false;
    final timer = Timer(limit ?? deadline, () async {
      if (result.isCompleted) return;
      expired = true;
      final timeout = DbWaitTimeoutException(
        operation: operation,
        deadline: limit ?? deadline,
        scopeStack: activeScopeStack,
        sql: sql,
      );
      if (!_expired) {
        _expired = true;
        try {
          await onExpired?.call(timeout);
        } on Object {
          // The wait failure is the one worth reporting, not a failed abort.
        }
      }
      if (!result.isCompleted) result.completeError(timeout);
    });
    unawaited(
      Future.sync(run).then<void>(
        (value) {
          timer.cancel();
          if (!result.isCompleted) result.complete(value);
        },
        onError: (Object error, StackTrace stackTrace) {
          timer.cancel();
          // Aborting the connection fails the statement itself; the wait
          // failure, not that fallout, is what the caller must see.
          if (expired) return;
          if (!result.isCompleted) result.completeError(error, stackTrace);
        },
      ),
    );
    return result.future;
  }

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    final inner = super.beginTransaction(parent);
    _scopes.add(
      _OpenScope(
        inner,
        savepoint: _scopes.any((scope) => identical(scope.executor, parent)),
      ),
    );
    return inner;
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    try {
      await _bounded(
        'commit',
        null,
        () => super.commitTransaction(inner),
        limit: _expired ? _afterAbortDeadline : null,
      );
    } finally {
      _scopes.removeWhere((scope) => identical(scope.executor, inner));
    }
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    final aborted = _expired;
    try {
      await _bounded(
        'rollback',
        null,
        () => super.rollbackTransaction(inner),
        limit: aborted ? _afterAbortDeadline : null,
      );
    } on Object {
      // Once the connection was aborted there is nothing to roll back, and a
      // rollback failure would hide the wait failure that caused it.
      if (!aborted) rethrow;
    } finally {
      _scopes.removeWhere((scope) => identical(scope.executor, inner));
    }
  }

  @override
  Future<void> close(QueryExecutor inner) {
    final database = _database;
    if (database != null) _liveByDatabase[database]?.remove(this);
    return super.close(inner);
  }

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      _bounded('ensureOpen', null, () => super.ensureOpen(executor, user));

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) => _bounded(
    'runBatched',
    statements.statements.join(';\n'),
    () => super.runBatched(executor, statements),
  );

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _bounded(
    'runCustom',
    statement,
    () => super.runCustom(executor, statement, args),
  );

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _bounded(
    'runInsert',
    statement,
    () => super.runInsert(executor, statement, args),
  );

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _bounded(
    'runDelete',
    statement,
    () => super.runDelete(executor, statement, args),
  );

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _bounded(
    'runUpdate',
    statement,
    () => super.runUpdate(executor, statement, args),
  );

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _bounded(
    'runSelect',
    statement,
    () => super.runSelect(executor, statement, args),
  );
}

const _activitySql = '''
SELECT pid, datname, state, wait_event_type, wait_event,
       extract(epoch FROM now() - xact_start)::float8 AS xact_age_s,
       extract(epoch FROM now() - state_change)::float8 AS state_age_s,
       array_to_string(pg_blocking_pids(pid), ',') AS blocked_by,
       query
FROM pg_stat_activity
WHERE datname = @name
  AND pid <> pg_backend_pid()
  AND backend_type = 'client backend'
ORDER BY pid
''';

Future<Connection> _openAdmin(DisposablePgTarget target) => Connection.open(
  target.adminEnv.pgEndpoint,
  settings: target.adminEnv.pgEndpointSettings,
);

Future<List<Map<String, Object?>>> _activityRows(
  Connection admin,
  String databaseName,
) async {
  final rows = await admin.execute(
    Sql.named(_activitySql),
    parameters: {'name': databaseName},
  );
  return [for (final row in rows) row.toColumnMap()];
}

/// The backends of the test database, from a separate admin connection: state,
/// wait event, transaction age, blocking pids and the last query of each.
Future<List<Map<String, Object?>>> readDbActivity(
  DisposablePgTarget target,
) async {
  final admin = await _openAdmin(target);
  try {
    return await _activityRows(admin, target.databaseName);
  } finally {
    await admin.close();
  }
}

bool _isStuck(Map<String, Object?> row) =>
    '${row['state']}'.startsWith('idle in transaction') ||
    row['wait_event_type'] == 'Lock';

Future<void> _recordAndAbort(
  DisposablePgTarget target,
  DbWaitTimeoutException timeout,
) async {
  final admin = await _openAdmin(target);
  try {
    final rows = await _activityRows(admin, target.databaseName);
    timeout.activity = rows;
    // The guard cannot tell which backend its executor sits on without
    // spending a statement per connection: the waiting one is either parked
    // in a transaction or blocked on a lock, never plainly idle.
    for (final row in rows.where(_isStuck)) {
      await admin.execute('SELECT pg_terminate_backend(${row['pid']})');
    }
  } finally {
    await admin.close();
  }
}

/// A human-readable dump: the scope stacks and the `pg_stat_activity` rows.
String formatDbHangReport({
  required String headline,
  required List<List<String>> scopeStacks,
  required List<Map<String, Object?>> activity,
}) {
  final out = StringBuffer(headline)
    ..writeln()
    ..writeln('Scope stack (outermost first):');
  final stacked = scopeStacks.where((stack) => stack.isNotEmpty).toList();
  if (stacked.isEmpty) out.writeln('  (empty)');
  for (final stack in stacked) {
    for (final scope in stack) {
      out.writeln('  $scope');
    }
  }
  if (activity.isEmpty) {
    out.write('pg_stat_activity: (no backends read)');
    return out.toString();
  }
  out.writeln('pg_stat_activity of ${activity.first['datname']}:');
  for (final row in activity) {
    out.writeln(
      '  pid=${row['pid']} state=${row['state']} '
      'wait_event=${row['wait_event_type']}/${row['wait_event']} '
      'xact_age_s=${row['xact_age_s']} state_age_s=${row['state_age_s']} '
      'blocked_by=[${row['blocked_by']}] query=${row['query']}',
    );
  }
  return out.toString().trimRight();
}

Future<String> _dumpOf(
  DisposablePgTarget target,
  String headline,
  Iterable<DbWaitGuard> guards,
) async {
  List<Map<String, Object?>> activity;
  try {
    activity = await readDbActivity(target);
  } on Object {
    activity = const [];
  }
  return formatDbHangReport(
    headline: headline,
    scopeStacks: [for (final guard in guards) guard.activeScopeStack],
    activity: activity,
  );
}

/// Dumps the guards' scope stacks and the test database's `pg_stat_activity`
/// once, if [watch]'s action is still running after [dumpAfter].
final class DbHangWatchdog {
  DbHangWatchdog({
    required this.target,
    required this.dumpAfter,
    this.guards = const [],
    void Function(String line)? write,
  }) : write = write ?? stdout.writeln;

  final DisposablePgTarget target;
  final Duration dumpAfter;
  final List<DbWaitGuard> guards;
  final void Function(String line) write;

  Future<T> watch<T>(Future<T> Function() action) async {
    final timer = Timer(
      dumpAfter,
      () => unawaited(
        _dumpOf(
          target,
          'Still running after ${dumpAfter.inMilliseconds} ms',
          guards,
        ).then(write),
      ),
    );
    try {
      return await action();
    } finally {
      timer.cancel();
    }
  }
}

/// Watches a disposable database for backends stuck on a lock or parked in a
/// transaction, for the whole suite, whatever connection they belong to. This
/// is what reports a hang outside any guarded Drift executor, before the
/// runner's own timeout fires.
final class DbStuckBackendMonitor {
  DbStuckBackendMonitor(this.target, {void Function(String line)? write})
    : _write = write ?? stdout.writeln;

  final DisposablePgTarget target;
  final void Function(String line) _write;
  final _reported = <String>{};
  Timer? _timer;
  var _polling = false;

  void start() {
    _timer ??= Timer.periodic(_stuckBackendPollEvery, (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final rows = await readDbActivity(target);
      final stuck = [
        for (final row in rows)
          if (_isStuck(row) &&
              ((row['state_age_s'] as double?) ?? 0) >=
                  stuckBackendDumpAfter.inMilliseconds / 1000 &&
              _reported.add('${row['pid']}|${row['query']}'))
            row,
      ];
      if (stuck.isEmpty || _timer == null) return;
      _write(
        formatDbHangReport(
          headline:
              'Backend stuck for over ${stuckBackendDumpAfter.inSeconds} s',
          scopeStacks: [
            for (final guard
                in DbWaitGuard._liveByDatabase[target.databaseName] ??
                    const <DbWaitGuard>{})
              guard.activeScopeStack,
          ],
          activity: rows,
        ),
      );
    } on Object {
      // Diagnostics only: the database may be mid-drop.
    } finally {
      _polling = false;
    }
  }
}
