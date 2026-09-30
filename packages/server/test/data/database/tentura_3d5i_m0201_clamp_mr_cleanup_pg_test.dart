@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';
import '../../support/m0201_clamp_mr_fixture_teardown.dart';
import '../../support/m0201_clamp_mr_harness.dart';
import '../../support/m0201_clamp_mr_post_m0202_pg.dart';

/// Runtime acceptance for tentura-3d5i: harness cleanup/seed helpers must run
/// on schema ≥ m0202 (no 42P01), clear the same fixture rows as pg clamp, and
/// be safely repeatable.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_3D5I_M0201_CLAMP_MR_CLEANUP_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_3d5i_m0201_mr_cleanup',
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

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  Future<void> requirePostM0202HarnessPreconditions() async {
    await requireSchemaVersionAtOrPastM0202(writer);
    await requireM0202DroppedTrustLedgerObjectsAbsent(writer);
  }

  void expectEmptyFixture(Map<String, int> counts) {
    for (final entry in counts.entries) {
      expect(
        entry.value,
        0,
        reason: 'cleanup must clear fixture ${entry.key} rows',
      );
    }
  }

  test(
    'm0201ClampMrPrepareEmptyPairFixture matches MR setUp on post-m0202',
    () async {
      await requirePostM0202HarnessPreconditions();
      await expectLater(
        m0201ClampMrPrepareEmptyPairFixture(database),
        completes,
        reason:
            'cleanup and user seed helpers must not 42P01 against dropped tables',
      );
      final counts = await m0201ClampMrFixtureTableCounts(database);
      expect(counts['user'], 2);
      expect(counts['trust_evidence'], 0);
      expect(counts['trust_publish_queue'], 0);
    },
    skip: skipReason,
  );

  test(
    'm0201ClampMrSeedDefaultPair writes trust_evidence on post-m0202',
    () async {
      await requirePostM0202HarnessPreconditions();
      await m0201ClampMrInsertUser(database, m0201ClampMrAliceId);
      await m0201ClampMrInsertUser(database, m0201ClampMrBobId);
      await expectLater(m0201ClampMrSeedDefaultPair(database), completes);
      final counts = await m0201ClampMrFixtureTableCounts(database);
      expect(counts['trust_evidence'], greaterThan(0));
      expect(counts['user'], 2);
    },
    skip: skipReason,
  );

  test(
    'm0201ClampMrCleanup clears pg-clamp fixture tables and is repeatable',
    () async {
      await requirePostM0202HarnessPreconditions();
      await m0201ClampMrSeedFullPairFixture(database);
      final before = await m0201ClampMrFixtureTableCounts(database);
      expect(before['trust_evidence'], greaterThan(0));
      expect(before['user_trust_edge'], greaterThanOrEqualTo(0));
      expect(before['trust_publish_queue'], greaterThan(0));
      expect(before['user_block'], 1);
      expect(before['user'], 2);

      await m0201ClampMrCleanup(database);
      expectEmptyFixture(await m0201ClampMrFixtureTableCounts(database));

      await expectLater(
        m0201ClampMrCleanup(database),
        completes,
        reason: 'second cleanup on an empty fixture must succeed',
      );
      expectEmptyFixture(await m0201ClampMrFixtureTableCounts(database));
    },
    skip: skipReason,
  );

  test(
    'm0201ClampMrCleanup matches pg clamp reference teardown on post-m0202',
    () async {
      await requirePostM0202HarnessPreconditions();

      await m0201ClampMrSeedFullPairFixture(database);
      await m0201ClampPgReferenceCleanup(database);
      final referenceEmpty = await m0201ClampMrFixtureTableCounts(database);
      expectEmptyFixture(referenceEmpty);

      await m0201ClampMrSeedFullPairFixture(database);
      final seeded = await m0201ClampMrFixtureTableCounts(database);
      expect(seeded['trust_evidence'], greaterThan(0));
      expect(seeded['trust_publish_queue'], greaterThan(0));

      await m0201ClampMrCleanup(database);
      final afterHarness = await m0201ClampMrFixtureTableCounts(database);
      expect(afterHarness, referenceEmpty);
    },
    skip: skipReason,
  );

  test(
    'MR clamp setUp and tearDown harness cycle completes on post-m0202',
    () async {
      await requirePostM0202HarnessPreconditions();
      await m0201ClampMrPrepareEmptyPairFixture(database);
      await m0201ClampMrSeedDefaultPair(database);
      await m0201ClampMrCleanup(database);
      expectEmptyFixture(await m0201ClampMrFixtureTableCounts(database));
      await expectLater(m0201ClampMrCleanup(database), completes);
    },
    skip: skipReason,
  );
}
