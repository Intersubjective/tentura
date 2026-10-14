@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';

const _actors = ['Uscopedactor01', 'Uscopedactor02'];
const _barrierLock = 763421;
const _stateSql = '''
SELECT pg_backend_pid() AS pid,
       txid_current()::text AS tx,
       coalesce(current_setting('tentura.mutating_user_id', true), '') AS actor,
       coalesce(current_setting('tentura.scope_probe', true), '') AS token,
       current_setting('lock_timeout') AS lock_timeout,
       current_setting('statement_timeout') AS statement_timeout
''';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SCOPED_MUTATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_scoped_mutation',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late _Harness harness;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    await session.writer.execute('''
CREATE TABLE public.scoped_mutation_probe (
  scope_id text NOT NULL,
  repository text NOT NULL,
  stage text NOT NULL,
  actor text NOT NULL,
  backend_pid integer NOT NULL,
  transaction_id text NOT NULL,
  PRIMARY KEY (scope_id, repository, stage)
)
''');
  });
  setUp(() async {
    await session.writer.execute('TRUNCATE public.scoped_mutation_probe');
    harness = _Harness(target.databaseEnv, session.writer);
  });
  tearDown(() => harness.database.close());
  tearDownAll(() => tearDownDisposablePgWriter(session: session));

  group('Connection-scoped mutating units of work', () {
    test(
      'independent scopes overlap on distinct backends and share one handle '
      'across their repositories',
      () async {
        final pair = await _runPair(
          harness,
          'parallel',
          action: (index, before) async {
            await harness.left.write('scope_$index', 'outer');
            await harness.right.write('scope_$index', 'outer');
            expect(await _probe(harness.database), before);
          },
        );

        pair.outcomes.forEach(_expectSuccess);
        final rows = await session.writer.execute('''
SELECT scope_id, repository, actor, backend_pid, transaction_id
FROM public.scoped_mutation_probe ORDER BY scope_id, repository
''');
        expect(rows, hasLength(4));
        for (var index = 0; index < 2; index++) {
          final probe = pair.outcomes[index].probe!;
          expect(rows.skip(index * 2).take(2).map((row) => row.toList()), [
            ['scope_$index', 'left', _actors[index], probe.pid, probe.tx],
            ['scope_$index', 'right', _actors[index], probe.pid, probe.tx],
          ]);
        }
        expect(
          pair.heldPids,
          hasLength(2),
          reason:
              'Two admitted scopes must reach SQL while both are held at '
              'the barrier; one shared Drift executor serializes them.',
        );
        expect(
          pair.outcomes.map((outcome) => outcome.probe!.pid).toSet(),
          hasLength(2),
        );
        expect(
          pair.outcomes.map((outcome) => outcome.probe!.tx).toSet(),
          hasLength(2),
        );
        expect(harness.env.connections, hasLength(2));
      },
    );

    test(
      'overlapping scopes keep actor and GUC state local while nested '
      'savepoints use the parent lease and rollback stays atomic',
      () async {
        final abortSavepoint = StateError('discard savepoint');
        final abortScope = StateError('discard outer scope');
        final pair = await _runPair(
          harness,
          'nested',
          action: (index, before) async {
            final scopeId = 'scope_$index';
            expect(before.actor, _actors[index]);
            expect(before.token, 'scope_token_$index');
            expect(before.lockTimeout, index == 0 ? '41s' : '42s');
            expect(before.statementTimeout, index == 0 ? '61s' : '62s');
            await harness.left.write(scopeId, 'outer');

            // Both outer scopes retain their connections until BOTH actions
            // finish. With a two-connection budget a second nested lease cannot
            // make progress, even if a different backend would look harmless.
            await harness.unitOfWork.run<void>(
              actorUserId: _actors[index],
              action: () async {
                expect(await _probe(harness.database), before);
                await harness.database.transaction(() async {
                  await harness.right.write(scopeId, 'nested_commit');
                  await expectLater(
                    harness.database.transaction<void>(() async {
                      await harness.left.write(scopeId, 'nested_rollback');
                      await harness.database.customStatement(
                        "SELECT set_config('tentura.scope_probe', 'discarded', true), "
                        "set_config('lock_timeout', '333ms', true)",
                      );
                      throw abortSavepoint;
                    }, requireNew: true),
                    throwsA(same(abortSavepoint)),
                  );
                  expect(await _probe(harness.database), before);
                  await harness.database.batch((batch) {
                    batch
                      ..customStatement(harness.left.insertSql, [
                        scopeId,
                        'batch',
                      ])
                      ..customStatement(harness.right.insertSql, [
                        scopeId,
                        'batch',
                      ]);
                  });
                }, requireNew: true);
                expect(await _probe(harness.database), before);
              },
            );
            if (index == 1) throw abortScope;
          },
        );

        _expectSuccess(pair.outcomes[0]);
        expect(pair.outcomes[1].error, same(abortScope));
        final rows = await session.writer.execute('''
SELECT scope_id, repository, stage, actor, backend_pid, transaction_id
FROM public.scoped_mutation_probe ORDER BY repository, stage
''');
        final committed = pair.outcomes[0].probe!;
        expect(rows.map((row) => row.toList()), [
          ['scope_0', 'left', 'batch', _actors[0], committed.pid, committed.tx],
          ['scope_0', 'left', 'outer', _actors[0], committed.pid, committed.tx],
          [
            'scope_0',
            'right',
            'batch',
            _actors[0],
            committed.pid,
            committed.tx,
          ],
          [
            'scope_0',
            'right',
            'nested_commit',
            _actors[0],
            committed.pid,
            committed.tx,
          ],
        ]);

        // Inspect every still-open physical session, including the one which
        // rolled back, before another actor could overwrite leaked settings.
        for (final entry in harness.env.connections.entries) {
          if (!entry.value.isOpen) continue;
          expect(
            await _sessionState(entry.value),
            harness.env.initialStates[entry.key],
          );
        }
        final activeTransactions = await session.writer.execute(
          Sql.named('''
SELECT count(*) FROM pg_stat_activity
WHERE datname = @database AND state LIKE 'idle in transaction%'
  AND pid <> pg_backend_pid()
'''),
          parameters: {'database': target.databaseName},
        );
        expect(activeTransactions.single.single, 0);

        final reused = await _runPair(
          harness,
          'reuse',
          actors: const [null, null],
          configureLocalState: false,
          action: (index, before) async {
            expect(before.actor, isEmpty);
            expect(before.token, isEmpty);
            // The disposable database's own default: scope-local values from
            // the earlier pair must not have leaked into the reused session.
            expect(before.lockTimeout, disposablePgLockTimeoutSetting);
            expect(before.statementTimeout, '65s');
            expect(await _probe(harness.database), before);
          },
        );
        reused.outcomes.forEach(_expectSuccess);
        expect(
          reused.outcomes.map((outcome) => outcome.probe!.pid),
          contains(committed.pid),
        );
        expect(
          pair.heldPids,
          hasLength(2),
          reason: 'Nested work must run while both outer leases are occupied.',
        );
        expect(reused.heldPids, hasLength(2));
      },
    );

    test(
      'nested scopes reject an incompatible isolation level before running SQL',
      () async {
        var nestedActionRan = false;
        await harness.unitOfWork.run<void>(
          actorUserId: _actors[0],
          action: () async {
            final outer = await _probe(harness.database);
            final isolation = await harness.database
                .customSelect(
                  "SELECT current_setting('transaction_isolation') AS isolation",
                )
                .getSingle();
            expect(isolation.read<String>('isolation'), 'read committed');
            await expectLater(
              harness.database.withMutatingRepeatableRead<void>(
                _actors[0],
                () async {
                  nestedActionRan = true;
                  await harness.right.write('incompatible', 'nested');
                },
              ),
              throwsA(isA<StateError>()),
            );
            expect(nestedActionRan, isFalse);
            expect(await _probe(harness.database), outer);
            await harness.left.write('compatible', 'outer');
          },
        );
        final rows = await session.writer.execute(
          'SELECT scope_id FROM public.scoped_mutation_probe',
        );
        expect(rows.map((row) => row.single), ['compatible']);
      },
    );
  });
}

typedef _Probe = ({
  int pid,
  String tx,
  String actor,
  String token,
  String lockTimeout,
  String statementTimeout,
});
typedef _SessionState = ({
  String actor,
  String token,
  String lockTimeout,
  String statementTimeout,
});
typedef _Outcome = ({_Probe? probe, Object? error, StackTrace? stackTrace});
typedef _Pair = ({List<int> heldPids, List<_Outcome> outcomes});

Future<_Probe> _probe(TenturaDb database, {String sql = _stateSql}) async {
  final row = await database.customSelect(sql).getSingle();
  return (
    pid: row.read<int>('pid'),
    tx: row.read<String>('tx'),
    actor: row.read<String>('actor'),
    token: row.read<String>('token'),
    lockTimeout: row.read<String>('lock_timeout'),
    statementTimeout: row.read<String>('statement_timeout'),
  );
}

Future<_SessionState> _sessionState(Connection connection) async {
  final row = (await connection.execute(_stateSql)).single;
  return (
    actor: row[2]! as String,
    token: row[3]! as String,
    lockTimeout: row[4]! as String,
    statementTimeout: row[5]! as String,
  );
}

void _expectSuccess(_Outcome outcome) {
  if (outcome.error != null) {
    Error.throwWithStackTrace(outcome.error!, outcome.stackTrace!);
  }
  expect(outcome.probe, isNotNull);
}

Future<_Pair> _runPair(
  _Harness harness,
  String marker, {
  required Future<void> Function(int index, _Probe before) action,
  List<String?> actors = _actors,
  bool configureLocalState = true,
}) async {
  final writer = harness.writer;
  final database = harness.database;
  final finished = Completer<void>();
  var finishedCount = 0;
  var heldPids = <int>[];
  await writer.execute('SELECT pg_advisory_lock($_barrierLock)');

  Future<_Outcome> run(int index) async {
    _Probe? before;
    try {
      await harness.unitOfWork.run<void>(
        actorUserId: actors[index],
        action: () async {
          try {
            if (configureLocalState) {
              await database.customStatement(
                r"SELECT set_config('tentura.scope_probe', $1, true), "
                r"set_config('lock_timeout', $2, true), "
                r"set_config('statement_timeout', $3, true)",
                [
                  'scope_token_$index',
                  '${41 + index}s',
                  '${61 + index}s',
                ],
              );
            }
            // Shared locks are compatible after the observer drops its
            // exclusive lock. The blocked state is stable until that release.
            before = await _probe(
              database,
              sql:
                  '''
/* scoped_mutation_barrier:$marker */
$_stateSql, pg_advisory_xact_lock_shared($_barrierLock)
''',
            );
            await action(index, before!);
          } finally {
            if (heldPids.length == 2) {
              if (++finishedCount == 2) finished.complete();
              await finished.future.timeout(kCompletionWait);
            }
          }
        },
      );
      return (probe: before, error: null, stackTrace: null);
    } on Object catch (error, stackTrace) {
      return (probe: before, error: error, stackTrace: stackTrace);
    }
  }

  // A single production unit of work and repository pair serves BOTH calls.
  // Opening independent TenturaDb owners here would bypass the shared-lock
  // regression and could pass without implementing connection-scoped access.
  final pending = [run(0), run(1)];
  Object? observationError;
  StackTrace? observationStack;
  try {
    final deadline = DateTime.now().add(kStableStateWait);
    while (true) {
      final rows = await writer.execute(
        Sql.named('''
SELECT pid FROM pg_stat_activity
WHERE datname = @database AND pid <> pg_backend_pid()
  AND state = 'active' AND wait_event_type = 'Lock'
  AND query LIKE @marker
ORDER BY pid
'''),
        parameters: {
          'database': harness.env.pgDatabase,
          'marker': '%scoped_mutation_barrier:$marker%',
        },
      );
      heldPids = rows.map((row) => row.single! as int).toList();
      if (heldPids.length == 2 || DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  } on Object catch (error, stackTrace) {
    observationError = error;
    observationStack = stackTrace;
  } finally {
    await writer.execute('SELECT pg_advisory_unlock($_barrierLock)');
  }
  // Drain both actions, including rollback, even when overlap was absent.
  final outcomes = await Future.wait(pending).timeout(kCompletionWait);
  if (observationError != null) {
    Error.throwWithStackTrace(observationError, observationStack!);
  }
  return (heldPids: heldPids, outcomes: outcomes);
}

final class _Harness {
  _Harness(Env postgres, this.writer) : env = _ScopePoolEnv(postgres) {
    database = TenturaDb(env);
    unitOfWork = MutatingUnitOfWork(database);
    left = _ProbeRepository(database, 'left');
    right = _ProbeRepository(database, 'right');
  }

  final _ScopePoolEnv env;
  final Connection writer;
  late final TenturaDb database;
  late final MutatingUnitOfWorkPort unitOfWork;
  late final _ProbeRepository left;
  late final _ProbeRepository right;
}

// Only records SQL's actual actor, transaction and backend. It does not
// implement scopes, leases, transaction dispatch, or repository rebinding.
final class _ProbeRepository {
  const _ProbeRepository(this.database, this.name);

  final TenturaDb database;
  final String name;

  String get insertSql =>
      '''
INSERT INTO public.scoped_mutation_probe
  (scope_id, repository, stage, actor, backend_pid, transaction_id)
VALUES (\$1, '$name', \$2,
        coalesce(current_setting('tentura.mutating_user_id', true), ''),
        pg_backend_pid(), txid_current()::text)
''';

  Future<void> write(String scopeId, String stage) =>
      database.customStatement(insertSql, [scopeId, stage]);
}

// Supply two available pool slots without using separate pools, which would
// test a different concurrency path.
final class _ScopePoolEnv extends Env {
  _ScopePoolEnv(Env postgres)
    : super(
        environment: Environment.test,
        printEnv: false,
        isDebugModeOn: false,
        pgHost: postgres.pgHost,
        pgPort: postgres.pgPort,
        pgDatabase: postgres.pgDatabase,
        pgUsername: postgres.pgUsername,
        pgPassword: postgres.pgPassword,
        maxConnectionAge: 3600,
        pgStatementTimeoutMs: 65000,
        maxConnectionCount: 2,
      );

  final connections = <int, Connection>{};
  final initialStates = <int, _SessionState>{};

  @override
  // Test-only: Env exposes this as a plain field; the harness needs a custom value.
  // ignore: overridden_fields
  late final pgPoolSettings = PoolSettings(
    maxConnectionCount: 2,
    maxConnectionAge: const Duration(hours: 1),
    maxSessionUse: const Duration(hours: 1),
    connectTimeout: const Duration(seconds: 5),
    sslMode: SslMode.disable,
    onOpen: (connection) async {
      await connection.execute('SET statement_timeout = 65000');
      final pid =
          (await connection.execute('SELECT pg_backend_pid()')).single.single!
              as int;
      connections[pid] = connection;
      initialStates[pid] = await _sessionState(connection);
    },
  );
}
