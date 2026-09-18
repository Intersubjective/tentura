@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_MIGRATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_ctm',
  );
  final reachable = await canReachPostgresAdmin(target);
  final Object skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';
  late DisposablePgWriterSession session;

  if (reachable) {
    setUp(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
        lastInclusiveVersion: '0161',
      );
    });

    tearDown(() async {
      await tearDownDisposablePgWriter(session: session);
    });
  }

  test(
    'fresh schema has both functions through 0163a with body checks on',
    () async {
      final connection = session.writer;
      await connection.execute('SET check_function_bodies = true');
      await withDisposablePgLifecycleLock(target.adminEnv, () async {
        await migrateDbSchemaThrough(connection, '0163a');
      });
      expect(
        await _versions(connection),
        containsAll(['0161a', '0162', '0163', '0163a']),
      );
      await _expectFunctions(connection);
      final triggers = await connection.execute('''
SELECT count(*)::int FROM pg_trigger
WHERE tgname = 'vote_user_bump_direct_trust_version'
  AND tgrelid = 'public.vote_user'::regclass
''');
      expect(triggers.single.single, 1);
    },
    skip: skipReason,
  );

  for (final current in ['0162', '0163a', '0168']) {
    test(
      'repairs legacy $current without rewriting its migration stamps',
      () async {
        final connection = session.writer;
        // Reproduce the old registry, including the jump from 0161 to 0163a.
        final legacy = current == '0162'
            ? [m0162]
            : [
                m0163a,
                m0162,
                m0163,
                if (current == '0168') ...[m0164, m0165, m0166, m0167, m0168],
              ];
        await withDisposablePgLifecycleLock(target.adminEnv, () async {
          await migrateDbSchemaFrom(connection, legacy);
        });
        final before = await _versions(connection);
        expect(before.last, current);
        expect(before, isNot(contains('0163')));
        expect(
          (await connection.execute(
            "SELECT to_regprocedure('public.constellation_trust_edges(text,text,text[])') IS NULL",
          )).single.single,
          isTrue,
        );
        if (current != '0162') {
          expect(before, isNot(contains('0162')));
        }

        await connection.execute('SET check_function_bodies = true');
        await withDisposablePgLifecycleLock(target.adminEnv, () async {
          await migrateDbSchema(connection);
        });
        final after = await _versions(connection);
        expect(after.take(before.length), before);
        expect(after.last, migrationsForTesting.last.version);
        if (current != '0162') {
          expect(after, isNot(contains('0162')));
          expect(after, isNot(contains('0163')));
        }
        await _expectFunctions(connection);

        // Reapplying the repair must also work when both functions already exist.
        for (final statement in m0169.statements) {
          await connection.execute(statement);
        }
        await _expectFunctions(connection);
      },
      skip: skipReason,
    );
  }
}

Future<List<String>> _versions(Connection connection) async => [
  for (final row in await connection.execute(
    'SELECT version FROM schema_version ORDER BY version COLLATE "C"',
  ))
    row.single as String,
];

Future<void> _expectFunctions(Connection connection) async {
  final readWall = await connection.execute('''
SELECT pg_get_functiondef('public.beacon_can_read_content(text,text)'::regprocedure)
''');
  expect(
    readWall.single.single,
    contains('person_are_mutually_visible_cached'),
  );
  expect(
    await connection.execute(
      "SELECT * FROM public.constellation_trust_edges('', '', ARRAY[]::text[])",
    ),
    isEmpty,
  );
}
