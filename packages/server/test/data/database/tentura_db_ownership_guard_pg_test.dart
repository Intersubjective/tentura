@Tags(['pg'])
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

const _actor = 'Uownershipgrd01';
const _stateSql = '''
SELECT pg_backend_pid() AS pid,
       txid_current()::text AS tx,
       coalesce(current_setting('tentura.mutating_user_id', true), '') AS actor
''';

typedef _State = ({int pid, String tx, String actor});

final class _Rollback implements Exception {}

Future<_State> _state(TenturaDb db) async {
  final row = await db.customSelect(_stateSql).getSingle();
  return (
    pid: row.read<int>('pid'),
    tx: row.read<String>('tx'),
    actor: row.read<String>('actor'),
  );
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_OWNERSHIP_GUARD_TEST_DB',
    defaultNamePrefix: 'tentura_test_ownership_guard',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late MainDbPool pool;
  late TenturaDb outerDb;
  late TenturaDb siblingDb;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
  });
  setUp(() {
    final db = target.databaseEnv;
    pool = MainDbPool(
      Env(
        environment: Environment.test,
        printEnv: false,
        isDebugModeOn: true,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        maxConnectionCount: 2,
      ),
    );
    outerDb = TenturaDb.scoped(pool);
    siblingDb = TenturaDb.scoped(pool);
  });
  tearDown(() async {
    await outerDb.close();
    await siblingDb.close();
    await pool.close();
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session));

  group('statement executor ownership guard', () {
    test(
      'a statement sent to the outer executor while a sibling handle holds '
      'the innermost transaction fails fast naming both executors',
      () async {
        Object? failure;
        await outerDb.withConnectionScope(() async {
          // The bare leased executor, as a stale reference would hold it.
          final stale = outerDb.resolvedEngine;
          await siblingDb.transaction(() async {
            try {
              await stale
                  .customSelect('SELECT 1')
                  .get()
                  .timeout(const Duration(seconds: 2));
            } on Object catch (error) {
              failure = error;
            }
          });
        });
        expect(failure, isA<StateError>());
        expect(
          (failure! as StateError).message,
          allOf(
            contains('innermost'),
            contains('expected'),
            contains('actual'),
          ),
        );
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'statements routed to the innermost executor still run on one backend',
      () async {
        final states = <_State>[];
        await outerDb.withTransaction(() async {
          states.add(await _state(outerDb));
          await siblingDb.transaction(() async {
            states
              ..add(await _state(siblingDb))
              ..add(await _state(outerDb));
          });
          states.add(await _state(siblingDb));
        });
        expect(states.toSet(), hasLength(1));
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  group('lease and admission ownership guard', () {
    test(
      'taking a pool admission slot while the zone holds a connection scope '
      'is rejected',
      () async {
        await outerDb.withConnectionScope(() async {
          await expectLater(
            pool.admission.run(() async => 1),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('admission'),
              ),
            ),
          );
        });
        expect(pool.admission.running, 0);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'a unit of work across two handles holds exactly one admission slot',
      () async {
        var running = -1;
        await MutatingUnitOfWork(outerDb).run<void>(
          actorUserId: _actor,
          action: () async {
            await siblingDb.withMutatingUser(_actor, () async {
              await siblingDb.transaction(() async {
                running = pool.admission.running;
              });
            });
          },
        );
        expect(running, 1);
        expect(pool.admission.running, 0);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  group('cross-handle nested transaction rollback', () {
    Future<void> create() => outerDb.customStatement(
      'CREATE TEMP TABLE IF NOT EXISTS guard_probe (v int)',
    );

    test('a failed nested savepoint rolls back only its own work', () async {
      final seen = <int>[];
      await MutatingUnitOfWork(outerDb).run<void>(
        actorUserId: _actor,
        action: () async {
          await create();
          await outerDb.customStatement('INSERT INTO guard_probe VALUES (1)');
          try {
            await siblingDb.transaction(() async {
              await siblingDb.customStatement(
                'INSERT INTO guard_probe VALUES (2)',
              );
              throw _Rollback();
            });
          } on _Rollback {
            // expected
          }
          final rows = await outerDb
              .customSelect('SELECT v FROM guard_probe ORDER BY v')
              .get();
          seen.addAll(rows.map((r) => r.read<int>('v')));
        },
      );
      expect(seen, [1]);
    });

    test('an outer failure rolls back work done through a sibling', () async {
      await outerDb.customStatement(
        'CREATE TABLE IF NOT EXISTS guard_outer_probe (v int)',
      );
      await expectLater(
        MutatingUnitOfWork(outerDb).run<void>(
          actorUserId: _actor,
          action: () async {
            await siblingDb.transaction(() async {
              await siblingDb.customStatement(
                'INSERT INTO guard_outer_probe VALUES (1)',
              );
            });
            throw _Rollback();
          },
        ),
        throwsA(isA<_Rollback>()),
      );
      final rows = await outerDb
          .customSelect('SELECT count(*)::int AS n FROM guard_outer_probe')
          .getSingle();
      expect(rows.read<int>('n'), 0);
    });
  });
}
