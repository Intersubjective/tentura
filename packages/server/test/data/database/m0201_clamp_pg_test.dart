@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';

/// P0.1 pg-only: publication failures must stay deferred — rebuild completes
/// without raising even when `mr_put_edge` fails mid-flight.
const _alice = 'Um0201pgalice';
const _bob = 'Um0201pgbob01';
const _allIds = [_alice, _bob];

Future<void> main() async {
  test('migration 0201 is registered in the schema registry', () {
    expect(
      migrationsForTesting.map((m) => m.version),
      contains('0201'),
    );
  });

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0201_CLAMP_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0201_clamp_pg',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
    });

    setUp(() async {
      await _cleanup(database);
      for (final id in _allIds) {
        await _insertUser(database, id);
      }
    });

    tearDown(() async {
      await _cleanup(database);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  test(
    'trust_rebuild_effective_edge defers publish when mr_put_edge fails',
    () async {
      var mrStubbed = false;
      addTearDown(() async {
        if (mrStubbed) {
          await _restorePgmer2AndSchema(writer);
          mrStubbed = false;
        }
      });

      await _applySource(database, _alice, _bob, 'very_good', 2);
      await _rebuild(database, _alice, _bob, epsilonOverride: -1);
      final prevBefore = await _readPrevSent(database, _alice, _bob);
      expect(prevBefore, greaterThan(0));

      await _applySource(database, _alice, _bob, 'very_bad', 3);

      await _stubMrPutEdgeFailure(writer);
      mrStubbed = true;

      final rawWeight = await _rebuild(
        database,
        _alice,
        _bob,
        epsilonOverride: -1,
      );
      expect(rawWeight, lessThan(0));

      expect(
        await _readPrevSent(database, _alice, _bob),
        closeTo(prevBefore, 1e-9),
      );

      await _restorePgmer2AndSchema(writer);
      mrStubbed = false;

      await database.customSelect('SELECT 1').getSingle();
    },
    skip: skipReason,
  );
}

Future<void> _stubMrPutEdgeFailure(Connection writer) async {
  await writer.execute('DROP EXTENSION IF EXISTS pgmer2 CASCADE');
  await writer.execute(r'''
CREATE FUNCTION public.mr_put_edge(
  src text,
  dst text,
  weight double precision,
  context text,
  ticker bigint
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'm0201 induced mr_put_edge failure';
END;
$$;
''');
}

Future<void> _restorePgmer2AndSchema(Connection writer) async {
  await writer.execute('DROP EXTENSION IF EXISTS pgmer2 CASCADE');
  await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
  await migrateDbSchema(writer);
}

Future<void> _applySource(
  TenturaDb db,
  String subject,
  String object,
  String bin,
  double amount,
) async {
  await db.customStatement(
    r'''
SELECT trust_apply_source_evidence('personal', $1, $2, $3, $4)
''',
    [subject, object, bin, amount],
  );
}

Future<double> _rebuild(
  TenturaDb db,
  String subject,
  String object, {
  required double epsilonOverride,
}) async {
  final row = await db
      .customSelect(
        r'SELECT trust_rebuild_effective_edge($1, $2, $3) AS w',
        variables: [
          Variable<String>(subject),
          Variable<String>(object),
          Variable<double>(epsilonOverride),
        ],
      )
      .getSingle();
  return row.read<double>('w');
}

Future<double> _readPrevSent(
  TenturaDb db,
  String subject,
  String object,
) async {
  final row = await db.customSelect(
    r'''
SELECT prev_sent_weight
FROM public.user_trust_edge
WHERE subject = $1 AND object = $2
''',
    variables: [
      Variable<String>(subject),
      Variable<String>(object),
    ],
  ).getSingle();
  return row.read<double>('prev_sent_weight');
}

Future<void> _insertUser(TenturaDb db, String id) => db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

Future<void> _cleanup(TenturaDb db) async {
  final idList = _allIds.map((id) => "'$id'").join(', ');
  await db.customStatement(
    'DELETE FROM public.user_trust_source_edge '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.user_trust_edge '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await db.customStatement(
    '''DELETE FROM public."user" WHERE id IN ($idList)''',
  );
}
