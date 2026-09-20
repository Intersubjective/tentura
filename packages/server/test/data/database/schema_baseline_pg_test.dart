@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// The squashed baseline builds the whole schema in one migration, so nothing
/// else proves that what it creates is actually usable. These assertions come
/// from the retired `constellation_migration_repair_pg_test`, which checked the
/// same objects after the `0161a`/`0169` branch repair converged — the branch is
/// gone, the objects still have to be there and still have to run.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SCHEMA_BASELINE_TEST_DB',
    defaultNamePrefix: 'tentura_test_baseline',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';
  late DisposablePgWriterSession session;

  if (reachable) {
    setUp(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
    });

    tearDown(() async {
      await tearDownDisposablePgWriter(session: session);
    });
  }

  test(
    'a fresh database records the baseline and everything after it',
    () async {
      expect(
        await _versions(session.writer),
        [for (final migration in migrationsForTesting) migration.version],
      );
    },
    skip: skipReason,
  );

  test(
    'the read wall and the trust-edge function are installed and callable',
    () async {
      final connection = session.writer;
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
    },
    skip: skipReason,
  );

  test(
    'the direct-trust version trigger survives the squash',
    () async {
      final triggers = await session.writer.execute('''
SELECT count(*)::int FROM pg_trigger
WHERE tgname = 'vote_user_bump_direct_trust_version'
  AND tgrelid = 'public.vote_user'::regclass
''');
      expect(triggers.single.single, 1);
    },
    skip: skipReason,
  );

  test(
    'the baseline seeds the rows the replaced chain seeded',
    () async {
      final connection = session.writer;
      expect(
        (await connection.execute(
          'SELECT count(*)::int FROM public.mr_publish_epoch',
        )).single.single,
        1,
      );
      expect(
        (await connection.execute(
          'SELECT count(*)::int FROM public.trust_policy',
        )).single.single,
        1,
      );
      expect(
        [
          for (final row in await connection.execute(
            'SELECT trust_context FROM public.trust_context_config '
            'ORDER BY trust_context',
          ))
            row.single! as String,
        ],
        ['commitment', 'forward', 'legacy', 'personal'],
      );
    },
    skip: skipReason,
  );
}

Future<List<String>> _versions(Connection connection) async => [
  for (final row in await connection.execute(
    'SELECT version FROM schema_version ORDER BY version COLLATE "C"',
  ))
    row.single! as String,
];
