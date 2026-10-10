@Tags(['pg'])
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/backends.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';
import '../../support/transaction_pinned_pool_env.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TRANSACTION_PINNED_POOL_TEST_DB',
    defaultNamePrefix: 'tentura_test_tx_pool',
  );
  final pgUnavailableReason = await pgSkipReason(target);
  final reachable = pgUnavailableReason == null;
  final skipReason = pgUnavailableReason ?? false;
  DisposablePgWriterSession? session;

  group('Transaction-pinned Drift pool', () {
    // Like other red-phase PG contract tests, this needs no database. It keeps
    // a missing prototype distinguishable from an unavailable local PG server.
    test('the opt-in configuration permits two pooled sessions', () {
      final env = transactionPinnedPoolEnv(enabled: true);
      expect(transactionPinnedPoolEnabled(env), isTrue);
      expect(env.pgPoolSettings.maxConnectionCount, 2);
    });

    setUpAll(() async {
      if (!reachable) return;
      session = await setUpDisposablePgWriter(target: target);
      await session!.writer.execute('''
        CREATE TABLE public.transaction_pool_probe (
          id text PRIMARY KEY,
          actor text NOT NULL,
          backend_pid integer NOT NULL
        )
      ''');
    });

    setUp(() async {
      if (!reachable) return;
      await session!.writer.execute('TRUNCATE public.transaction_pool_probe');
    });

    tearDownAll(() async {
      if (session case final opened?) {
        await tearDownDisposablePgWriter(session: opened);
      }
    });

    for (final enabled in [false, true]) {
      test(
        enabled
            ? 'enabled executor preserves nested savepoints under pool pressure'
            : 'flag-off production executor raises 25P01 when nested savepoint '
                  'loses its connection',
        () async {
          final configured = transactionPinnedPoolEnv(
            enabled: enabled,
            postgres: target.databaseEnv,
          );
          final env = _ObservedPoolEnv(
            configured,
            forceTwoConnections: !enabled,
          );
          await _assertNestedSavepointConnectionPressure(
            env,
            session!.writer,
            enabled: enabled,
          );
        },
        skip: skipReason,
      );
    }

    test(
      'runtime opt-in selects a pinned executor for nested savepoint pressure',
      () async {
        // No constructor override: exercise the same production wiring with
        // the flag supplied solely through Platform.environment.
        final env = _ObservedPoolEnv(
          transactionPinnedPoolEnv(postgres: target.databaseEnv),
        );
        await _assertNestedSavepointConnectionPressure(
          env,
          session!.writer,
          enabled: true,
        );
      },
      skip:
          Platform.environment['DRIFT_TRANSACTION_PINNED_POOL_ENABLED'] !=
              'true'
          ? 'Requires DRIFT_TRANSACTION_PINNED_POOL_ENABLED=true'
          : skipReason,
    );

    for (final capacity in [2, 3]) {
      test(
        '$capacity concurrent transactions keep nested savepoints and '
        'mutating actors on separate sessions',
        () async {
          final env = transactionPinnedPoolEnv(
            enabled: true,
            maxConnectionCount: capacity,
            postgres: target.databaseEnv,
          );
          expect(env.pgPoolSettings.maxConnectionCount, capacity);
          final owner = TenturaDb(env);
          addTearDown(owner.close);
          await owner.customSelect('SELECT 1').get();

          // Two logical Drift handles share the actual selected executor and
          // pool. Separate TenturaDb instances with separate pools could pass
          // without offering any transaction concurrency on a shared pool.
          final handles = List.generate(
            capacity,
            (_) => TenturaDb.forTest(database: owner.executor),
          );
          final overlap = _TransactionOverlap(capacity);
          final probes = await Future.wait([
            for (var index = 0; index < capacity; index++)
              handles[index].withMutatingUser('actor_$index', () async {
                final probe = await _probe(handles[index]);
                await overlap.enter();
                await _nestedWrites(
                  handles[index],
                  'tx_$index',
                  'actor_$index',
                );
                expect(await _probe(handles[index]), probe);
                return probe;
              }),
          ]);

          expect(probes.map((probe) => probe.pid).toSet(), hasLength(capacity));
          expect(probes.map((probe) => probe.tx).toSet(), hasLength(capacity));
          final rows = await _persistedRows(session!.writer);
          expect(rows, hasLength(capacity * 3));
          for (var index = 0; index < capacity; index++) {
            expect(
              rows.where((row) => row[0].toString().startsWith('tx_$index:')),
              unorderedEquals([
                ['tx_$index:outer', 'actor_$index', probes[index].pid],
                ['tx_$index:committed', 'actor_$index', probes[index].pid],
                ['tx_$index:deep', 'actor_$index', probes[index].pid],
              ]),
            );
            expect(handles[index].isInAmbientMutatingTransaction, isFalse);
          }

          // Lease every pooled session again without installing an actor. This
          // catches GUC/context leakage even when later mutations set new actors.
          final reuseOverlap = _TransactionOverlap(capacity);
          final reused = await Future.wait([
            for (final handle in handles)
              handle.transaction(() async {
                final probe = await _probe(handle);
                expect(handle.isInAmbientMutatingTransaction, isFalse);
                await reuseOverlap.enter();
                return probe;
              }),
          ]);
          expect(
            reused.map((probe) => probe.pid).toSet(),
            probes.map((probe) => probe.pid).toSet(),
          );
          expect(reused.map((probe) => probe.actor), everyElement(isEmpty));
        },
        skip: skipReason,
      );
    }

    test(
      'outer rollback clears writes and actor context before the session is reused',
      () async {
        final env = transactionPinnedPoolEnv(
          enabled: true,
          postgres: target.databaseEnv,
        );
        final owner = TenturaDb(env);
        addTearDown(owner.close);
        final db = TenturaDb.forTest(database: owner.executor);
        final abort = StateError('abort outer transaction');

        await expectLater(
          db.withMutatingUser('aborted_actor', () async {
            await _nestedWrites(db, 'aborted', 'aborted_actor');
            throw abort;
          }),
          throwsA(same(abort)),
        );
        expect(await _persistedRows(session!.writer), isEmpty);
        expect(db.isInAmbientMutatingTransaction, isFalse);
        expect((await _probe(db)).actor, isEmpty);

        await db.withMutatingUser(
          'next_actor',
          () => _nestedWrites(db, 'next', 'next_actor'),
        );
        expect(await _persistedRows(session!.writer), hasLength(3));
      },
      skip: skipReason,
    );

    test(
      'flag-off transactions preserve nested savepoint behavior on one session',
      () async {
        final env = transactionPinnedPoolEnv(
          enabled: false,
          maxConnectionCount: 3,
          postgres: target.databaseEnv,
        );
        expect(transactionPinnedPoolEnabled(env), isFalse);
        expect(env.pgPoolSettings.maxConnectionCount, 1);
        final db = TenturaDb(env);
        addTearDown(db.close);

        await db.withMutatingUser(
          'compatible_actor',
          () => _nestedWrites(db, 'compatible', 'compatible_actor'),
        );
        expect(await _persistedRows(session!.writer), hasLength(3));
        expect((await _probe(db)).actor, isEmpty);
      },
      skip: skipReason,
    );
  });
}

/// Both flag states replay identical SQL and advisory-lock choreography:
/// warm two backends, enter nested savepoints, then block an ordinary pool
/// query just before RELEASE SAVEPOINT. Only the expected backend and outcome
/// differ. The enabled executor must retain its leased transaction backend.
Future<void> _assertNestedSavepointConnectionPressure(
  _ObservedPoolEnv env,
  Connection writer, {
  required bool enabled,
}) async {
  expect(transactionPinnedPoolEnabled(env), enabled);
  expect(env.pgPoolSettings.maxConnectionCount, 2);
  addTearDown(env.closeConnections);
  final owner = TenturaDb(env);
  addTearDown(owner.close);
  await owner.customSelect('SELECT 1').get();
  final executor = owner.executor;
  final warmPids = await _warmProductionExecutor(executor, writer);
  expect(warmPids, hasLength(2));
  expect(env.connections.keys.toSet(), warmPids);

  // Sharing the production-selected executor bypasses the existing
  // TenturaDb.transaction shim, so this proves executor-level pinning.
  final db = TenturaDb.forTest(database: executor);
  final ordinaryPoolZone = Zone.current;
  Future<int>? competingQuery;
  _SessionProbe? transactionProbe;
  Object? failure;
  int? competingPid;

  try {
    await db.withMutatingUser('pressure_actor', () async {
      transactionProbe = await _probe(db);
      await _nestedWrites(
        db,
        'pressure',
        'pressure_actor',
        beforeNestedCommit: (transactionPid) async {
          await writer.execute('SELECT pg_advisory_lock($_controlLock)');
          competingQuery = ordinaryPoolZone.run(
            () => _poolQueryPid(
              executor,
              'SELECT pg_backend_pid() AS pid, '
              'pg_advisory_xact_lock($_controlLock) '
              '/* transaction_pool_control */',
            ),
          );
          final blocked = await _blockedSessions(
            writer,
            label: 'transaction_pool_control',
            count: 1,
          );
          competingPid = blocked.single;
          expect(warmPids, contains(competingPid));
          expect(
            competingPid,
            enabled ? isNot(transactionPid) : transactionPid,
            reason:
                'A pinned transaction backend cannot be borrowed by '
                'the blocked ordinary pool query.',
          );
        },
      );
      expect(await _probe(db), transactionProbe);
    });
  } on Object catch (error) {
    failure = error;
  } finally {
    await writer.execute('SELECT pg_advisory_unlock($_controlLock)');
    try {
      if (competingQuery != null) {
        expect(await competingQuery!.timeout(kCompletionWait), competingPid);
      }
    } finally {
      // An unpinned executor can leave its original backend in an aborted
      // transaction while attempting rollback on the other backend.
      for (final connection in env.connections.values) {
        if (connection.isOpen) await connection.execute('ROLLBACK');
      }
    }
  }

  if (!enabled) {
    expect(
      _sqlStates(failure),
      contains('25P01'),
      reason:
          'The unpinned two-connection control must reproduce the real '
          'PostgreSQL no-active-transaction error: $failure',
    );
    expect(await _persistedRows(writer), isEmpty);
    return;
  }

  expect(
    failure,
    isNull,
    reason:
        'The enabled executor must pass the same nested-savepoint '
        'pressure scenario that produces 25P01 in the unpinned control.',
  );
  expect(
    await _persistedRows(writer),
    unorderedEquals([
      ['pressure:outer', 'pressure_actor', transactionProbe!.pid],
      ['pressure:committed', 'pressure_actor', transactionProbe!.pid],
      ['pressure:deep', 'pressure_actor', transactionProbe!.pid],
    ]),
  );
  expect(db.isInAmbientMutatingTransaction, isFalse);
  expect((await _probe(db)).actor, isEmpty);
}

typedef _SessionProbe = ({int pid, String tx, String actor});

Future<_SessionProbe> _probe(TenturaDb db) async {
  final row = await db.customSelect('''
    SELECT pg_backend_pid() AS pid, txid_current()::text AS tx,
           coalesce(current_setting('tentura.mutating_user_id', true), '') AS actor
  ''').getSingle();
  return (
    pid: row.read<int>('pid'),
    tx: row.read<String>('tx'),
    actor: row.read<String>('actor'),
  );
}

Future<void> _insert(TenturaDb db, String id) => db.customStatement(
  'INSERT INTO public.transaction_pool_probe (id, actor, backend_pid) '
  r"VALUES ($1, current_setting('tentura.mutating_user_id'), pg_backend_pid())",
  [id],
);

Future<void> _nestedWrites(
  TenturaDb db,
  String prefix,
  String actor, {
  Future<void> Function(int pid)? beforeNestedCommit,
}) async {
  final initial = await _probe(db);
  expect(initial.actor, actor);
  expect(db.isInAmbientMutatingTransaction, isTrue);
  await _insert(db, '$prefix:outer');
  await db.withMutatingUser(actor, () async {
    expect(await _probe(db), initial);
  });
  var mismatchedActorRan = false;
  await expectLater(
    db.withMutatingUser('${actor}_other', () async {
      mismatchedActorRan = true;
    }),
    throwsA(isA<StateError>()),
  );
  expect(mismatchedActorRan, isFalse);

  final abortNested = StateError('abort nested transaction');
  await expectLater(
    db.transaction(
      () async {
        await _insert(db, '$prefix:rolled_back');
        throw abortNested;
      },
      requireNew: true,
    ),
    throwsA(same(abortNested)),
  );
  expect(await _probe(db), initial);
  await db.transaction(
    () async {
      await _insert(db, '$prefix:committed');
      await db.transaction(
        () async {
          await _insert(db, '$prefix:deep');
          expect(await _probe(db), initial);
        },
        requireNew: true,
      );
      await beforeNestedCommit?.call(initial.pid);
    },
    requireNew: true,
  );
  expect(await _probe(db), initial);
}

Future<List<List<Object?>>> _persistedRows(Connection writer) async {
  final rows = await writer.execute(
    'SELECT id, actor, backend_pid FROM public.transaction_pool_probe ORDER BY id',
  );
  return rows.map((row) => row.toList()).toList();
}

Set<String?> _sqlStates(Object? error) => switch (error) {
  ServerException(:final code) => {code},
  CouldNotRollBackException(:final cause, :final exception) => {
    ..._sqlStates(cause),
    ..._sqlStates(exception),
  },
  _ => {},
};

// Observe the real pool in both flag states. Only the legacy reproduction
// forces two connections; the enabled case keeps Env's configured capacity.
final class _ObservedPoolEnv extends Env {
  _ObservedPoolEnv(this._configured, {this.forceTwoConnections = false})
    : super(
        environment: Environment.test,
        printEnv: false,
        isDebugModeOn: false,
        pgHost: _configured.pgHost,
        pgPort: _configured.pgPort,
        pgDatabase: _configured.pgDatabase,
        pgUsername: _configured.pgUsername,
        pgPassword: _configured.pgPassword,
        maxConnectionCount: 2,
        maxConnectionAge: _configured.pgMaxConnectionAge,
        pgStatementTimeoutMs: _configured.pgStatementTimeoutMs,
      );

  final Env _configured;
  final bool forceTwoConnections;
  final connections = <int, Connection>{};

  // The real flag must exist on the configured Env before this delegate can
  // return it; this is not a test-only substitute for the missing opt-in.
  @override
  // The getter must compile before Env declares the experimental flag.
  // ignore: override_on_non_overriding_member
  bool get driftTransactionPinnedPoolEnabled =>
      transactionPinnedPoolEnabled(_configured);

  @override
  PoolSettings get pgPoolSettings => _observedPoolSettings;

  late final _observedPoolSettings = PoolSettings(
    maxConnectionCount: forceTwoConnections
        ? 2
        : _configured.pgPoolSettings.maxConnectionCount,
    maxConnectionAge: _configured.pgPoolSettings.maxConnectionAge,
    maxSessionUse: _configured.pgPoolSettings.maxSessionUse,
    sslMode: _configured.pgPoolSettings.sslMode,
    onOpen: (connection) async {
      await _configured.pgPoolSettings.onOpen?.call(connection);
      final rows = await connection.execute('SELECT pg_backend_pid()');
      connections[rows.single.single! as int] = connection;
    },
  );

  Future<void> closeConnections() async {
    for (final connection in connections.values) {
      await connection.close(force: true);
    }
  }
}

const _warmLock = 227301;
const _controlLock = 227302;

/// Access the selected executor's pool without Drift's per-database queue.
/// A delegated executor exposes its ordinary session through its delegate;
/// another QueryExecutor implementation can provide concurrent root queries.
Future<int> _poolQueryPid(QueryExecutor executor, String sql) async {
  if (executor is DelegatedDatabase) {
    final result = await executor.delegate.runSelect(sql, const []);
    return result.rows.single.first! as int;
  }
  final rows = await executor.runSelect(sql, const []);
  return rows.single['pid']! as int;
}

Future<Set<int>> _warmProductionExecutor(
  QueryExecutor executor,
  Connection writer,
) async {
  await writer.execute('SELECT pg_advisory_lock($_warmLock)');
  final queries = Future.wait([
    for (var index = 0; index < 2; index++)
      _poolQueryPid(
        executor,
        'SELECT pg_backend_pid() AS pid, pg_advisory_xact_lock($_warmLock) '
        '/* transaction_pool_warm */',
      ),
  ]);
  try {
    await _blockedSessions(writer, label: 'transaction_pool_warm', count: 2);
  } finally {
    await writer.execute('SELECT pg_advisory_unlock($_warmLock)');
  }
  return (await queries.timeout(kCompletionWait)).toSet();
}

Future<List<int>> _blockedSessions(
  Connection writer, {
  required String label,
  required int count,
}) async {
  final deadline = DateTime.now().add(kStableStateWait);
  while (true) {
    final rows = await writer.execute(
      Sql.named('''
        SELECT pid FROM pg_stat_activity
        WHERE datname = current_database()
          AND pid <> pg_backend_pid()
          AND query LIKE @label
          AND wait_event = 'advisory'
        ORDER BY pid
      '''),
      parameters: {'label': '%$label%'},
    );
    if (rows.length == count) {
      return [for (final row in rows) row.single! as int];
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('Expected $count pooled sessions waiting at $label; found $rows.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

final class _TransactionOverlap {
  _TransactionOverlap(this.expected);

  final int expected;
  final _allEntered = Completer<void>();
  var _entered = 0;

  Future<void> enter() {
    if (++_entered == expected) _allEntered.complete();
    return _allEntered.future.timeout(
      kStableStateWait,
      onTimeout: () => fail(
        '$expected transaction leases must overlap; only $_entered entered. '
        'Serial execution does not exercise a multi-connection transaction pool.',
      ),
    );
  }
}
