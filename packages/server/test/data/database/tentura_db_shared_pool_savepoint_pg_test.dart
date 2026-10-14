@Tags(['pg', 'multi-connection'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

const _actor = 'Usharedpoolsp01';
const _stateSql = '''
SELECT pg_backend_pid() AS pid,
       txid_current()::text AS tx,
       coalesce(current_setting('tentura.mutating_user_id', true), '') AS actor
''';

typedef _State = ({int pid, String tx, String actor});

Future<_State> _state(TenturaDb db) async {
  final row = await db.customSelect(_stateSql).getSingle();
  return (
    pid: row.read<int>('pid'),
    tx: row.read<String>('tx'),
    actor: row.read<String>('actor'),
  );
}

/// DI hands every repository its own [TenturaDb] over one [MainDbPool]. A
/// unit of work opened on one instance, then a nested mutation and a Drift
/// savepoint (as a manager prefetch opens) on another instance, must run on
/// the same leased connection instead of waiting on itself.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SHARED_POOL_SAVEPOINT_TEST_DB',
    defaultNamePrefix: 'tentura_test_shared_pool_sp',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late MainDbPool pool;
  late TenturaDb outerDb;
  late TenturaDb repositoryDb;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
  });
  setUp(() {
    final db = target.databaseEnv;
    pool = MainDbPool(
      Env(
        environment: Environment.test,
        printEnv: false,
        isDebugModeOn: false,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        maxConnectionCount: 2,
      ),
    );
    outerDb = TenturaDb.scoped(pool);
    repositoryDb = TenturaDb.scoped(pool);
  });
  tearDown(() async {
    await outerDb.close();
    await repositoryDb.close();
    await pool.close();
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session));

  test(
    'a savepoint opened by another instance over the same pool reuses the '
    'outer transaction lease',
    () async {
      final states = <_State>[];
      await MutatingUnitOfWork(outerDb).run<void>(
        actorUserId: _actor,
        action: () async {
          states.add(await _state(outerDb));
          await outerDb.customStatement('SELECT 1');
          await repositoryDb.withMutatingUser(_actor, () async {
            states.add(await _state(repositoryDb));
            await repositoryDb.transaction(() async {
              states
                ..add(await _state(repositoryDb))
                ..add(await _state(outerDb));
            });
            await outerDb.transaction(() async {
              states
                ..add(await _state(outerDb))
                ..add(await _state(repositoryDb));
            });
          });
          states.add(await _state(outerDb));
        },
      );
      expect(states, hasLength(7));
      expect(states.toSet(), {states.first});
      expect(states.first.actor, _actor);
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
