@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';

import '../../support/disposable_pg_target.dart';

const _ego = 'Ucapb2bego02';
const _peer = 'Ucapb2bp05';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_WITNESS_BUMP_MR_EPOCH_P02_TEST_DB',
    defaultNamePrefix: 'tentura_test_witness_bump_p02',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late WitnessWindowRepository repo;
  late MeritrankRepository meritRank;

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
      repo = WitnessWindowRepository(database);
      meritRank = MeritrankRepository(database);
    });

    setUp(() async {
      await database.customStatement(
        r'DELETE FROM public.ego_witness_window WHERE ego_user_id = $1',
        [_ego],
      );
      await database.customStatement(
        "SELECT mr_put_edge('$_ego', '$_peer', 0::double precision, ''::text, 0)",
      );
      await database.customStatement(
        r'UPDATE public.mr_publish_epoch SET epoch = 0 WHERE id = true',
      );
      await database.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$_ego', 'ego', 'pk-ego', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  group('P0.2 mr_sync barrier (pgmer2 0.8.1)', () {
    test(
      'pgmer2 extension is 0.8.1 (postgres-tentura image pin)',
      () async {
        final row = await writer.execute(r'''
SELECT extversion
FROM pg_extension
WHERE extname = 'pgmer2'
''');
        expect(row, hasLength(1));
        expect(row.single[0], '0.8.1');
        await writer.execute('SELECT public.mr_sync()');
      },
      skip: skipReason,
    );

    test(
      'mr_bump_publish_epoch performs mr_sync before epoch bump',
      () async {
        final row = await writer.execute(r'''
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'mr_bump_publish_epoch'
''');
        final def = row.single[0] as String;
        expect(def, contains('mr_sync'));
        final syncIndex = def.indexOf('mr_sync');
        final epochIndex = def.indexOf('mr_publish_epoch');
        expect(syncIndex, greaterThan(-1));
        expect(epochIndex, greaterThan(syncIndex));
      },
      skip: skipReason,
    );

    test(
      'WitnessWindowRepository.bumpMrEpoch completes after mr_put_edge',
      () async {
        await meritRank.putEdge(
          nodeA: _ego,
          nodeB: _peer,
          weight: 0.75,
        );
        final epochBefore = await _readEpoch(database);
        await expectLater(repo.bumpMrEpoch(), completes);
        final epochAfter = await _readEpoch(database);
        expect(epochAfter, greaterThan(epochBefore));

        final def = await _mrBumpPublishEpochDef(writer);
        expect(
          def,
          contains('mr_sync'),
          reason:
              'epoch bump from Dart must stay aligned with SQL mr_sync barrier',
        );
      },
      skip: skipReason,
    );
  });
}

Future<BigInt> _readEpoch(TenturaDb db) async {
  final row = await db
      .customSelect(
        r'SELECT epoch FROM public.mr_publish_epoch WHERE id = true',
        readsFrom: {},
      )
      .getSingle();
  return row.read<BigInt>('epoch');
}

Future<String> _mrBumpPublishEpochDef(Connection writer) async {
  final row = await writer.execute(r'''
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'mr_bump_publish_epoch'
''');
  return row.single[0] as String;
}
