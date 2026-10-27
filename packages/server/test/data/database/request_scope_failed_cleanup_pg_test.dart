@Tags(['pg'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/request_db_scope.dart';
import 'package:tentura_server/domain/request_context.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

typedef _Backend = ({int pid, int statementMs, int lockMs});

// Read before issuing scope SQL: scope.execute would overwrite the very
// session settings whose cleanliness the next borrower needs to observe.
Future<_Backend> _backend(Connection connection) async {
  final row = (await connection.execute('''
    SELECT pg_backend_pid(),
      (SELECT setting::int FROM pg_settings WHERE name = 'statement_timeout'),
      (SELECT setting::int FROM pg_settings WHERE name = 'lock_timeout')
  ''')).single;
  return (
    pid: row[0]! as int,
    statementMs: row[1]! as int,
    lockMs: row[2]! as int,
  );
}

void _expectFreshDefaults(_Backend before, _Backend after) {
  expect(
    (
      freshBackend: after.pid != before.pid,
      statementMs: after.statementMs,
      lockMs: after.lockMs,
    ),
    (freshBackend: true, statementMs: 30000, lockMs: 0),
    reason:
        'A failed cleanup must discard the lease so the next request '
        'gets a different backend with default timeouts. '
        'Previous backend: $before; next backend: $after',
  );
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_CLEANUP_TEST_DB',
    defaultNamePrefix: 'tentura_test_request_cleanup',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Postgres unavailable', () {}, skip: unavailable);
    return;
  }

  setUpAll(target.recreate);
  tearDownAll(target.drop);

  group('Request scope pool recovery', () {
    for (final reset in ['statement_timeout', 'lock_timeout']) {
      test('failed $reset reset gives the next request a fresh backend '
          'with default timeouts', () async {
        final pool = MainDbPool(_PoolEnv(target.databaseEnv));
        addTearDown(pool.close);
        final request = RequestContext(requestId: 'failed-reset');
        addTearDown(request.dispose);
        late _Backend dirty;
        late _FaultConnection fault;

        await pool.pool.withConnection((lease) async {
          fault = _FaultConnection(lease, failedReset: reset);
          final scope = await RequestDbScope.open(fault, pool, request);
          try {
            expect((await scope.execute('SELECT 42')).single.single, 42);
            dirty = await _backend(lease);
            expect(dirty.statementMs, inInclusiveRange(1, 5000));
            expect(dirty.lockMs, inInclusiveRange(1, 1000));
          } finally {
            await scope.release();
          }
        });

        expect(
          fault.resetFailures,
          1,
          reason: 'The reset must actually fail with SQLSTATE 57014.',
        );
        expect(fault.backendAfterResetFailure?.pid, dirty.pid);
        expect(fault.backendAfterResetFailure?.lockMs, dirty.lockMs);
        expect(
          fault.backendAfterResetFailure?.statementMs,
          reset == 'statement_timeout' ? dirty.statementMs : 30000,
        );
        expect(
          fault.cleanupCloseAttempts,
          1,
          reason: 'release must catch the reset failure and attempt disposal.',
        );
        expect(
          fault.wasOpenAtCleanupClose,
          isTrue,
          reason:
              'The injected error must leave a live lease for the '
              'cleanup handler to discard.',
        );
        _expectFreshDefaults(dirty, await _nextRequestBackend(pool));
      });
    }

    test('failed cancellation control discards the backend even when '
        'timeout reset would succeed', () async {
      final env = _PoolEnv(target.databaseEnv, failControl: true);
      final pool = MainDbPool(env);
      addTearDown(pool.close);
      final request = RequestContext(requestId: 'failed-cancellation');
      addTearDown(request.dispose);
      final cancelled = StateError('Caller disconnected');
      late _Backend dirty;

      await pool.pool.withConnection((lease) async {
        final fault = _FaultConnection(lease);
        final scope = await RequestDbScope.open(fault, pool, request);
        var openBeforeRelease = false;
        try {
          // Prove both reset commands work on this lease before inducing the
          // independent control-channel failure.
          await fault.execute('SET statement_timeout = 30000');
          await fault.execute('SET lock_timeout = 0');
          final defaults = await _backend(lease);
          expect(defaults.statementMs, 30000);
          expect(defaults.lockMs, 0);
          expect(fault.successfulResets, [
            'SET statement_timeout = 30000',
            'SET lock_timeout = 0',
          ]);
          fault.successfulResets.clear();
          expect((await scope.execute('SELECT 42')).single.single, 42);
          dirty = await _backend(lease);
          expect(dirty.statementMs, inInclusiveRange(1, 5000));
          expect(dirty.lockMs, inInclusiveRange(1, 1000));
          final result = expectLater(
            scope.execute('SELECT pg_sleep(0.5)'),
            throwsA(anyOf(same(cancelled), isA<PgException>())),
          );
          await fault.sleepDispatched.future;
          request.cancel(cancelled);
          await result;
          expect(
            env.controlError,
            isA<ServerException>().having(
              (error) => error.code,
              'SQLSTATE',
              '22012',
            ),
            reason:
                'The control connection must fail with the injected SQL '
                'error, rather than merely being opened.',
          );
          expect(
            fault.closeAttempts,
            1,
            reason:
                'Before release runs, the cancellation-control failure '
                'handler must attempt to discard the application lease.',
          );
          expect(
            fault.wasOpenAtClose,
            isTrue,
            reason:
                'The control error must leave the application lease '
                'open until its cancellation handler attempts disposal.',
          );
          openBeforeRelease = lease.isOpen;
        } finally {
          await scope.release();
        }
        expect(fault.resetFailures, 0);
        expect(
          fault.successfulResets,
          openBeforeRelease
              ? ['SET statement_timeout = 30000', 'SET lock_timeout = 0']
              : isEmpty,
          reason:
              'If cancellation leaves the lease open, release must '
              'successfully reset both timeouts. A discarded lease needs no reset.',
        );
      });

      expect(
        env.controlFailures,
        1,
        reason: 'Cancellation must exercise the failed control connection.',
      );
      _expectFreshDefaults(dirty, await _nextRequestBackend(pool));
    });
  });
}

Future<_Backend> _nextRequestBackend(MainDbPool pool) =>
    pool.pool.withConnection((lease) async {
      final request = RequestContext(requestId: 'next-request');
      final scope = await RequestDbScope.open(lease, pool, request);
      try {
        return await _backend(lease);
      } finally {
        await scope.release();
        request.dispose();
      }
    });

final class _PoolEnv extends Env {
  _PoolEnv(Env base, {this.failControl = false})
    : super(
        environment: 'test',
        printEnv: false,
        isDebugModeOn: false,
        pgHost: base.pgHost,
        pgPort: base.pgPort,
        pgDatabase: base.pgDatabase,
        pgUsername: base.pgUsername,
        pgPassword: base.pgPassword,
        pgStatementTimeoutMs: 30000,
      );

  final bool failControl;
  int controlFailures = 0;
  ServerException? controlError;

  @override
  // ignore: overridden_fields
  late final pgEndpointSettings = ConnectionSettings(
    sslMode: SslMode.disable,
    onOpen: failControl
        ? (connection) async {
            controlFailures++;
            // A real server error on the separate control connection, without
            // breaking the application lease or replacing MainDbPool cancellation.
            try {
              await connection.execute('SELECT 1 / 0');
            } on ServerException catch (error) {
              controlError = error;
              rethrow;
            }
          }
        : null,
  );

  @override
  // ignore: overridden_fields
  late final pgPoolSettings = PoolSettings(
    maxConnectionCount: 1,
    maxConnectionAge: const Duration(hours: 1),
    maxSessionUse: const Duration(hours: 1),
    sslMode: SslMode.disable,
    onOpen: (connection) async {
      await connection.execute('SET statement_timeout = 30000');
      await connection.execute('SET lock_timeout = 0');
    },
  );
}

// Forward to a real pool lease, including close(force: ...). Only the chosen
// reset is replaced with an injected nonfatal SQLSTATE 57014 error, leaving
// the physical connection open with its existing settings.
final class _FaultConnection implements Connection {
  _FaultConnection(this.lease, {this.failedReset});

  final Connection lease;
  final String? failedReset;
  int resetFailures = 0;
  _Backend? backendAfterResetFailure;
  int cleanupCloseAttempts = 0;
  bool? wasOpenAtCleanupClose;
  int closeAttempts = 0;
  bool? wasOpenAtClose;
  final successfulResets = <String>[];
  final sleepDispatched = Completer<void>();

  @override
  bool get isOpen => lease.isOpen;

  @override
  Future<void> get closed => lease.closed;

  @override
  Future<void> close({bool force = false}) {
    closeAttempts++;
    wasOpenAtClose = lease.isOpen;
    if (resetFailures > 0) {
      cleanupCloseAttempts++;
      wasOpenAtCleanupClose = lease.isOpen;
    }
    return lease.close(force: force);
  }

  @override
  Future<Result> execute(
    Object query, {
    Object? parameters,
    bool ignoreRows = false,
    QueryMode? queryMode,
    Duration? timeout,
  }) async {
    if (failedReset != null &&
        query is String &&
        query.startsWith('SET $failedReset = ')) {
      try {
        return await lease.execute(r'''
          DO $$ BEGIN
            RAISE EXCEPTION 'injected reset SQL failure' USING ERRCODE = '57014';
          END $$
        ''');
      } on ServerException catch (error) {
        expect(error.code, '57014');
        resetFailures++;
        // A successful query here establishes that the injected reset failure
        // did not itself disconnect or poison the underlying pool lease.
        backendAfterResetFailure = await _backend(lease);
        rethrow;
      }
    }
    final result = lease.execute(
      query,
      parameters: parameters,
      ignoreRows: ignoreRows,
      queryMode: queryMode,
      timeout: timeout,
    );
    if (query == 'SELECT pg_sleep(0.5)') sleepDispatched.complete();
    final rows = await result;
    if (query is String &&
        (query.startsWith('SET statement_timeout = ') ||
            query.startsWith('SET lock_timeout = '))) {
      successfulResets.add(query);
    }
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
