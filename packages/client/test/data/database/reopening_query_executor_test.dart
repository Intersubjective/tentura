import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/database/database.dart';
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
    await db.into(db.settings).insert(
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
}
