// `perf` suites are timing-sensitive, so like `mr` suites they run serialised
// (`-j 1`) and outside the default and plain-`pg` runs.
@Tags(['perf', 'pg', 'mr'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';

import '../support/disposable_pg_target.dart';
import '../support/meritrank_lock_probe.dart';

/// Warm FULL read of the heaviest synthetic viewer (V ≈ 1,000) on
/// `tentura_perfsynth`, with the cross-request visible-set cache in place:
/// once the viewer's set is stored, a FULL read makes no MeritRank RPC
/// (`mr_rpc_attempts()` delta) and its p95 is within the FULL p95 budget of
/// ARCH §7.6.
///
/// What is timed is the production FULL path of the constellation use case
/// with the real profile hydration (`DriftUserProfileBatchLookup`), encoded to
/// the wire map and JSON like the GraphQL response: ARCH §7.6 measures from
/// request admission through response encoding, so the cache is gated on the
/// whole read, not on the visible-set step alone.
///
/// The suite loads the dataset's graph into MeritRank (`meritrank_init()`) when
/// MeritRank is empty, and applies the server's own migrations to it first, as
/// starting the server against it (`scripts/perf/run_server_db.sh`) would. The
/// viewer is the dataset's heaviest: the user with the most outgoing trust
/// edges (the dataset's `U66728b9dba8d` today), unless
/// `TENTURA_VISIBLE_SET_CACHE_PERF_VIEWER` names another.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_VISIBLE_SET_CACHE_PERF_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_vis_cache_perf',
  );
  final skipReason = await canReachPostgresAdmin(target)
      ? null
      : 'Postgres admin database not reachable for visible-set cache perf suite';

  const datasetDb = 'tentura_perfsynth';
  const warmups = 3;
  const measuredReads = 30;
  // ARCH §7.6 "Initial target budgets", FULL row, p95. The calibrated U41 gate
  // for the dense dataset is tighter (250 ms, journal "Calibrated frozen
  // budgets"); the acceptance criterion names the §7.6 figure.
  const archFullP95Budget = Duration(milliseconds: 300);

  group('warm FULL read with the visible-set cache on tentura_perfsynth', () {
    late Connection connection;
    late TenturaDb db;
    late ConstellationFieldCase fieldCase;
    late Connection probe;
    late String viewerId;
    var cacheTableExists = false;
    late List<String> uncachedVisibleSet;
    Connection? suiteLock;
    final latencies = <Duration>[];
    final rpcDeltas = <int>[];

    Future<void> fullRead() async {
      final snapshot = await fieldCase.readSnapshot(
        viewerId: viewerId,
        context: '',
        params: (
          filters: ConstellationFieldMembershipFilters.defaults,
          projection: ConstellationProjection.full,
        ),
      );
      // The GraphQL layer serialises timestamps as ISO-8601 strings.
      jsonEncode(
        constellationFieldToGqlMap(snapshot),
        toEncodable: (o) => o is DateTime ? o.toIso8601String() : o,
      );
    }

    setUpAll(() async {
      if (skipReason != null) return;
      // MeritRank is shared by every `mr` suite and holds one graph at a time.
      suiteLock = await holdMeritRankSuiteLock(target);
      final datasetEnv = Env(
        environment: Environment.test,
        pgHost: target.databaseEnv.pgHost,
        pgPort: target.databaseEnv.pgPort,
        pgDatabase: datasetDb,
        pgUsername: target.databaseEnv.pgUsername,
        pgPassword: target.databaseEnv.pgPassword,
        printEnv: false,
        isDebugModeOn: false,
      );
      probe = await Connection.open(
        datasetEnv.pgEndpoint,
        settings: datasetEnv.pgEndpointSettings,
      );
      await migrateDbSchema(probe);
      // One connection, like a production worker: `mr_rpc_attempts()` counts
      // per backend, so every read below runs on the connection it is read on.
      connection = await Connection.open(
        datasetEnv.pgEndpoint,
        settings: datasetEnv.pgEndpointSettings,
      );
      db = TenturaDb.forTest(
        database: PgDatabase.opened(connection, enableMigrations: false),
      );
      fieldCase = ConstellationFieldCase(
        ConstellationFieldRepository(
          db,
          DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
        ),
        env: Env(environment: Environment.test),
        logger: Logger('VisibleSetCachePerf'),
      );

      // Without the table the reads below still run, uncached, so each test
      // fails on what it asserts and not on an unset field.
      cacheTableExists =
          (await probe.execute(
            "SELECT to_regclass('public.person_visible_set_cache') "
            'IS NOT NULL',
          )).single.single ==
          true;
      Future<int> edgeCount() async =>
          (await probe.execute(
                'SELECT count(*)::int FROM mr_edgelist()',
              )).single.single!
              as int;
      if (await edgeCount() == 0) {
        await probe.execute('SELECT meritrank_init()');
      }
      if (await edgeCount() == 0) {
        throw StateError('$datasetDb has no MeritRank graph to read from');
      }

      viewerId =
          Platform.environment['TENTURA_VISIBLE_SET_CACHE_PERF_VIEWER'] ??
          (await probe.execute(
                'SELECT subject FROM public.user_trust_edge '
                'GROUP BY subject ORDER BY count(*) DESC, subject LIMIT 1',
              )).single.single!
              as String;
      // The visible set without the cache, to compare the stored one with.
      uncachedVisibleSet =
          ((await probe.execute(
                    Sql.named(
                      'SELECT coalesce(array_agg(s.peer_id '
                      "ORDER BY s.peer_id), '{}'::text[]) "
                      'FROM public.person_visible_peers_symmetric(@v, @c) s',
                    ),
                    parameters: {'v': viewerId, 'c': ''},
                  )).single.single!
                  as List)
              .cast<String>();

      // Cold start for the viewer, then the reads that fill the cache.
      if (cacheTableExists) {
        await probe.execute(
          Sql.named(
            'DELETE FROM public.person_visible_set_cache WHERE viewer_id = @v',
          ),
          parameters: {'v': viewerId},
        );
      }
      for (var i = 0; i < warmups; i++) {
        await fullRead();
      }
      for (var i = 0; i < measuredReads; i++) {
        final rpcBefore = await db.mrRpcAttempts();
        final clock = Stopwatch()..start();
        await fullRead();
        clock.stop();
        rpcDeltas.add(await db.mrRpcAttempts() - rpcBefore);
        latencies.add(clock.elapsed);
      }
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await db.close();
      if (connection.isOpen) await connection.close();
      await probe.close();
      await suiteLock?.close();
    });

    test('the visible-set cache table exists on the dataset', () async {
      final rows = await probe.execute(
        "SELECT to_regclass('public.person_visible_set_cache') IS NOT NULL",
      );
      expect(rows.single.single, isTrue);
    }, skip: skipReason);

    test('the viewer is heavy enough for the gate to mean something', () {
      expect(uncachedVisibleSet, isNotEmpty);
    }, skip: skipReason);

    // ARCH §7.4a: the payload column is `peer_ids text[]`.
    test("the viewer's stored visible set equals the uncached one", () async {
      expect(cacheTableExists, isTrue, reason: 'no cache table to read');
      final rows = await probe.execute(
        Sql.named(
          'SELECT peer_ids FROM public.person_visible_set_cache '
          "WHERE viewer_id = @v AND ctx = ''",
        ),
        parameters: {'v': viewerId},
      );
      expect(rows, hasLength(1));
      expect(
        ((rows.single.single! as List).cast<String>())..sort(),
        uncachedVisibleSet,
      );
    }, skip: skipReason);

    test('a warm FULL read makes no MeritRank RPC', () {
      expect(rpcDeltas, hasLength(measuredReads));
      expect(rpcDeltas.where((d) => d != 0), isEmpty);
    }, skip: skipReason);

    test('warm FULL p95 is within the FULL budget', () {
      expect(latencies, hasLength(measuredReads));
      final sorted = [...latencies]..sort();
      // Nearest-rank p95.
      final p95 = sorted[(sorted.length * 0.95).ceil() - 1];
      expect(
        p95,
        lessThanOrEqualTo(archFullP95Budget),
        reason: 'p95 ${p95.inMilliseconds} ms over $measuredReads warm reads',
      );
    }, skip: skipReason);
  });
}
