@Tags(['pg'])
library;

import 'dart:async';

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/port/user_availability_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';

const _viewer = 'Unewviewer001';
const _other = 'Unewviewer002';
const _peer = 'Unewpeer00001';
const _untouched = 'Unewpeer00002';
const _unseen = 'Unewpeer00003';

const _acknowledge = r'''
mutation($peerIds: [String!]!) {
  constellationAcknowledgeNew(peerIds: $peerIds)
}
''';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_NEW_PEOPLE_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_new_people_gql',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('New people on the viewer Field', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late GraphQL schema;
    late Env env;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      final db = target.databaseEnv;
      env = Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        publicOrigin: 'http://127.0.0.1:2080',
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
      );
      await configureDependencies(env);
      await getIt.allReady(ignorePendingAsyncCreation: true);
      schema = graphqlSchema;
    });

    tearDownAll(() async {
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    Future<void> addPerson(String id) async {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {'id': id, 'key': '$id-key'},
      );
      for (final viewer in [_viewer, _other]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@viewer, @peer, 1), (@peer, @viewer, 1)
'''),
          parameters: {'viewer': viewer, 'peer': id},
        );
      }
    }

    Future<void> firstSeen(
      String peer,
      String age, {
      String viewer = _viewer,
    }) => writer.execute(
      Sql.named('''
INSERT INTO public.person_field_first_seen (viewer_id, peer_id, first_seen_at)
VALUES (@viewer, @peer, now() - CAST(@age AS interval))
ON CONFLICT (viewer_id, peer_id)
DO UPDATE SET first_seen_at = EXCLUDED.first_seen_at
'''),
      parameters: {'viewer': viewer, 'peer': peer, 'age': age},
    );

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      for (final viewer in [_viewer, _other]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
          parameters: {'id': viewer, 'key': '$viewer-key'},
        );
      }
      await addPerson(_peer);
      await addPerson(_untouched);
      await firstSeen(_peer, '1 day');
      await firstSeen(_untouched, '1 day');
      await firstSeen(_peer, '1 day', viewer: _other);
    });

    Future<Map<String, dynamic>> run(
      String document, {
      Map<String, dynamic> variables = const {},
      String viewer = _viewer,
    }) async =>
        await schema.parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
            )
            as Map<String, dynamic>;

    Future<void> acknowledge(
      List<String> ids, {
      String viewer = _viewer,
    }) async {
      final result = await run(
        _acknowledge,
        variables: {'peerIds': ids},
        viewer: viewer,
      );
      expect(
        result,
        {'constellationAcknowledgeNew': true},
        reason:
            'a successful acknowledgement returns true without GraphQL errors',
      );
    }

    // Calls the actual query resolver, repository, PostgreSQL and wire mapper.
    // This also tests mapping independently of GraphQL selection validation.
    Future<Map<String, dynamic>> field({String viewer = _viewer}) async =>
        await QueryConstellationField().constellationField.resolve!(null, {
              kGlobalInputQueryJwt: JwtEntity(sub: viewer),
              'showClosed': false,
              'participatedOnly': false,
              'projection': 'FULL',
            })
            as Map<String, dynamic>;

    Map<String, dynamic> person(Map<String, dynamic> payload, String id) =>
        (payload['peers'] as List).cast<Map<String, dynamic>>().singleWhere(
          (peer) => peer['id'] == id,
        );

    Future<Map<String, Object?>> stored(String viewer, String peer) async =>
        (await writer.execute(
          Sql.named('''
SELECT first_seen_at::text, acknowledged_at::text
FROM public.person_field_first_seen WHERE viewer_id = @viewer AND peer_id = @peer
'''),
          parameters: {'viewer': viewer, 'peer': peer},
        )).single.toColumnMap();

    test(
      'first-seen storage supports a nullable acknowledgement time',
      () async {
        final columns = await writer.execute('''
SELECT data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'person_field_first_seen'
  AND column_name = 'acknowledged_at'
''');
        expect(
          columns,
          hasLength(1),
          reason: 'migrated storage must retain acknowledgement',
        );
        expect(columns.single.toColumnMap(), {
          'data_type': 'timestamp with time zone',
          'is_nullable': 'YES',
          'column_default': null,
        });
        expect((await stored(_viewer, _peer))['acknowledged_at'], isNull);
      },
    );

    for (final age in ['0 seconds', '6 days 23 hours']) {
      test('an unacknowledged person first seen $age ago is new', () async {
        await firstSeen(_peer, age);
        expect(person(await field(), _peer)['isNew'], isTrue);
      });
    }

    for (final age in ['7 days', '8 days']) {
      test('a person first seen $age ago is no longer new', () async {
        await firstSeen(_peer, age);
        expect(person(await field(), _peer)['isNew'], isFalse);
      });
    }

    test('a backfilled person is never new', () async {
      await writer.execute(
        Sql.named('''
UPDATE public.person_field_first_seen SET first_seen_at = '-infinity'
WHERE viewer_id = @viewer AND peer_id = @peer
'''),
        parameters: {'viewer': _viewer, 'peer': _peer},
      );
      expect(person(await field(), _peer)['isNew'], isFalse);
    });

    test('the GraphQL Field selection exposes a boolean new flag', () async {
      final data = await run('''
query { constellationField { peers { id isNew } } }
''');
      final payload = data['constellationField'] as Map<String, dynamic>;
      expect(person(payload, _peer)['isNew'], isTrue);
    });

    test('a later mutual contact is new on its first Field response', () async {
      await field();
      await addPerson(_unseen);
      final first = await field();
      expect(person(first, _unseen)['isNew'], isTrue);
      expect(person(await field(), _unseen)['isNew'], isTrue);
    });

    // Snapshot the existing storage without selecting the not-yet-added column.
    // These checks must fail on the mutation contract, not a missing SQL column.
    Future<List<String>> firstSeenStorage() async => (await writer.execute('''
SELECT to_jsonb(seen)::text FROM public.person_field_first_seen seen
ORDER BY viewer_id, peer_id
''')).map((row) => row.first! as String).toList();

    test(
      'acknowledgement requires an authenticated viewer and changes no rows on rejection',
      () async {
        final before = await firstSeenStorage();
        await expectLater(
          schema.parseAndExecute(
            _acknowledge,
            variableValues: {
              'peerIds': [_peer],
            },
          ),
          throwsA(isA<UnauthorizedException>()),
        );
        expect(await firstSeenStorage(), before);
      },
    );

    test(
      'acknowledgement requires a peer list and changes no rows when it is missing',
      () async {
        final before = await firstSeenStorage();
        await expectLater(
          run('mutation { constellationAcknowledgeNew }'),
          throwsA(isA<GraphQLException>()),
        );
        expect(await firstSeenStorage(), before);
      },
    );

    test(
      'acknowledging unknown people succeeds without creating or changing first-seen rows',
      () async {
        final before = await firstSeenStorage();
        // This well-formed person id has no user or first-seen row in the fixture.
        // The operation is scoped to existing viewer rows, so it is a safe no-op.
        await acknowledge([_unseen]);
        expect(await firstSeenStorage(), before);
        expect(person(await field(), _peer)['isNew'], isTrue);
      },
    );

    test(
      'acknowledging selected people clears only their new flags after refetch',
      () async {
        await acknowledge([_peer]);
        final payload = await field();
        expect(person(payload, _peer)['isNew'], isFalse);
        expect(person(payload, _untouched)['isNew'], isTrue);
        final row = await stored(_viewer, _peer);
        expect(row['acknowledged_at'], isNotNull);
        final acknowledgedAt = DateTime.parse(
          row['acknowledged_at']! as String,
        );
        expect(
          DateTime.now().toUtc().difference(acknowledgedAt).abs(),
          lessThan(const Duration(minutes: 1)),
        );
      },
    );

    test(
      'repeating acknowledgement preserves its original time and first-seen time',
      () async {
        final before = (await writer.execute(
          Sql.named('''
SELECT first_seen_at::text FROM public.person_field_first_seen
WHERE viewer_id = @viewer AND peer_id = @peer
'''),
          parameters: {'viewer': _viewer, 'peer': _peer},
        )).single.first;
        expect(before, isNotNull);
        await acknowledge([_peer, _peer, _untouched]);
        final first = await stored(_viewer, _peer);
        expect(
          first['first_seen_at'],
          before,
          reason: 'the first acknowledgement must preserve first-seen time',
        );
        expect(first['acknowledged_at'], isNotNull);
        await acknowledge([_peer, _untouched]);
        expect(await stored(_viewer, _peer), first);
        final payload = await field();
        expect(person(payload, _peer)['isNew'], isFalse);
        expect(person(payload, _untouched)['isNew'], isFalse);
      },
    );

    test(
      'acknowledgement cannot clear another viewer flags for the same person',
      () async {
        await acknowledge([_peer], viewer: _other);
        expect(person(await field(viewer: _other), _peer)['isNew'], isFalse);
        expect(person(await field(), _peer)['isNew'], isTrue);
        expect((await stored(_viewer, _peer))['acknowledged_at'], isNull);
        expect((await stored(_other, _peer))['acknowledged_at'], isNotNull);
      },
    );

    test(
      'acknowledgement does not create a first-seen row owned only by another viewer',
      () async {
        await writer.execute(
          Sql.named('''
DELETE FROM public.person_field_first_seen WHERE viewer_id = @viewer AND peer_id = @peer
'''),
          parameters: {'viewer': _other, 'peer': _peer},
        );
        await acknowledge([_peer], viewer: _other);
        final rows = await writer.execute(
          Sql.named('''
SELECT viewer_id, acknowledged_at::text FROM public.person_field_first_seen
WHERE peer_id = @peer ORDER BY viewer_id
'''),
          parameters: {'peer': _peer},
        );
        expect(rows.map((r) => r.toColumnMap()).toList(), [
          {'viewer_id': _viewer, 'acknowledged_at': null},
        ]);
        expect(person(await field(), _peer)['isNew'], isTrue);
      },
    );

    test(
      'new flags are loaded in batches rather than once per person',
      () async {
        final recorder = _SelectRecorder();
        final db = TenturaDb(env, scopeInterceptor: () => recorder);
        addTearDown(db.close);
        final query = QueryConstellationField(
          constellationFieldCase: ConstellationFieldCase(
            ConstellationFieldRepository(
              db,
              DriftUserProfileBatchLookup(
                db,
                getIt<UserAvailabilityRepositoryPort>(),
              ),
            ),
            env: env,
            logger: Logger('new-people-batched-read'),
          ),
        );
        Future<Map<String, dynamic>> read() async =>
            await query.constellationField.resolve!(null, {
                  kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
                  'showClosed': false,
                  'participatedOnly': false,
                  'projection': 'FULL',
                })
                as Map<String, dynamic>;

        await read(); // Warm up connections and visibility before measuring.
        recorder.count = 0;
        final small = await read();
        final smallCount = recorder.count;
        final extraIds = [
          for (var i = 0; i < 20; i++)
            'Unewbatch${i.toString().padLeft(4, '0')}',
        ];
        for (final id in extraIds) {
          await addPerson(id);
          await firstSeen(id, '1 day');
        }
        await read();
        recorder.count = 0;
        final large = await read();
        final largeCount = recorder.count;

        expect(person(small, _peer)['isNew'], isTrue);
        for (final id in extraIds) {
          expect(person(large, id)['isNew'], isTrue, reason: id);
        }
        expect(smallCount, greaterThan(0));
        expect(
          largeCount,
          smallCount,
          reason: 'adding people must not add per-person SELECTs',
        );
      },
    );

    test(
      'a FULL refetch after acknowledgement reads fresh flags once the pending read settles',
      () async {
        final opened = Completer<void>();
        final release = Completer<void>();
        var reads = 0;
        final repository = ConstellationFieldRepository(
          getIt<TenturaDb>(),
          getIt<UserProfileBatchLookup>(),
          snapshotOpenProbe: (db) async {
            reads++;
            if (reads != 1) return;
            // Acquire the real REPEATABLE READ snapshot before the write.
            // The pending FULL and its followers must finish on that snapshot;
            // they must not suppress a fresh FULL after it completes.
            await db
                .customSelect(
                  'SELECT first_seen_at FROM public.person_field_first_seen',
                )
                .get();
            opened.complete();
            await release.future.timeout(const Duration(seconds: 5));
          },
        );
        final query = QueryConstellationField(
          constellationFieldCase: ConstellationFieldCase(
            repository,
            env: env,
            logger: Logger('new-people-refetch-after-acknowledgement'),
          ),
        );
        Future<Map<String, dynamic>> read() async =>
            await query.constellationField.resolve!(null, {
                  kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
                  'showClosed': false,
                  'participatedOnly': false,
                  'projection': 'FULL',
                })
                as Map<String, dynamic>;

        final leader = read();
        final pending = <Future<Map<String, dynamic>>>[leader];
        late List<Map<String, dynamic>> oldPayloads;
        try {
          await opened.future.timeout(const Duration(seconds: 5));
          await acknowledge([_peer]);
          pending.add(read());
        } finally {
          release.complete();
          oldPayloads = await Future.wait(pending);
        }
        expect(
          reads,
          1,
          reason: 'overlapping FULLs share the pending snapshot',
        );
        for (final payload in oldPayloads) {
          expect(person(payload, _peer)['isNew'], isTrue);
        }

        final refreshed = await read();
        expect(
          reads,
          2,
          reason: 'a completed FULL must not gate the post-write refetch',
        );
        expect(person(refreshed, _peer)['isNew'], isFalse);
        expect(person(refreshed, _untouched)['isNew'], isTrue);

        final later = await read();
        expect(reads, 3, reason: 'only pending FULLs may be shared');
        expect(person(later, _peer)['isNew'], isFalse);
      },
    );

    test(
      'overlapping FULL reads share one snapshot and carry the same new flags',
      () async {
        final opened = Completer<void>();
        final release = Completer<void>();
        var reads = 0;
        final repository = ConstellationFieldRepository(
          getIt<TenturaDb>(),
          getIt<UserProfileBatchLookup>(),
          snapshotOpenProbe: (_) async {
            reads++;
            if (!opened.isCompleted) opened.complete();
            await release.future.timeout(const Duration(seconds: 5));
          },
        );
        final query = QueryConstellationField(
          constellationFieldCase: ConstellationFieldCase(
            repository,
            env: env,
            logger: Logger('new-people-shared-read'),
          ),
        );
        final args = <String, dynamic>{
          kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
          'showClosed': false,
          'participatedOnly': false,
          'projection': 'FULL',
        };
        final first = Future<dynamic>.sync(
          () => query.constellationField.resolve!(null, args),
        );
        await opened.future.timeout(const Duration(seconds: 5));
        final second = Future<dynamic>.sync(
          () => query.constellationField.resolve!(null, args),
        );
        release.complete();
        final payloads = await Future.wait([first, second]);
        expect(reads, 1);
        for (final payload in payloads) {
          expect(
            person(payload as Map<String, dynamic>, _peer)['isNew'],
            isTrue,
          );
        }
      },
    );
  });
}

/// Counts actual repository SELECTs without inspecting their SQL wording.
final class _SelectRecorder extends QueryInterceptor {
  int count = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    count++;
    return super.runSelect(executor, statement, args);
  }
}
