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
    envVarName: 'TENTURA_WITNESS_BUMP_MR_EPOCH_TEST_DB',
    defaultNamePrefix: 'tentura_test_witness_bump',
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

  group('WitnessWindowRepository.bumpMrEpoch', () {
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
