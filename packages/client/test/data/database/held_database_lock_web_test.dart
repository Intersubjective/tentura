// Run with: flutter test --platform chrome <this file>
//
// Real `navigator.locks`: another holder keeps the local database's cross-tab
// lock (as a frozen or background tab does) while this page opens the
// database. The open must give up with a lock error well before the 60 s boot
// timeout instead of waiting for the lock forever.
@TestOn('browser')
@Timeout(Duration(seconds: 150))
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:sqlite3/common.dart' show SqliteException;

import 'package:tentura/app/boot_dependencies.dart';
import 'package:tentura/app/di/modules.dart';
import 'package:tentura/data/database/database.dart' hide isNotNull, isNull;
import 'package:tentura/data/database/open_local_database_web.dart';
import 'package:tentura/data/database/reopening_query_executor.dart';
import 'package:tentura/data/service/local_secure_storage.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/data/repository/auth_local_repository.dart';

final class _Module extends RegisterModule {}

@JS('eval')
external JSAny? _eval(JSString code);

/// Counts this page's requests for any `tentura:local-db:*` lock and lets the
/// test hold such a lock from a separate request that the opener cannot see
/// through (it is granted before the open starts and never released).
void _installLockProbe() => _eval(
  '''
(() => {
  if (globalThis.__localDbLockProbe) return;
  const original = LockManager.prototype.request;
  const probe = globalThis.__localDbLockProbe = { requests: {}, original };
  LockManager.prototype.request = function (name, ...rest) {
    const key = String(name);
    if (key.startsWith('tentura:local-db:')) {
      probe.requests[key] = (probe.requests[key] || 0) + 1;
    }
    return original.call(this, name, ...rest);
  };
})()
'''
      .toJS,
);

JSObject get _probe =>
    globalContext.getProperty<JSObject>('__localDbLockProbe'.toJS);

int _lockRequests(String lockName) {
  final requests = _probe.getProperty<JSObject>('requests'.toJS);
  final count = requests.getProperty<JSNumber?>(lockName.toJS);
  return count?.toDartInt ?? 0;
}

/// Holds [lockName] from another request until the page goes away.
Future<void> _holdLockForever(String lockName) async {
  final granted = Completer<void>();
  _probe
      .getProperty<JSFunction>('original'.toJS)
      .callAsFunction(
        _navigatorLocks,
        lockName.toJS,
        ((JSAny? _) {
          granted.complete();
          return Completer<void>().future.toJS;
        }).toJS,
      );
  await granted.future;
}

JSObject get _navigatorLocks => globalContext
    .getProperty<JSObject>('navigator'.toJS)
    .getProperty<JSObject>('locks'.toJS);

/// The opener's own lock-held error, possibly wrapped by the reopening
/// executor as the cause of its final open failure.
final _isLockHeld = predicate<Object?>(
  (error) =>
      error is LocalDatabaseLockHeldException ||
      (error is LocalDatabaseOpenException &&
          error.cause is LocalDatabaseLockHeldException),
  'a LocalDatabaseLockHeldException (or an open failure caused by one)',
);

/// Short bounds for the tests; production uses the k* defaults.
const _lockWait = Duration(milliseconds: 300);
const _lockAttempts = 2;

/// Generous slack over the configured bound for a busy CI browser.
const _slack = Duration(seconds: 5);

/// Opens at once; every statement then fails with a storage error.
final class _OpenExecutor extends QueryExecutor {
  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async => true;

  @override
  Future<void> close() async {}

  /// The storage under SQLite failed (I/O error, result code 10, #853).
  Never _storageError() => throw SqliteException(
    extendedResultCode: 10,
    message: 'disk I/O error',
  );

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String s,
    List<Object?> a,
  ) async => _storageError();

  @override
  Future<int> runInsert(String s, List<Object?> a) async => _storageError();

  @override
  Future<int> runUpdate(String s, List<Object?> a) async => _storageError();

  @override
  Future<int> runDelete(String s, List<Object?> a) async => _storageError();

  @override
  Future<void> runCustom(String s, [List<Object?>? a]) async => _storageError();

  @override
  Future<void> runBatched(BatchedStatements s) async => _storageError();

  @override
  TransactionExecutor beginTransaction() => _storageError();

  @override
  QueryExecutor beginExclusive() => _storageError();
}

final class _User extends QueryExecutorUser {
  @override
  int get schemaVersion => 5;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(_installLockProbe);

  group('local database open while another tab holds the cross-tab lock', () {
    test('production lock bounds: one wait is well under the boot timeout '
        'and all attempts together finish before it', () {
      expect(kLocalDatabaseLockAttempts, greaterThanOrEqualTo(2));
      expect(
        kLocalDatabaseLockWait,
        lessThanOrEqualTo(kBootTimeout ~/ 4),
        reason: 'one lock wait must be well under kBootTimeout',
      );
      expect(
        kLocalDatabaseLockWait * kLocalDatabaseLockAttempts,
        lessThan(kBootTimeout),
      );
    });

    test(
      'the open waits for the configured bound, asks again, then fails '
      'with a lock-held error',
      () async {
        const name = 'held_lock_bounded_db';
        const lockName = 'tentura:local-db:$name';
        await _holdLockForever(lockName);
        final database = Database(
          const Env(),
          Logger('HeldLockTest'),
          localDatabaseOpener(
            name,
            restoreAccounts: (_) async {},
            lockWait: _lockWait,
            lockAttempts: _lockAttempts,
          )(),
        );
        final watch = Stopwatch()..start();

        Object? error;
        try {
          await database
              .customSelect('SELECT 1')
              .get()
              .timeout(
                _lockWait * _lockAttempts + _slack,
                onTimeout: () => fail(
                  'the open was still waiting on the held lock after '
                  '${watch.elapsed}',
                ),
              );
        } on TestFailure {
          rethrow;
        } on Object catch (e) {
          error = e;
        }
        watch.stop();

        expect(error, _isLockHeld);
        expect(
          watch.elapsed,
          greaterThanOrEqualTo(_lockWait),
          reason: 'the opener must wait for the lock before giving up',
        );
        expect(
          _lockRequests(lockName),
          greaterThanOrEqualTo(2),
          reason: 'the opener must ask for the lock again before giving up',
        );
      },
    );

    test(
      'a statement that reopens the database after a storage error fails '
      'with a lock-held error and is reported instead of waiting on the lock',
      () async {
        const name = 'held_lock_reopen_db';
        const lockName = 'tentura:local-db:$name';
        final failures = <DatabaseStatementFailure>[];
        var opens = 0;
        final executor = ReopeningQueryExecutor(
          () => opens++ == 0
              ? _OpenExecutor()
              : localDatabaseOpener(
                  name,
                  restoreAccounts: (_) async {},
                  lockWait: _lockWait,
                  lockAttempts: _lockAttempts,
                )(),
          retryDelays: const [],
          onStatementError: failures.add,
        );
        expect(await executor.ensureOpen(_User()), isTrue);
        await _holdLockForever(lockName);
        final watch = Stopwatch()..start();

        Object outcome;
        try {
          await executor
              .runSelect('SELECT 1', const [])
              .timeout(
                _lockWait * _lockAttempts + _slack,
                onTimeout: () => fail(
                  'the reopen was still waiting on the held lock after '
                  '${watch.elapsed}',
                ),
              );
          outcome = 'completed';
        } on TestFailure {
          rethrow;
        } on Object catch (error) {
          outcome = error;
        }

        expect(opens, 2, reason: 'the storage error must trigger one reopen');
        expect(outcome, _isLockHeld);
        expect(_lockRequests(lockName), greaterThanOrEqualTo(2));
        expect(failures, isNotEmpty);
        expect(failures.last.statement, 'SELECT 1');
        expect(
          failures.last.error,
          _isLockHeld,
          reason: 'onStatementError must report the failed reopen',
        );
      },
    );

    test(
      'the auth_accounts boot step on the production database fails with a '
      'lock-held error before the boot timeout',
      () async {
        // The production DI database with its production bounds, exactly as
        // boot opens it.
        const lockName = 'tentura:local-db:main_db';
        await _holdLockForever(lockName);
        final reported = <Object>[];
        final watch = Stopwatch()..start();

        final ok = await bootDependencies(
          configure: () => bootStep('auth_accounts', () async {
            final logger = Logger('HeldLockTest');
            final database = Database(
              const Env(),
              logger,
              _Module().database,
            );
            return AuthLocalRepository(
              logger,
              database,
              LocalSecureStorage(),
            ).getAccountsAll();
          }),
          report: (error, _) => reported.add(error),
        ).timeout(kBootTimeout + const Duration(seconds: 10));
        watch.stop();

        expect(ok, isFalse);
        final error = reported.single;
        expect(
          error,
          isNot(isA<BootTimeoutException>()),
          reason:
              'boot waited on the held lock until the generic 60 s boot '
              'timeout: $error',
        );
        expect(error, _isLockHeld);
        expect(watch.elapsed, lessThan(kBootTimeout));
        expect(_lockRequests(lockName), greaterThanOrEqualTo(2));
      },
    );
  });
}
