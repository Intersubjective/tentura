import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:test/test.dart';

import '../../support/drift_executor_wait_guard.dart';

const _deadline = Duration(milliseconds: 200);

/// Everything the guard has to bound: each executor entry point a statement or
/// a transaction boundary can wait in.
const _operations = <String>[
  'ensureOpen',
  'runSelect',
  'runCustom',
  'runInsert',
  'runUpdate',
  'runDelete',
  'runBatched',
  'commit',
  'rollback',
];

final class _User implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

/// An executor whose chosen operations never complete, standing in for a
/// Drift executor lock that is held by the caller itself.
class _HangingExecutor implements TransactionExecutor {
  _HangingExecutor({this.hangOn = const {}});

  final Set<String> hangOn;
  final List<String> calls = [];

  Future<T> _run<T>(String operation, T result) {
    calls.add(operation);
    if (hangOn.contains(operation)) return Completer<T>().future;
    return Future<T>.value(result);
  }

  @override
  SqlDialect get dialect => SqlDialect.postgres;

  @override
  bool get supportsNestedTransactions => true;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _run('ensureOpen', true);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _run('runSelect', [
    {'answer': 1},
  ]);

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _run('runInsert', 1);

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _run('runUpdate', 1);

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _run('runDelete', 1);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _run('runCustom', null);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _run('runBatched', null);

  @override
  TransactionExecutor beginTransaction() => _HangingExecutor(hangOn: hangOn);

  @override
  QueryExecutor beginExclusive() => this;

  @override
  Future<void> send() => _run('commit', null);

  @override
  Future<void> rollback() => _run('rollback', null);

  @override
  Future<void> close() async {}
}

final class _FailingExecutor extends _HangingExecutor {
  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => Future.error(const FormatException('boom'));
}

Future<void> _invoke(QueryExecutor executor, String operation) async {
  switch (operation) {
    case 'ensureOpen':
      await executor.ensureOpen(_User());
    case 'runSelect':
      await executor.runSelect('SELECT hung_marker', const []);
    case 'runCustom':
      await executor.runCustom('SELECT hung_marker', const []);
    case 'runInsert':
      await executor.runInsert('INSERT hung_marker', const []);
    case 'runUpdate':
      await executor.runUpdate('UPDATE hung_marker', const []);
    case 'runDelete':
      await executor.runDelete('DELETE hung_marker', const []);
    case 'runBatched':
      await executor.runBatched(BatchedStatements(['SELECT hung_marker'], []));
    case 'commit':
      await (executor as TransactionExecutor).send();
    case 'rollback':
      await (executor as TransactionExecutor).rollback();
    default:
      throw ArgumentError.value(operation);
  }
}

QueryExecutor _guarded(
  _HangingExecutor inner,
  DbWaitGuard guard, {
  required String operation,
}) {
  final executor = inner.interceptWith(guard);
  if (operation == 'commit' || operation == 'rollback') {
    return executor.beginTransaction();
  }
  return executor;
}

Future<Object?> _failureOf(Future<void> Function() action) =>
    action().then<Object?>((_) => null, onError: (Object error) => error);

void main() {
  group('executor wait deadline', () {
    test(
      'operations that finish in time are passed through untouched',
      () async {
        final inner = _HangingExecutor();
        final executor = inner.interceptWith(DbWaitGuard(deadline: _deadline));

        expect(await executor.ensureOpen(_User()), isTrue);
        expect(await executor.runSelect('SELECT 1', const []), [
          {'answer': 1},
        ]);
        expect(await executor.runInsert('INSERT', const []), 1);
        expect(inner.calls, ['ensureOpen', 'runSelect', 'runInsert']);
      },
    );

    for (final operation in _operations) {
      test(
        '$operation that never completes fails past the deadline instead of '
        'waiting forever',
        () async {
          final inner = _HangingExecutor(hangOn: {operation});
          final executor = _guarded(
            inner,
            DbWaitGuard(deadline: _deadline),
            operation: operation,
          );
          final clock = Stopwatch()..start();

          final failure = await _failureOf(
            () => _invoke(executor, operation),
          ).timeout(const Duration(seconds: 5));

          expect(failure, isA<DbWaitTimeoutException>());
          final timeout = failure! as DbWaitTimeoutException;
          expect(timeout.operation, operation);
          expect(timeout.deadline, _deadline);
          expect(clock.elapsed, greaterThanOrEqualTo(_deadline));
          expect(clock.elapsed, lessThan(const Duration(seconds: 3)));
        },
      );
    }

    test('the failure names the statement that was waiting', () async {
      final executor = _HangingExecutor(
        hangOn: {'runSelect'},
      ).interceptWith(DbWaitGuard(deadline: _deadline));

      final failure = await _failureOf(
        () => executor.runSelect('SELECT hung_marker FROM somewhere', const []),
      );

      expect(failure, isA<DbWaitTimeoutException>());
      final timeout = failure! as DbWaitTimeoutException;
      expect(timeout.sql, contains('hung_marker'));
      expect(timeout.report, contains('hung_marker'));
      expect(timeout.toString(), contains('runSelect'));
    });

    test(
      'the owning connection is aborted once, before the failure surfaces',
      () async {
        final events = <String>[];
        final executor = _HangingExecutor(hangOn: {'runSelect'}).interceptWith(
          DbWaitGuard(
            deadline: _deadline,
            onExpired: (timeout) async {
              events.add('aborted:${timeout.operation}');
            },
          ),
        );

        await executor
            .runSelect('SELECT hung_marker', const [])
            .then<void>((_) {}, onError: (Object _) => events.add('failed'));

        expect(events, ['aborted:runSelect', 'failed']);
      },
    );

    test('a failing abort does not mask the wait failure', () async {
      final executor = _HangingExecutor(hangOn: {'runSelect'}).interceptWith(
        DbWaitGuard(
          deadline: _deadline,
          onExpired: (_) async => throw StateError('connection already gone'),
        ),
      );

      await expectLater(
        executor.runSelect('SELECT hung_marker', const []),
        throwsA(isA<DbWaitTimeoutException>()),
      );
    });

    test('a statement error is not rewritten into a wait failure', () async {
      final executor = _FailingExecutor().interceptWith(
        DbWaitGuard(deadline: _deadline),
      );

      await expectLater(
        executor.runSelect('SELECT 1', const []),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('active scope stack', () {
    test('lists open transactions and savepoints, outermost first', () async {
      final guard = DbWaitGuard(deadline: _deadline);
      final root = _HangingExecutor().interceptWith(guard);
      expect(guard.activeScopeStack, isEmpty);

      final transaction = root.beginTransaction();
      await transaction.runSelect('SELECT 1', const []);
      expect(guard.activeScopeStack, hasLength(1));

      final savepoint = transaction.beginTransaction();
      await savepoint.runSelect('SELECT 1', const []);
      expect(guard.activeScopeStack, hasLength(2));

      await savepoint.send();
      expect(guard.activeScopeStack, hasLength(1));

      await transaction.send();
      expect(guard.activeScopeStack, isEmpty);
    });

    test('a rolled back transaction leaves the stack', () async {
      final guard = DbWaitGuard(deadline: _deadline);
      final transaction = _HangingExecutor()
          .interceptWith(guard)
          .beginTransaction();
      await transaction.runSelect('SELECT 1', const []);
      expect(guard.activeScopeStack, hasLength(1));

      await transaction.rollback();

      expect(guard.activeScopeStack, isEmpty);
    });

    test(
      'the failure carries the stack that was open when it expired',
      () async {
        final guard = DbWaitGuard(deadline: _deadline);
        final transaction = _HangingExecutor(
          hangOn: {'runSelect'},
        ).interceptWith(guard).beginTransaction();
        final savepoint = transaction.beginTransaction();

        final failure = await _failureOf(
          () => savepoint.runSelect('SELECT hung_marker', const []),
        );

        expect(failure, isA<DbWaitTimeoutException>());
        final timeout = failure! as DbWaitTimeoutException;
        expect(timeout.scopeStack, hasLength(2));
        expect(timeout.report.toLowerCase(), contains('scope stack'));
      },
    );
  });
}
