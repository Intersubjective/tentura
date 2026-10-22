@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

const _actor = 'Uguardsactor1';

/// Entry guards of the scoped main database (#278, #280) on a real pool, with
/// one connection (every scope re-entry would deadlock) and with two (a
/// re-entry could silently take a spare connection instead).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TRANSACTION_GUARDS_TEST_DB',
    defaultNamePrefix: 'tentura_test_tx_guards',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  setUpAll(() async {
    // Two handles over one pool is the production shape here.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    session = await setUpDisposablePgWriter(target: target);
    await session.writer.execute('''
      CREATE TABLE public.tx_guard_probe (label text PRIMARY KEY)
    ''');
  });
  setUp(() => session.writer.execute('TRUNCATE public.tx_guard_probe'));
  tearDownAll(() => tearDownDisposablePgWriter(session: session));

  for (final connections in [1, 2]) {
    group(
      'with $connections pooled connection(s)',
      () => _guards(target, () => session, connections),
    );
  }
}

void _guards(
  DisposablePgTarget target,
  DisposablePgWriterSession Function() session,
  int connections,
) {
  late _Harness harness;
  setUp(() => harness = _Harness(target.databaseEnv, connections));
  tearDown(() => harness.close());

  Future<List<String>> labels() async => [
    for (final row in await session().writer.execute(
      'SELECT label FROM public.tx_guard_probe ORDER BY label',
    ))
      row.single! as String,
  ];

  group('TenturaDb.batch (#278)', () {
    test('fails fast outside a scope without leasing a connection', () async {
      var callbackInvoked = false;
      await expectLater(
        harness.db.batch((batch) {
          callbackInvoked = true;
          batch.customStatement('SELECT 1');
        }),
        throwsA(_forbiddenBatch),
      );
      expect(callbackInvoked, isFalse);
      expect(harness.leases, 0, reason: 'No connection may be leased.');
      expect(harness.events, isEmpty);
    });

    test(
      'fails fast inside an open transaction, which still commits',
      () async {
        await harness.db.withTransaction(() async {
          await harness.insert('before');
          final events = harness.events.length;
          await expectLater(
            harness.sibling.batch(
              (batch) => batch.customStatement('SELECT 1'),
            ),
            throwsA(_forbiddenBatch),
          );
          await expectLater(
            harness.db.batch((batch) => batch.customStatement('SELECT 1')),
            throwsA(_forbiddenBatch),
          );
          expect(
            harness.events.skip(events),
            isEmpty,
            reason: 'A refused batch must not send SQL or open a savepoint.',
          );
          await harness.insert('after');
        });
        expect(harness.leases, 1);
        expect(await labels(), ['after', 'before']);
      },
    );

    // Drift's Batch commits on the executor of the user it started on, so a
    // batch reaching past the TenturaDb override must still not run unleased.
    test(
      'a batch on the unscoped engine is refused before any SQL',
      () async {
        final engine = harness.db.resolvedEngine;
        await expectLater(
          engine.batch(
            (batch) => batch.customStatement(
              r'INSERT INTO public.tx_guard_probe (label) VALUES ($1)',
              ['unscoped'],
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('unscoped pool executor'),
            ),
          ),
        );
        expect(harness.leases, 0);
        expect(await labels(), isEmpty);
      },
    );

    test(
      'a batch on the engine of an open transaction runs pinned to its lease',
      () async {
        late int before;
        late int after;
        await harness.db.withTransaction(() async {
          before = await harness.backendPid();
          await harness.db.resolvedEngine.batch(
            (batch) => batch.customStatement(
              r'INSERT INTO public.tx_guard_probe (label) VALUES ($1)',
              ['pinned'],
            ),
          );
          after = await harness.backendPid();
        });
        expect(after, before);
        expect(harness.leases, 1);
        expect(harness.events, contains('batch'));
        expect(await labels(), ['pinned']);
      },
    );
  });

  group('withMutatingRepeatableRead nesting (#280)', () {
    /// Both the handle that owns the scope and a sibling handle over the
    /// same pool must be refused.
    Future<void> expectRejected(Matcher message) async {
      for (final handle in [harness.db, harness.sibling]) {
        final events = harness.events.length;
        final leases = harness.leases;
        var callbackInvoked = false;
        final sleeps = <Duration>[];
        Object? error;
        try {
          await handle.withMutatingRepeatableRead<void>(
            _actor,
            () async => callbackInvoked = true,
            sleep: (duration) async => sleeps.add(duration),
          );
        } on Object catch (caught) {
          error = caught;
        }
        expect(
          error,
          isA<StateError>().having((e) => e.message, 'message', message),
        );
        expect(
          harness.events.skip(events),
          isEmpty,
          reason: 'Nesting must be refused before any SQL is issued.',
        );
        expect(harness.leases, leases, reason: 'No new connection lease.');
        expect(callbackInvoked, isFalse);
        expect(sleeps, isEmpty);
      }
    }

    final insideTransaction = contains('inside an open transaction');

    final outers = <String, Future<void> Function(Future<void> Function())>{
      'withTransaction': (body) => harness.db.withTransaction(body),
      'withJoinedTransaction': (body) => harness.db.withJoinedTransaction(body),
      'Drift transaction': (body) => harness.db.transaction(body),
      'withReadSnapshot': (body) => harness.db.withReadSnapshot(body),
      'withMutatingUser': (body) => harness.db.withMutatingUser(_actor, body),
      'withMutatingSystem': (body) => harness.db.withMutatingSystem(body),
      'withMutatingRepeatableRead': (body) =>
          harness.db.withMutatingRepeatableRead(_actor, body),
    };

    for (final MapEntry(key: name, value: outer) in outers.entries) {
      test('is refused inside $name, which stays usable', () async {
        final readOnly = name == 'withReadSnapshot';
        await outer(() async {
          if (!readOnly) await harness.insert('before');
          await expectRejected(insideTransaction);
          // The outer transaction was not aborted by a failed statement.
          await harness.db.customSelect('SELECT 1').get();
          if (!readOnly) await harness.insert('after');
        });
        expect(harness.leases, 1);
        expect(await labels(), readOnly ? isEmpty : ['after', 'before']);
      });
    }

    test(
      'is refused inside a leased connection scope, where a retry backoff '
      'would sleep holding the lease',
      () async {
        await harness.db.withConnectionScope(() async {
          await harness.insert('before');
          await expectRejected(contains('connection scope'));
          await harness.insert('after');
        });
        expect(harness.leases, 1);
        expect(await labels(), ['after', 'before']);
      },
    );

    test(
      'is refused inside Drift exclusive and intercepted executors of a scope',
      () async {
        await harness.db.exclusively(() async {
          await expectRejected(contains('connection scope'));
        });
        await harness.db.runWithInterceptor(
          () => expectRejected(contains('connection scope')),
          interceptor: _EventRecorder([]),
        );
      },
    );

    test(
      'is refused inside a transaction on another pool, whose lease a '
      'backoff would hold',
      () async {
        await harness.outsider.withTransaction(
          () => expectRejected(insideTransaction),
        );
        await harness.outsider.withConnectionScope(
          () => expectRejected(contains('connection scope')),
        );
      },
    );

    test('runs outside any scope or transaction', () async {
      final seen = await harness.db.withMutatingRepeatableRead(
        _actor,
        () async {
          await harness.insert('repeatable');
          final row = await harness.db
              .customSelect(
                "SELECT current_setting('transaction_isolation') AS level",
              )
              .getSingle();
          return row.read<String>('level');
        },
      );
      expect(seen, 'repeatable read');
      expect(await labels(), ['repeatable']);
    });
  });
}

final _forbiddenBatch = isA<UnsupportedError>().having(
  (error) => error.message,
  'message',
  contains('TenturaDb.batch() is forbidden'),
);

final class _Harness {
  _Harness(Env postgres, int connections) {
    pool = MainDbPool(
      Env(
        environment: Environment.test,
        printEnv: false,
        isDebugModeOn: false,
        pgHost: postgres.pgHost,
        pgPort: postgres.pgPort,
        pgDatabase: postgres.pgDatabase,
        pgUsername: postgres.pgUsername,
        pgPassword: postgres.pgPassword,
        maxConnectionCount: connections,
      ),
    );
    db = TenturaDb.scoped(pool, scopeInterceptor: _recorder);
    sibling = TenturaDb.scoped(pool, scopeInterceptor: _recorder);
    outsiderPool = MainDbPool(postgres);
    outsider = TenturaDb.scoped(outsiderPool, scopeInterceptor: _recorder);
  }

  late final MainDbPool outsiderPool;

  /// A handle over a different pool (as the auth database has).
  late final TenturaDb outsider;

  late final MainDbPool pool;

  /// The handle whose scope or transaction is open.
  late final TenturaDb db;

  /// Another handle over the same pool, as a second repository would hold.
  late final TenturaDb sibling;

  /// Statements and transaction control calls, in order, on every lease.
  final events = <String>[];

  /// Connection leases taken by either handle.
  int leases = 0;

  QueryInterceptor _recorder() {
    leases++;
    return _EventRecorder(events);
  }

  Future<void> insert(String label) async {
    await db.customStatement(
      r'INSERT INTO public.tx_guard_probe (label) VALUES ($1)',
      [label],
    );
  }

  Future<int> backendPid() async =>
      (await db.customSelect('SELECT pg_backend_pid() AS pid').getSingle())
          .read<int>('pid');

  Future<void> close() async {
    await db.close();
    await sibling.close();
    await outsider.close();
    await pool.close();
    await outsiderPool.close();
  }
}

/// Records every statement and transaction control call on one lease.
final class _EventRecorder extends QueryInterceptor {
  _EventRecorder(this._events);

  final List<String> _events;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    _events.add('begin');
    return super.beginTransaction(parent);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    _events.add('commit');
    return super.commitTransaction(inner);
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) {
    _events.add('rollback');
    return super.rollbackTransaction(inner);
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    _events.add('batch');
    return super.runBatched(executor, statements);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _events.add(statement);
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _events.add(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _events.add(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _events.add(statement);
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _events.add(statement);
    return super.runSelect(executor, statement, args);
  }
}
