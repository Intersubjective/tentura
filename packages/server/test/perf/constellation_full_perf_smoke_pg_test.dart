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
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';

import '../support/constellation_profiles_from_public_records.dart';
import '../support/disposable_pg_target.dart';
import 'perf_fixtures.dart';
import 'perf_recorder.dart';

/// Smallest end-to-end proof of the perf harness: today's FULL constellation
/// read on a 100-user sparse-trust fixture, recorded and written to
/// `build/perf/<fixture>.json`.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERF_SMOKE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_perf_smoke',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for perf smoke test';

  const measuredAttempts = 20;
  const fixtureSpec = PerfFixture.sparseTrust(visibleUsers: 100);
  final reportName = '${fixtureSpec.name}_full';

  group('FULL constellation read recorded on a 100-user sparse fixture', () {
    late DisposablePgWriterSession session;
    late PerfDbMeter meter;
    late String lastPayload;
    late TenturaDb db;
    late PerfFixtureSeed seed;
    late Map<String, Object?> json;
    late File outputFile;
    late int explainedRowCountAfter;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      meter = PerfDbMeter();
      db = TenturaDb.forTest(
        database: PgDatabase.opened(
          meter.instrument(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
          ),
          enableMigrations: false,
        ).interceptWith(meter),
      );

      seed = await fixtureSpec.seed(session.writer);
      await requireNonEmptyMeritRankGraph(session.writer);

      // The production FULL path: use case, GraphQL mapping, wire encoding.
      final fieldCase = ConstellationFieldCase(
        ConstellationFieldRepository(db, _EmptyProfileLookup()),
        env: Env(environment: Environment.test),
        logger: Logger('ConstellationFullPerfSmoke'),
      );
      final recorder = PerfRecorder(
        fixture: reportName,
        parameters: {
          'visibleUsers': fixtureSpec.visibleUsers,
          'trust': 'sparse',
          'projection': 'full',
        },
        db: db,
        meter: meter,
        probeConnection: session.writer,
      );

      Future<String> encodedFull(PerfAttemptScope scope) async {
        final snapshot = await scope.execution(
          () => fieldCase.readSnapshot(
            viewerId: seed.viewerId,
            context: '',
            params: (
              filters: ConstellationFieldMembershipFilters.defaults,
              projection: ConstellationProjection.full,
            ),
          ),
        );
        return lastPayload = jsonEncode(constellationFieldToGqlMap(snapshot));
      }

      // One cold attempt and the warm repetitions behind the percentiles.
      for (var i = 0; i < 1 + measuredAttempts; i++) {
        await recorder.attempt(encodedFull);
      }
      // A write attempt, so the WAL figure is shown to come from Postgres.
      await recorder.attempt(
        (_) => db.customStatement(
          "UPDATE public.\"user\" SET display_name = 'perf-wal-attempt'",
        ),
      );
      // A failed attempt is part of the latency distribution too.
      await expectLater(
        recorder.attempt<void>((_) async => throw StateError('injected')),
        throwsStateError,
      );

      await recorder.captureExplain(
        label: 'user_count',
        sql: 'SELECT count(*) FROM public."user"',
      );
      await recorder.captureExplain(
        label: 'user_touch',
        sql: "UPDATE public.\"user\" SET display_name = 'perf-touched'",
        mutating: true,
      );
      explainedRowCountAfter =
          (await session.writer.execute(
                'SELECT count(*)::int FROM public."user" '
                "WHERE display_name = 'perf-touched'",
              )).first.first!
              as int;

      outputFile = await recorder.writeReport();
      json =
          jsonDecode(await outputFile.readAsString()) as Map<String, Object?>;
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });

    test('the fixture really has 100 visible users and a loaded MeritRank '
        'graph', () async {
      final peers = await ConstellationFieldRepository(
        db,
        _EmptyProfileLookup(),
      ).visibleGraphPeerIds(viewerId: seed.viewerId, context: '', cap: 1000);

      expect(peers.ids.length, inInclusiveRange(99, 101));
    }, skip: skipReason);

    test('writes build/perf/<fixture>.json', () {
      expect(outputFile.path, 'build/perf/$reportName.json');
      expect(outputFile.existsSync(), isTrue);
      expect(json['fixture'], reportName);
      expect(json['parameters'], containsPair('visibleUsers', 100));
    }, skip: skipReason);

    test('counts every attempt, the failed one included', () {
      final attempts = json['attempts']! as Map<String, Object?>;

      // Cold + warm FULL reads, one write attempt and one injected failure.
      expect(attempts['total'], 1 + measuredAttempts + 1 + 1);
      expect(attempts['failed'], 1);
      expect(attempts['succeeded'], 1 + measuredAttempts + 1);
    }, skip: skipReason);

    test('records p50 and p95 for latency and, separately, execution', () {
      for (final key in ['latencyMs', 'executionMs']) {
        final section = json[key]! as Map<String, Object?>;
        expect(section['p50'], isA<num>(), reason: key);
        expect(section['p95'], isA<num>(), reason: key);
        expect(
          section['p95']! as num,
          greaterThanOrEqualTo(section['p50']! as num),
        );
      }
      final latency = json['latencyMs']! as Map<String, Object?>;
      final execution = json['executionMs']! as Map<String, Object?>;
      expect(execution['p50']! as num, greaterThan(0));
      // Latency also spans the use case, GraphQL mapping and JSON encoding
      // around the repository read that `execution` times.
      expect(latency['p50']! as num, greaterThan(execution['p50']! as num));
    }, skip: skipReason);

    test('the recorded FULL response is the real wire payload', () {
      final payload = jsonDecode(lastPayload) as Map<String, Object?>;

      expect((payload['peers']! as List).length, inInclusiveRange(99, 101));
      expect(payload, contains('anchorProjection'));
    }, skip: skipReason);

    test('records query count, connector RPCs, retries and WAL bytes', () {
      for (final key in [
        'queryCount',
        'connectorRpcs',
        'retryCount',
        'walBytes',
      ]) {
        final section = json[key]! as Map<String, Object?>;
        expect(section['total'], isA<int>(), reason: key);
        expect(section['p50'], isA<num>(), reason: key);
        expect(section['p95'], isA<num>(), reason: key);
      }
      final queries = json['queryCount']! as Map<String, Object?>;
      // Every FULL read and the write attempt ran at least one statement; the
      // injected failure ran none.
      expect(
        queries['total']! as int,
        greaterThanOrEqualTo(1 + measuredAttempts + 1),
      );
      expect(queries['p50']! as num, greaterThanOrEqualTo(1));
      expect(json['walAttribution'], anyOf('quiet-cluster', 'cluster-total'));
    }, skip: skipReason);

    test('reads the connector RPC count, WAL bytes and transaction age from '
        'the database rather than reporting constants', () {
      // FULL's visibility reads go through MeritRank; the write attempt
      // generates WAL for the 100 touched users; FULL runs in a transaction.
      expect((json['connectorRpcs']! as Map)['total'] as int, greaterThan(0));
      expect((json['walBytes']! as Map)['total'] as int, greaterThan(8 * 1024));
      expect((json['txAgeMs']! as Map)['p95'] as num, greaterThan(0));
    }, skip: skipReason);

    test('lock probes on the disposable database see no waiter in an '
        'uncontended run', () {
      // The probe is scoped to the fixture database, so unrelated sessions
      // elsewhere on the cluster never show up here.
      final waiters = json['lockWaiters']! as Map<String, Object?>;
      expect(waiters['max'], 0);
    }, skip: skipReason);

    test('records cursor wait and hold, connection queue time and tx age', () {
      for (final key in [
        'cursorWaitMs',
        'cursorHoldMs',
        'connectionQueueMs',
        'txAgeMs',
      ]) {
        final section = json[key]! as Map<String, Object?>;
        expect(section['p50'], isA<num>(), reason: key);
        expect(section['p95'], isA<num>(), reason: key);
      }
    }, skip: skipReason);

    test('keeps EXPLAIN (ANALYZE, BUFFERS, WAL) JSON, rolling back the '
        'mutating capture', () async {
      final explain = (json['explain']! as List<Object?>)
          .cast<Map<String, Object?>>();

      expect(explain.map((e) => e['label']), ['user_count', 'user_touch']);
      expect(explain.map((e) => e['rolledBack']), [false, true]);
      for (final capture in explain) {
        final root =
            (capture['plan']! as List<Object?>).single! as Map<String, Object?>;
        expect(root, contains('Planning Time'));
        expect(root, contains('Execution Time'));
        final plan = root['Plan']! as Map<String, Object?>;
        // The BUFFERS and WAL options were really requested.
        expect(plan, contains('Shared Hit Blocks'));
        expect(plan, contains('WAL Records'));
      }
      final touchPlan =
          ((explain.last['plan']! as List<Object?>).single!
                  as Map<String, Object?>)['Plan']!
              as Map<String, Object?>;
      expect(touchPlan['WAL Bytes']! as num, greaterThan(0));
      expect(explainedRowCountAfter, 0);
    }, skip: skipReason);
  });
}

final class _EmptyProfileLookup implements UserProfileBatchLookup {
  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) => constellationProfilesFromRecords(this, ids);

  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async => {};

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async => {
    // A peer without a profile is dropped from the snapshot, so the fixture's
    // users each need one for the payload to carry them.
    for (final id in ids)
      id: UserPublicRecord(
        id: id,
        displayName: id,
        description: '',
        userAvailability: null,
      ),
  };
}
