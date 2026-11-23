@Tags(['pg'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
// The VM test runner supports mirrors. The Flutter workspace SDK hides them
// from its analyzer. Remove this import when the production port can be imported.
// ignore: uri_does_not_exist
import 'dart:mirrors' as vm;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/postgres_serialization_retry.dart'
    show
        PostgresRetryDeadlineExceededException,
        PostgresSnapshotUnavailableException;
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

const _ownerA = 'Uownergrapha1';
const _ownerB = 'Uownergraphb2';
const _actor = 'Uowneractor01';
const _differentActor = 'Uowneractor02';
const _owners = {_ownerA, _ownerB};
const _reverseOwners = {_ownerB, _ownerA};
const _retryBudget = Duration(seconds: 5);
const _completionLimit = Duration(seconds: 6);
const _ownerGraphKey = "hashtextextended('owner_graph:' || @1, 4242)";
const _insertProbe = r'INSERT INTO owner_graph_probe (label) VALUES ($1)';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_OWNER_GRAPH_TEST_DB',
    defaultNamePrefix: 'tentura_test_owner_graph',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late _SqlLog sql;

  TenturaDb openDatabase(_SqlLog log) {
    final targetEnv = target.databaseEnv;
    final database = TenturaDb(
      Env(
        environment: Environment.test,
        pgHost: targetEnv.pgHost,
        pgPort: targetEnv.pgPort,
        pgDatabase: targetEnv.pgDatabase,
        pgUsername: targetEnv.pgUsername,
        pgPassword: targetEnv.pgPassword,
        maxConnectionCount: 1,
        constellationDbMaxConcurrent: 1,
        printEnv: false,
        isDebugModeOn: false,
      ),
      scopeInterceptor: () => log,
    );
    addTearDown(database.close);
    return database;
  }

  setUpAll(() async {
    final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    // The concurrent tests use independent pools and executors.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous,
    );
    session = await setUpDisposablePgWriter(target: target);
    await session.writer.execute(
      'CREATE TABLE owner_graph_probe (label text PRIMARY KEY)',
    );
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session));

  setUp(() async {
    await session.writer.execute('TRUNCATE owner_graph_probe');
    sql = _SqlLog();
    db = openDatabase(sql);
  });

  Future<List<String>> committedLabels() async => [
    for (final row in await session.writer.execute(
      'SELECT label FROM owner_graph_probe ORDER BY label',
    ))
      row.single! as String,
  ];

  Future<Connection> openLockHolder() async {
    final holder = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    addTearDown(holder.close);
    return holder;
  }

  group('Owner-graph mutations', () {
    test(
      'expose exactly the requested owners and the mutating actor',
      () async {
        final graph = await _openOwnerGraph(db);
        final state = await graph.run(_owners, _actor, (scope) async {
          expect(_scopeOwners(scope), unorderedEquals(_owners));
          expect(db.isInAmbientMutatingTransaction, isTrue);
          return _readState(db);
        });

        expect(state.isolation, 'read committed');
        expect(state.actor, _actor);
        expect(state.owners, unorderedEquals(_owners));
        await _expectScopeCleared(db, state.pid);
      },
    );

    test('hold every requested advisory lock through commit', () async {
      final graph = await _openOwnerGraph(db);
      final observer = session.writer;

      final result = await graph.run(_owners, _actor, (_) async {
        expect(await _tryOwnerLock(observer, _ownerA), isFalse);
        expect(await _tryOwnerLock(observer, _ownerB), isFalse);
        return 'committed';
      });

      expect(result, 'committed');
      expect(await _tryOwnerLock(observer, _ownerA), isTrue);
      expect(await _tryOwnerLock(observer, _ownerB), isTrue);
    });

    test('take the owner locks first and in ascending owner order', () async {
      final graph = await _openOwnerGraph(db);
      final holder = await openLockHolder();
      await holder.execute('BEGIN');
      await holder.execute(
        Sql.indexed('SELECT pg_advisory_xact_lock($_ownerGraphKey)'),
        parameters: [_ownerB],
      );

      var bodyEntered = false;
      var finished = false;
      final operation =
          graph
              .run(_reverseOwners, _actor, (_) async {
                bodyEntered = true;
                return 'locked';
              })
              .whenComplete(() => finished = true)
            ..ignore();

      try {
        final pid = await _waitForOwnerLock(
          session.writer,
          _ownerB,
          isFinished: () => finished,
        );
        expect(
          await _ownerLocks(session.writer, _ownerA),
          contains((pid: pid, granted: true)),
          reason: 'The lower owner lock must already be held.',
        );
        expect(bodyEntered, isFalse);
        expect(sql.statements, isNotEmpty);
        expect(
          sql.statements,
          everyElement(contains('pg_advisory_xact_lock')),
          reason: 'Only owner lock statements may run before the last lock.',
        );
      } finally {
        await holder.execute('ROLLBACK');
      }
      expect(await operation.timeout(_completionLimit), 'locked');
    });

    test(
      'serialize overlapping owner sets submitted in opposite orders',
      () async {
        final firstGraph = await _openOwnerGraph(db);
        final otherSql = _SqlLog();
        final otherDb = openDatabase(otherSql);
        final secondGraph = await _openOwnerGraph(otherDb);
        final firstEntered = Completer<void>();
        final releaseFirst = Completer<void>();
        var firstCalls = 0;
        var secondCalls = 0;
        var secondFinished = false;

        final first = firstGraph.run(_owners, _actor, (_) async {
          firstCalls++;
          await db.customStatement(_insertProbe, ['first']);
          firstEntered.complete();
          await releaseFirst.future;
          return 'first';
        })..ignore();

        Future<String>? second;
        try {
          await Future.any([
            firstEntered.future,
            first.then<void>(
              (_) => fail('The first body did not reach its barrier.'),
            ),
          ]).timeout(_completionLimit);
          second =
              secondGraph
                  .run(_reverseOwners, _differentActor, (_) async {
                    secondCalls++;
                    return (await committedLabels()).single;
                  })
                  .whenComplete(() => secondFinished = true)
                ..ignore();

          await _waitForOwnerLock(
            session.writer,
            _ownerA,
            isFinished: () => secondFinished,
          );
          expect(secondCalls, 0);
        } finally {
          releaseFirst.complete();
          expect(await first.timeout(_completionLimit), 'first');
          if (second != null) {
            expect(await second.timeout(_completionLimit), 'first');
          }
        }

        expect(firstCalls, 1);
        expect(secondCalls, 1);
        expect(sql.begins, 1);
        expect(otherSql.begins, 1);
      },
    );

    for (final (code, failure) in [
      ('40001', 'serialization failure'),
      ('40P01', 'deadlock'),
    ]) {
      test(
        'replays the whole transaction after a PostgreSQL $failure',
        () async {
          final graph = await _openOwnerGraph(db);
          final transactions = <String>[];

          final result = await graph
              .run(_owners, _actor, (_) async {
                transactions.add((await _readState(db)).transaction);
                final label = 'attempt ${transactions.length}';
                await db.customStatement(_insertProbe, [label]);
                if (transactions.length == 1) await _raiseSqlState(db, code);
                return label;
              })
              .timeout(_completionLimit);

          expect(result, 'attempt 2');
          expect(transactions, hasLength(2));
          expect(transactions.toSet(), hasLength(2));
          expect(await committedLabels(), ['attempt 2']);
        },
      );
    }

    test('rethrows the serialization failure after three attempts', () async {
      final graph = await _openOwnerGraph(db);
      var attempts = 0;
      final clock = Stopwatch()..start();

      await expectLater(
        graph
            .run(_owners, _actor, (_) async {
              attempts++;
              await db.customStatement(_insertProbe, ['attempt $attempts']);
              await _raiseSqlState(db, '40001');
            })
            .timeout(_completionLimit),
        throwsA(_sqlState('40001')),
      );

      expect(attempts, 3);
      expect(clock.elapsed, lessThanOrEqualTo(_retryBudget));
      expect(await committedLabels(), isEmpty);
    });

    test(
      'a nested owner subset keeps the same transaction and held owners',
      () async {
        final graph = await _openOwnerGraph(db);

        final result = await graph.run(_owners, _actor, (_) async {
          final outer = await _readState(db);
          final beginsBefore = sql.begins;
          final statementsBefore = sql.statements.length;

          final value = await graph.run({_ownerA}, _actor, (_) async {
            expect(sql.statements.skip(statementsBefore), isEmpty);
            final inner = await _readState(db);
            expect(inner.transaction, outer.transaction);
            expect(inner.owners, unorderedEquals(_owners));
            return 'joined';
          });

          expect(
            sql.begins,
            beginsBefore,
            reason: 'A join must not open a savepoint.',
          );
          expect((await _readState(db)).owners, unorderedEquals(_owners));
          return value;
        });

        expect(result, 'joined');
      },
    );

    for (final (description, nestedOwners, nestedActor) in [
      ('a different actor', {_ownerA}, _differentActor),
      ('an owner outside the held set', _owners, _actor),
    ]) {
      test('rejects a nested mutation with $description', () async {
        final graph = await _openOwnerGraph(db);
        var innerRan = false;

        await graph.run({_ownerA}, _actor, (_) async {
          final beginsBefore = sql.begins;
          final statementsBefore = sql.statements.length;
          await expectLater(
            Future.sync(
              () => graph.run(nestedOwners, nestedActor, (_) async {
                innerRan = true;
              }),
            ),
            throwsA(isA<StateError>()),
          );
          expect(innerRan, isFalse);
          expect(sql.begins, beginsBefore);
          expect(sql.statements.skip(statementsBefore), isEmpty);
          expect((await _readState(db)).owners, [_ownerA]);
        });
      });
    }

    test(
      'only the owner of a joined transaction retries its failed body',
      () async {
        final graph = await _openOwnerGraph(db);
        final innerCallsPerOuterAttempt = <int>[];

        final result = await graph
            .run(_owners, _actor, (_) async {
              innerCallsPerOuterAttempt.add(0);
              final attempt = innerCallsPerOuterAttempt.length;
              return graph.run({_ownerA}, _actor, (_) async {
                innerCallsPerOuterAttempt[attempt - 1]++;
                await db.customStatement(_insertProbe, [
                  'nested attempt $attempt',
                ]);
                if (attempt == 1) await _raiseSqlState(db, '40001');
                return 'outer retried';
              });
            })
            .timeout(_completionLimit);

        expect(result, 'outer retried');
        expect(innerCallsPerOuterAttempt, [1, 1]);
        expect(await committedLabels(), ['nested attempt 2']);
      },
    );

    Future<void> expectAmbientRefusal(
      TenturaDb database,
      Future<void> Function(Future<void> Function()) enterAmbient,
    ) async {
      final graph = await _openOwnerGraph(database);
      await enterAmbient(() async {
        await database.customSelect('SELECT 1').getSingle();
        final beginsBefore = sql.begins;
        final statementsBefore = sql.statements.length;
        var bodyRan = false;

        await expectLater(
          Future.sync(
            () => graph.run(_owners, _actor, (_) async {
              bodyRan = true;
            }),
          ).timeout(_completionLimit),
          throwsA(isA<StateError>()),
        );

        expect(bodyRan, isFalse);
        expect(sql.begins, beginsBefore);
        expect(sql.statements.skip(statementsBefore), isEmpty);
      });
    }

    test(
      'refuses to start in an open transaction before issuing SQL',
      () async {
        final connection = await openLockHolder();
        // This Drift transaction has no pooled lease, so lease detection alone
        // cannot satisfy the transaction guard.
        final database = TenturaDb.forTest(
          database: PgDatabase.opened(
            connection,
            enableMigrations: false,
          ).interceptWith(sql),
        );
        addTearDown(database.close);
        await expectAmbientRefusal(database, database.transaction);
      },
    );

    test(
      'refuses to start on a leased connection before issuing SQL',
      () async {
        await expectAmbientRefusal(db, db.withConnectionScope);
      },
    );
  });

  group('Repeatable-read owner-graph mutations', () {
    test(
      'open one repeatable-read transaction with the owner and actor set',
      () async {
        final graph = await _openOwnerGraph(db);
        var bodyCalls = 0;

        final state = await graph.runRepeatableRead(_ownerA, _actor, (
          scope,
        ) async {
          bodyCalls++;
          expect(_scopeOwners(scope), [_ownerA]);
          return _readState(db);
        });

        expect(state.isolation, 'repeatable read');
        expect(state.actor, _actor);
        expect(state.owners, [_ownerA]);
        expect(bodyCalls, 1);
        expect(sql.begins, 1);
        expect(
          sql.statements.firstWhere(
            (statement) => !statement.startsWith('set '),
          ),
          contains('pg_try_advisory_xact_lock'),
          reason: 'The try-lock must precede snapshot-acquiring statements.',
        );
        await _expectScopeCleared(db, state.pid);
      },
    );

    test(
      'wait for a mutation on the same owner and start a fresh snapshot',
      () async {
        final writerGraph = await _openOwnerGraph(db);
        final otherSql = _SqlLog();
        final otherDb = openDatabase(otherSql);
        final readerGraph = await _openOwnerGraph(otherDb);
        final writerEntered = Completer<void>();
        final releaseWriter = Completer<void>();
        var readerFinished = false;
        var readerCalls = 0;

        final writing = writerGraph.run({_ownerA}, _actor, (_) async {
          await db.customStatement(_insertProbe, ['writer committed']);
          writerEntered.complete();
          await releaseWriter.future;
        })..ignore();

        Future<String>? reading;
        try {
          await Future.any([
            writerEntered.future,
            writing.then<void>(
              (_) => fail('The writer did not reach its barrier.'),
            ),
          ]).timeout(_completionLimit);
          reading =
              readerGraph
                  .runRepeatableRead(_ownerA, _differentActor, (_) async {
                    readerCalls++;
                    final row = await otherDb
                        .customSelect('SELECT label FROM owner_graph_probe')
                        .getSingle();
                    return row.read<String>('label');
                  })
                  .whenComplete(() => readerFinished = true)
                ..ignore();

          await _waitForOwnerLock(
            session.writer,
            _ownerA,
            isFinished: () => readerFinished,
          );
          expect(
            otherSql.statements,
            contains(contains('pg_try_advisory_xact_lock')),
          );
          expect(
            readerCalls,
            0,
            reason: 'The stale attempt must not reach the body.',
          );
        } finally {
          releaseWriter.complete();
          await writing.timeout(_completionLimit);
          if (reading != null) {
            expect(await reading.timeout(_completionLimit), 'writer committed');
          }
        }

        expect(readerCalls, 1);
        expect(otherSql.begins, 2);
        expect(otherSql.rollbacks, 1);
      },
    );

    test(
      'stop waiting within the retry budget if the owner remains locked',
      () async {
        final graph = await _openOwnerGraph(db);
        final holder = await openLockHolder();
        await holder.execute('BEGIN');
        await holder.execute(
          Sql.indexed('SELECT pg_advisory_xact_lock($_ownerGraphKey)'),
          parameters: [_ownerA],
        );
        var bodyRan = false;
        final clock = Stopwatch()..start();

        try {
          await expectLater(
            graph
                .runRepeatableRead(_ownerA, _actor, (_) async {
                  bodyRan = true;
                })
                .timeout(
                  _completionLimit,
                  onTimeout: () => fail(
                    'The transaction kept waiting past its retry budget.',
                  ),
                ),
            throwsA(
              anyOf(
                isA<PostgresRetryDeadlineExceededException>(),
                isA<PostgresSnapshotUnavailableException>(),
                _sqlState('57014'),
                _sqlState('55P03'),
              ),
            ),
          );
          expect(
            clock.elapsed,
            lessThan(_retryBudget + const Duration(milliseconds: 500)),
          );
          expect(bodyRan, isFalse);
          expect(
            sql.statements,
            contains(contains('pg_try_advisory_xact_lock')),
          );
          expect(await _tryOwnerLock(session.writer, _ownerA), isFalse);
        } finally {
          await holder.execute('ROLLBACK');
        }
      },
    );
  });
}

typedef _Run =
    Future<T> Function<T>(
      Set<String> owners,
      String actor,
      Future<T> Function(Object scope) body,
    );
typedef _RunRepeatableRead =
    Future<T> Function<T>(
      String owner,
      String actor,
      Future<T> Function(Object scope) body,
    );

/// Load the new boundary at runtime so its absence is a test assertion.
/// Keep the callable signatures here while the production library is absent.
Future<({_Run run, _RunRepeatableRead runRepeatableRead})> _openOwnerGraph(
  TenturaDb db,
) async {
  final libraryUri = Uri.parse(
    'package:tentura_server/data/repository/owner_graph_unit_of_work.dart',
  );
  final source = await Isolate.resolvePackageUri(libraryUri);
  if (source == null || !File.fromUri(source).existsSync()) {
    fail(
      'OwnerGraphUnitOfWork is missing. Owner-graph transactions are unavailable.',
    );
  }
  final library = await vm.currentMirrorSystem().isolate.loadUri(libraryUri);
  final type = library.declarations[#OwnerGraphUnitOfWork] as vm.ClassMirror?;
  if (type == null) fail('OwnerGraphUnitOfWork must be a class.');
  expect([
    for (final interface in type.superinterfaces) interface.simpleName,
  ], contains(#OwnerGraphTransactionPort));
  final unit = type.newInstance(Symbol.empty, [db]);
  return (
    run: unit.getField(#run).reflectee as _Run,
    runRepeatableRead:
        unit.getField(#runRepeatableRead).reflectee as _RunRepeatableRead,
  );
}

Iterable<String> _scopeOwners(Object scope) =>
    vm.reflect(scope).getField(#ownerIds).reflectee as Iterable<String>;

Future<
  ({
    int pid,
    String transaction,
    String isolation,
    String actor,
    List<String> owners,
  })
>
_readState(TenturaDb db) async {
  final row = await db.customSelect('''
    SELECT pg_backend_pid() AS pid, txid_current()::text AS tx,
      current_setting('transaction_isolation') AS isolation,
      current_setting('tentura.mutating_user_id', true) AS actor,
      current_setting('tentura.owner_scopes', true) AS owners
  ''').getSingle();
  return (
    pid: row.read<int>('pid'),
    transaction: row.read<String>('tx'),
    isolation: row.read<String>('isolation'),
    actor: row.readNullable<String>('actor') ?? '',
    // Compare the IDs regardless of delimiters or array quoting.
    owners: RegExp('[A-Za-z0-9_-]+')
        .allMatches(row.readNullable<String>('owners') ?? '')
        .map((match) => match.group(0)!)
        .toList(),
  );
}

Future<void> _expectScopeCleared(TenturaDb db, int transactionPid) async {
  final next = await db.withConnectionScope(
    () => db.customSelect('''
    SELECT pg_backend_pid() AS pid,
      current_setting('tentura.owner_scopes', true) AS owners
  ''').getSingle(),
  );
  expect(
    next.read<int>('pid'),
    transactionPid,
    reason: 'Inspect the same backend.',
  );
  expect(next.readNullable<String>('owners') ?? '', isEmpty);
}

Future<bool> _tryOwnerLock(Connection observer, String owner) async {
  final rows = await observer.execute(
    Sql.indexed('SELECT pg_try_advisory_xact_lock($_ownerGraphKey)'),
    parameters: [owner],
  );
  return rows.single.single! as bool;
}

Future<List<({int pid, bool granted})>> _ownerLocks(
  Connection observer,
  String owner,
) async {
  final rows = await observer.execute(
    Sql.indexed('''
      WITH scope AS (SELECT $_ownerGraphKey AS key)
      SELECT pid, granted FROM pg_locks, scope
      WHERE locktype = 'advisory' AND objsubid = 1
        AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
        AND classid::bigint = ((key >> 32) & 4294967295)
        AND objid::bigint = (key & 4294967295)
    '''),
    parameters: [owner],
  );
  return [
    for (final row in rows) (pid: row[0]! as int, granted: row[1]! as bool),
  ];
}

Future<int> _waitForOwnerLock(
  Connection observer,
  String owner, {
  required bool Function() isFinished,
}) async {
  final clock = Stopwatch()..start();
  while (!isFinished() && clock.elapsed < _retryBudget) {
    final pending = (await _ownerLocks(
      observer,
      owner,
    )).where((lock) => !lock.granted).firstOrNull;
    if (pending != null) return pending.pid;
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
  fail('No transaction waited for owner $owner while the lock was held.');
}

Future<void> _raiseSqlState(TenturaDb db, String code) => db.customStatement(
  "DO \$\$ BEGIN RAISE EXCEPTION USING ERRCODE = '$code'; END \$\$",
);

Matcher _sqlState(String code) =>
    isA<ServerException>().having((error) => error.code, 'SQLSTATE', code);

final class _SqlLog extends QueryInterceptor {
  final statements = <String>[];
  int begins = 0;
  int rollbacks = 0;

  void _record(String statement) =>
      statements.add(statement.trimLeft().toLowerCase());

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    begins++;
    return super.beginTransaction(parent);
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) {
    rollbacks++;
    return super.rollbackTransaction(inner);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement);
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement);
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement);
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<void> runBatched(QueryExecutor executor, BatchedStatements batch) {
    for (final execution in batch.arguments) {
      _record(batch.statements[execution.statementIndex]);
    }
    return super.runBatched(executor, batch);
  }
}
