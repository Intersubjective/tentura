@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/meritrank_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/forward_band_witness_g3a_pg_cleanup.dart';

const _pgTimeout = Timeout(Duration(minutes: 10));

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_6KOO_FORWARD_BAND_WITNESS_CLEANUP_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_6koo_g3a_cleanup',
  );
  final reachable = await canReachPostgresAdmin(target);

  late Connection writer;
  late TenturaDb database;
  late MeritrankRepository meritRank;

  if (reachable) {
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
      meritRank = MeritrankRepository(database);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  test(
    'setUp teardown clears populated users and beacon on schema >= m0203',
    () async {
      expect(
        reachable,
        isTrue,
        reason:
            'Postgres admin database must be reachable to verify setUp '
            'teardown on schema >= m0203',
      );

      final version = await writer.execute(
        'SELECT max(version) FROM public.schema_version',
      );
      expect(
        (version.single.single! as String).compareTo('0203'),
        greaterThanOrEqualTo(0),
        reason: 'fixture requires disposable DB migrated through m0203',
      );

      await forwardBandG3aSeedPopulatedPreCleanupFixture(database, meritRank);
      expect(
        await forwardBandG3aFixtureUserCount(database),
        forwardBandG3aAllIds.length,
        reason: 'precondition: populated fixture users before teardown',
      );
      expect(
        await forwardBandG3aFixtureBeaconCount(database),
        1,
        reason: 'precondition: fixture beacon row before teardown',
      );

      await forwardBandWitnessG3aIntegrationCleanup(database, meritRank);

      expect(
        await forwardBandG3aFixtureUserCount(database),
        0,
        reason: 'setUp teardown must clear fixture users',
      );
      expect(
        await forwardBandG3aFixtureBeaconCount(database),
        0,
        reason:
            'setUp teardown must DELETE public.beacon fixture row (not only '
            'users/trust)',
      );

      await expectLater(
        forwardBandWitnessG3aIntegrationCleanup(database, meritRank),
        completes,
        reason: 'second teardown after successful clear must succeed',
      );
    },
    timeout: _pgTimeout,
  );
}
