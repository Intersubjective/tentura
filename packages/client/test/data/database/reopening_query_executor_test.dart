import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/database/database.dart' hide isNull;
import 'package:tentura/data/database/reopening_query_executor.dart';
import 'package:tentura/env.dart';

/// Stands in for the web connection whose open fails while the previous
/// page still holds the database file (#674).
final class _FailingOpenExecutor extends QueryExecutor {
  _FailingOpenExecutor(this.error);

  final Exception error;

  bool closed = false;

  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async => throw error;

  @override
  Future<void> close() async => closed = true;

  Never _unopened() => throw StateError('never opened');

  @override
  Future<List<Map<String, Object?>>> runSelect(String s, List<Object?> a) =>
      _unopened();

  @override
  Future<int> runInsert(String s, List<Object?> a) => _unopened();

  @override
  Future<int> runUpdate(String s, List<Object?> a) => _unopened();

  @override
  Future<int> runDelete(String s, List<Object?> a) => _unopened();

  @override
  Future<void> runCustom(String s, [List<Object?>? a]) => _unopened();

  @override
  Future<void> runBatched(BatchedStatements s) => _unopened();

  @override
  TransactionExecutor beginTransaction() => _unopened();

  @override
  QueryExecutor beginExclusive() => _unopened();
}

/// Hands out failing connections for the first [failures] opens, then real
/// in-memory ones.
final class _Opener {
  _Opener({required this.failures});

  int failures;

  final failed = <_FailingOpenExecutor>[];

  int opened = 0;

  QueryExecutor call() {
    opened++;
    if (failures > 0) {
      failures--;
      final executor = _FailingOpenExecutor(
        Exception(
          'SqliteException(1): while opening the database, SQL logic error',
        ),
      );
      failed.add(executor);
      return executor;
    }
    return NativeDatabase.memory();
  }
}

Database _database(QueryExecutor executor) =>
    Database(const Env(), Logger('test'), executor);

Future<int> _countAccounts(Database db) async =>
    (await db.select(db.accounts).get()).length;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const delays = [Duration(milliseconds: 1), Duration(milliseconds: 2)];

  test('reopens on a fresh connection after a failed open', () async {
    final opener = _Opener(failures: 2);
    final waited = <Duration>[];
    final retries = <int>[];
    final db = _database(
      ReopeningQueryExecutor(
        opener.call,
        retryDelays: delays,
        delay: (d) async => waited.add(d),
        onRetry: (attempt, _, _) => retries.add(attempt),
      ),
    );
    addTearDown(db.close);

    expect(await _countAccounts(db), 0);
    expect(opener.opened, 3);
    expect(retries, [1, 2]);
    expect(waited, delays);
    expect(opener.failed.every((e) => e.closed), isTrue);

    // Once open, the same connection serves every later call.
    await db
        .into(db.settings)
        .insert(
          SettingsCompanion.insert(key: 'k', valueText: const Value('v')),
        );
    expect((await db.select(db.settings).get()).single.valueText, 'v');
    expect(opener.opened, 3);
  });

  test('concurrent first queries share one open', () async {
    final opener = _Opener(failures: 1);
    final db = _database(
      ReopeningQueryExecutor(
        opener.call,
        retryDelays: delays,
        delay: (_) async {},
      ),
    );
    addTearDown(db.close);

    final counts = await Future.wait([
      _countAccounts(db),
      _countAccounts(db),
      _countAccounts(db),
    ]);
    expect(counts, [0, 0, 0]);
    expect(opener.opened, 2);
  });

  test('gives up with LocalDatabaseOpenException, then a later call '
      'tries again', () async {
    final opener = _Opener(failures: delays.length + 1);
    final db = _database(
      ReopeningQueryExecutor(
        opener.call,
        retryDelays: delays,
        delay: (_) async {},
      ),
    );
    addTearDown(db.close);

    await expectLater(
      _countAccounts(db),
      throwsA(
        isA<LocalDatabaseOpenException>()
            .having((e) => e.attempts, 'attempts', delays.length + 1)
            .having((e) => e.cause, 'cause', isA<Exception>()),
      ),
    );
    expect(opener.failed, hasLength(delays.length + 1));
    expect(opener.failed.every((e) => e.closed), isTrue);

    // The failure is not cached: the next query opens a fresh connection.
    expect(await _countAccounts(db), 0);
    expect(opener.opened, delays.length + 2);
  });

  group('after open (#703)', () {
    test('a failing statement is reported with its SQL and state, '
        'then rethrown', () async {
      final failures = <DatabaseStatementFailure>[];
      final opener = _Opener(failures: 1);
      final db = _database(
        ReopeningQueryExecutor(
          opener.call,
          retryDelays: delays,
          delay: (_) async {},
          onStatementError: failures.add,
        ),
      );
      addTearDown(db.close);

      expect(await _countAccounts(db), 0);
      // The failed open is the retry listener's business, not a statement.
      expect(failures, isEmpty);

      await expectLater(
        db.customSelect('SELECT * FROM no_such_table').get(),
        throwsA(isA<SqliteException>()),
      );
      expect(failures, hasLength(1));
      expect(failures.single.statement, 'SELECT * FROM no_such_table');
      expect(failures.single.state, LocalDatabaseState.open);
      expect(failures.single.connection, 2);
      expect(failures.single.failedOpens, 1);
      expect(failures.single.error, isA<SqliteException>());
      expect(failures.single.toString(), contains('no_such_table'));
    });

    test('a failure never carries the error text (bound arguments), only '
        'its type and SQLite result code', () async {
      final failures = <DatabaseStatementFailure>[];
      final db = _database(
        ReopeningQueryExecutor(
          _Opener(failures: 0).call,
          onStatementError: failures.add,
        ),
      );
      addTearDown(db.close);

      const secret = 'secret-user-value-703';
      Future<void> insert() => db
          .into(db.settings)
          .insert(
            SettingsCompanion.insert(key: secret, valueText: const Value('v')),
          );
      await insert();
      // The same primary key again: a constraint failure on a bound value.
      await expectLater(insert(), throwsA(isA<SqliteException>()));

      final failure = failures.single;
      expect(failure.error.toString(), contains(secret));
      expect(failure.statement, contains('settings'));
      expect(failure.toString(), isNot(contains(secret)));
      final code = (failure.error as SqliteException).extendedResultCode;
      expect(failure.errorSummary, 'SqliteException($code)');
      expect(failure.toString(), contains(failure.errorSummary));

      // What reaches the log (and the Sentry breadcrumb built from it).
      final logger = Logger('LocalDatabase703');
      final records = <LogRecord>[];
      final sub = logger.onRecord.listen(records.add);
      addTearDown(sub.cancel);
      logDatabaseStatementFailure(logger, failure);
      expect(records.single.level, Level.WARNING);
      expect(records.single.message, isNot(contains(secret)));
      expect(records.single.message, contains(failure.errorSummary));
      expect(records.single.error, isNull);
      expect(records.single.stackTrace, failure.stackTrace);
    });

    test('a non-SQLite error is described by its type only', () {
      final failure = DatabaseStatementFailure(
        statement: 'SELECT 1',
        state: LocalDatabaseState.open,
        connection: 1,
        failedOpens: 0,
        error: StateError('secret-user-value-703'),
        stackTrace: StackTrace.empty,
      );
      expect(failure.errorSummary, 'StateError');
      expect(failure.toString(), isNot(contains('secret-user-value-703')));
    });

    test('after close reads are dropped and reported, but writes and '
        'transactions throw LocalDatabaseClosedException', () async {
      final failures = <DatabaseStatementFailure>[];
      final db = _database(
        ReopeningQueryExecutor(
          _Opener(failures: 0).call,
          retryDelays: delays,
          delay: (_) async {},
          onStatementError: failures.add,
        ),
      );
      expect(await _countAccounts(db), 0);
      await db.close();

      // Late work (a realtime handler, a disposed account) after close.
      expect(await _countAccounts(db), 0);
      await expectLater(
        db
            .into(db.settings)
            .insert(
              SettingsCompanion.insert(key: 'k', valueText: const Value('v')),
            ),
        throwsA(isA<LocalDatabaseClosedException>()),
      );
      await expectLater(
        db
            .update(db.settings)
            .write(const SettingsCompanion(valueInt: Value(1))),
        throwsA(isA<LocalDatabaseClosedException>()),
      );
      await expectLater(
        db.transaction(() async {
          await db.delete(db.contacts).go();
        }),
        throwsA(isA<LocalDatabaseClosedException>()),
      );
      // A transaction that only reads still never commits after close.
      await expectLater(
        db.transaction(() => _countAccounts(db)),
        throwsA(isA<LocalDatabaseClosedException>()),
      );

      expect(
        failures.map((f) => f.state),
        everyElement(LocalDatabaseState.closed),
      );
      expect(
        failures.map((f) => f.error),
        everyElement(isA<LocalDatabaseClosedException>()),
      );
      expect(failures.first.statement, contains('accounts'));
      expect(failures[1].statement, contains('settings'));
      expect(failures[2].statement, contains('settings'));
      expect(failures[3].statement, contains('contacts'));
    });

    test('a statement that succeeds is not reported', () async {
      final failures = <DatabaseStatementFailure>[];
      final db = _database(
        ReopeningQueryExecutor(
          _Opener(failures: 0).call,
          onStatementError: failures.add,
        ),
      );
      addTearDown(db.close);

      expect(await _countAccounts(db), 0);
      expect(failures, isEmpty);
    });
  });
}
