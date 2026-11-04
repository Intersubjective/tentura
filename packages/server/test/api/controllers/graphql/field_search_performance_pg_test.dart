@Tags(['pg'])
@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart' show TenturaDb;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/query_counter.dart';
import '../../../support/session_database_di_harness.dart';

const _viewer = 'Ufsperfview01';

// No substitute resolver or repository: both tests execute the registered
// operation over production DI. Only the database's existing observation hook
// is installed. Fixture SQL uses a separate connection and is never counted.
// The round-trip scaling test carries only pg and runs in server-pg.
// Only the latency test carries perf: measure it explicitly on an idle local
// database, rather than charging concurrent pg shards against a 300 ms target.
// Its JSON output provides numbers for Alloy to copy to bead notes. Tests do
// not modify Alloy task tracking; valid timings cannot exist until search does.
// A missing operation or incorrect result must fail before reporting latency.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FIELD_SEARCH_PERF_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_search_perf',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Postgres unavailable', () {}, skip: unavailable);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late GraphQL schema;
  late QueryCounter counter;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    final pg = target.databaseEnv;
    counter = QueryCounter();
    getIt
      ..skipDoubleRegistration = true
      ..registerFactory<TenturaDb>(
        () => TenturaDb.scoped(
          getIt<MainDbPool>(),
          scopeInterceptor: () => counter,
        ),
      );
    await configureSessionDatabaseTestGraph(
      Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicOrigin: 'http://127.0.0.1:2080',
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: pg.pgHost,
        pgPort: pg.pgPort,
        pgDatabase: pg.pgDatabase,
        pgUsername: pg.pgUsername,
        pgPassword: pg.pgPassword,
        workersCount: 1,
        maxConnectionCount: 1,
        printEnv: false,
        isDebugModeOn: false,
      ),
    );
    schema = graphqlSchema;
    // Prove the observation hook sees real scoped SQL before relying on it.
    final db = getIt<TenturaDb>();
    counter.reset();
    await db.withReadSnapshot(() => db.customSelect('SELECT 1').get());
    expect(counter.count, greaterThan(0));
  });

  tearDownAll(() async {
    getIt.skipDoubleRegistration = false;
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  });

  String peerId(int i) => 'Ufsperf${i.toString().padLeft(5, '0')}';
  String itemId(String kind, int i) =>
      'Bfsperf$kind${i.toString().padLeft(5, '0')}';

  Future<void> seed(int matchesPerGroup) async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$_viewer', 'Viewer', encode(convert_to(rpad('$_viewer', 32, 'x'), 'UTF8'), 'base64'))
''');
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT 'Ufsperf' || lpad(i::text, 5, '0'), 'Garden person ' || i,
       encode(convert_to(rpad('Ufsperf' || lpad(i::text, 5, '0'), 32, 'x'), 'UTF8'), 'base64')
FROM generate_series(1, @size::int) i
'''),
      parameters: {'size': matchesPerGroup},
    );
    await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount)
SELECT '$_viewer', id, 1 FROM public."user" WHERE id <> '$_viewer'
UNION ALL
SELECT id, '$_viewer', 1 FROM public."user" WHERE id <> '$_viewer'
''');
    // One eligible Request and Post per peer, plus equally many unreadable
    // candidates with matching text. Wrong read filtering cannot look fast.
    for (final kind in ['r', 'x', 'p', 'q']) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at, expires_at)
SELECT 'Bfsperf' || @kind || lpad(i::text, 5, '0'),
       'Ufsperf' || lpad(i::text, 5, '0'),
       CASE WHEN @kind IN ('r', 'x') THEN 'Garden Request ' || i ELSE '' END,
       '', 0, CASE WHEN @kind IN ('r', 'x') THEN 0 ELSE 1 END,
       @kind = 'r', now() - interval '1 hour',
       CASE WHEN @kind IN ('p', 'q') THEN now() + interval '1 day' END
FROM generate_series(1, @size::int) i
'''),
        parameters: {'size': matchesPerGroup, 'kind': kind},
      );
    }
    await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
SELECT 'M' || id, id, user_id, 'Garden Post ' || id
FROM public.beacon WHERE kind = 1
''');
    await writer.execute('''
UPDATE public.beacon SET post_root_message_id = 'M' || id WHERE kind = 1
''');
    await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, status, room_access)
SELECT id, '$_viewer', 6, 0, 3 FROM public.beacon WHERE id LIKE 'Bfsperfp%'
''');
    await writer.execute('ANALYZE');
    // Check the positive/negative read-wall fixtures before the new API.
    final readable = await writer.execute(
      Sql.named('''
SELECT public.beacon_can_read_content(@request, @viewer),
       public.beacon_can_read_content(@private, @viewer),
       public.beacon_can_read_content(@admitted, @viewer),
       public.beacon_can_read_content(@unadmitted, @viewer)
'''),
      parameters: {
        'viewer': _viewer,
        'request': itemId('r', 1),
        'private': itemId('x', 1),
        'admitted': itemId('p', 1),
        'unadmitted': itemId('q', 1),
      },
    );
    expect(readable.single.toList(), [true, false, true, false]);
  }

  Future<({int statements, double milliseconds})> search(int population) async {
    counter.reset();
    final watch = Stopwatch()..start();
    final response = await schema.parseAndExecute(
      r'''
query FieldSearch($query: String!, $context: String!) {
  fieldSearch(query: $query, context: $context) {
    people { id }
    requests { id status hidden }
    posts { id status hidden expiresAt }
  }
}
''',
      variableValues: {'query': 'garden', 'context': ''},
      globalVariables: {kGlobalInputQueryJwt: const JwtEntity(sub: _viewer)},
    );
    watch.stop();
    final statementCount = counter.count;
    expect(response, isA<Map<String, dynamic>>());
    final payload = (response as Map<String, dynamic>)['fieldSearch'];
    expect(
      payload,
      isA<Map<String, dynamic>>(),
      reason:
          'A real Field search payload is required before measuring performance',
    );
    final result = payload as Map<String, dynamic>;
    final count = population < 20 ? population : 20;
    for (final (group, allowedIds) in [
      ('people', {for (var i = 1; i <= population; i++) peerId(i)}),
      ('requests', {for (var i = 1; i <= population; i++) itemId('r', i)}),
      ('posts', {for (var i = 1; i <= population; i++) itemId('p', i)}),
    ]) {
      expect(result[group], isA<List<Object?>>());
      final ids = (result[group] as List)
          .map((row) => (row as Map)['id'])
          .toList();
      expect(
        ids,
        hasLength(count),
        reason: '$group must contain real readable matches',
      );
      expect(ids.toSet(), hasLength(count));
      expect(
        ids,
        everyElement(isIn(allowedIds)),
        reason: 'Unreadable matches must not be returned',
      );
    }
    return (
      statements: statementCount,
      milliseconds: watch.elapsedMicroseconds / 1000,
    );
  }

  test(
    'Field search database round trips stay constant as matching results grow',
    () async {
      final coldCounts = <int>[];
      final warmCounts = <int>[];
      for (final size in [1, 20]) {
        await seed(size);
        coldCounts.add((await search(size)).statements);
        warmCounts.add((await search(size)).statements);
      }
      expect(
        coldCounts.first,
        greaterThan(0),
        reason:
            'The real search must use the observed database for these newly seeded matches',
      );
      for (final counts in [coldCounts, warmCounts]) {
        expect(
          counts.last,
          lessThanOrEqualTo(counts.first),
          reason:
              'Returning 20 people, Requests and Posts must not add per-row database round trips, on either cold or warm reads',
        );
      }
      print(
        jsonEncode({
          'benchmark': 'fieldSearch round trips',
          'populations': [1, 20],
          'coldStatements': coldCounts,
          'warmStatements': warmCounts,
        }),
      );
    },
  );

  test(
    'Field search p95 stays below 300 milliseconds on a populated local database',
    () async {
      const population = 1000;
      const samples = 100;
      await seed(population);
      for (var i = 0; i < 5; i++) {
        await search(population);
      }
      final measurements = <double>[];
      final statementCounts = <int>[];
      for (var i = 0; i < samples; i++) {
        final sample = await search(population);
        measurements.add(sample.milliseconds);
        statementCounts.add(sample.statements);
      }
      measurements.sort();
      final p95 = measurements[(samples * .95).ceil() - 1];
      // Retain all samples and the measurement boundary in the test log, ready
      // for Alloy's bead notes. No metrics are emitted for an absent/no-op API.
      print(
        jsonEncode({
          'benchmark': 'fieldSearch',
          'host': Platform.localHostname,
          'database': target.databaseName,
          'unit': 'ms',
          'boundary': 'registered GraphQL parseAndExecute',
          'people': population,
          'requests': population * 2,
          'posts': population * 2,
          'warmups': 5,
          'samples': samples,
          'p95': p95,
          'latencySamples': measurements,
          'statementCounts': statementCounts,
        }),
      );
      expect(
        p95,
        lessThan(300),
        reason: 'Local Field search p95 target is below 300 ms',
      );
    },
    tags: ['perf'],
  );
}
