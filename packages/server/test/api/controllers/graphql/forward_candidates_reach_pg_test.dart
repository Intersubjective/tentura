@Tags(['pg', 'mr'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:get_it/get_it.dart';
import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_forward_candidates.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_user_block.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_candidates_repository.dart';
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/forward_candidates_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/query_counter.dart';

const _viewer = 'Ureach_viewer';
const _a = 'Ureach_a';
const _b = 'Ureach_b';
const _c = 'Ureach_c';
const _d = 'Ureach_d';
const _e = 'Ureach_e';
const _f = 'Ureach_f';
const _request = 'Breach_shared';
const _image = '00000000-0000-4000-8000-000000000440';
const _reachSelection = '''
forward_reach {
  kind via_count
  via { id displayName image { id hash height width } }
  shared_request_id shared_request_title
}
''';

// Real PostgreSQL -> repositories -> use case -> authenticated GraphQL.
// The MR graph is published separately from current explicit trust, as in
// production: withdrawing an edge need not have reached the publisher yet.
// Server-only contract: input devices, viewport and locale are not applicable.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_CANDIDATES_REACH_TEST_DB',
    defaultNamePrefix: 'tentura_test_forward_reach',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late MeritrankRepository mr;
  late GraphQL graphQL;
  late QueryForwardCandidates query;
  late UserBlockRepository blocks;
  late _StatementLog log;

  setUpAll(() async {
    final env = Env(environment: Environment.test);
    GetIt.I.registerSingleton<Env>(env);
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    log = _StatementLog();
    db = TenturaDb.forTest(
      database: PgDatabase.opened(
        Pool<dynamic>.withEndpoints(
          [target.databaseEnv.pgEndpoint],
          settings: target.databaseEnv.pgPoolSettings,
        ),
        enableMigrations: false,
      ).interceptWith(log),
    );
    mr = MeritrankRepository(db);
    final profiles = DriftUserProfileBatchLookup(
      db,
      UserAvailabilityRepository(db),
    );
    query = QueryForwardCandidates(
      forwardCandidatesCase: ForwardCandidatesCase(
        ForwardCandidatesRepository(db),
        profiles,
        PersonVisibilityRepository(db),
        env: env,
        logger: Logger('ForwardCandidatesReachTest'),
      ),
    );
    blocks = UserBlockRepository(env, db);
    graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.addAll(query.all)
          ..fields.addAll(
            QueryUserBlock(
              blockRepository: blocks,
              profileLookup: profiles,
            ).all,
          ),
      ),
    );
  });

  tearDownAll(() async {
    await mr.reset();
    await tearDownDisposablePgWriter(session: session, drift: db);
    await GetIt.I.reset();
  });

  Future<void> user(
    String id,
    int index, {
    String keyNamespace = 'forward-reach',
  }) => session.writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
    parameters: {
      'id': id,
      // Deliberately opposite to the viewer's trust order.
      'name': id == _a
          ? 'Zara'
          : id == _b
          ? 'Ada'
          : 'Name $id',
      'key': pgTestPublicKey(keyNamespace, index),
    },
  );

  Future<void> edge(String from, String to, double weight) async {
    await session.writer.execute(
      Sql.named('''
INSERT INTO public.user_trust_edge (subject, object, trust_w, target_w)
VALUES (@from, @to, @weight, @weight)
'''),
      parameters: {'from': from, 'to': to, 'weight': weight},
    );
    await session.writer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@from, @to, 1)
'''),
      parameters: {'from': from, 'to': to},
    );
  }

  Future<void> sharedRequest(
    String id,
    List<String> peers,
    DateTime activity, {
    int status = 0,
    int kind = 0,
  }) async {
    await session.writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, published_at, created_at, updated_at)
VALUES (@id, @viewer, @title, '', @kind, @status, @activity, @activity, @activity)
'''),
      parameters: {
        'id': id,
        'viewer': _viewer,
        'title': 'Title $id',
        'kind': kind,
        'status': status,
        'activity': activity,
      },
    );
    for (final peer in peers) {
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES (@request, @peer, 1, 3)
'''),
        parameters: {'request': id, 'peer': peer},
      );
    }
  }

  Future<Map<String, dynamic>> execute(String document) async =>
      await graphQL.parseAndExecute(
            document,
            globalVariables: {
              kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
            },
          )
          as Map<String, dynamic>;

  Future<Map<String, Map<String, dynamic>>> candidates({
    bool enriched = true,
  }) async {
    final result = await execute(
      'query { forwardCandidates(context: "") '
      '{ id shares_active_context ${enriched ? _reachSelection : ''} } }',
    );
    expect(result['errors'], isNull);
    final rows = (result['forwardCandidates'] as List)
        .cast<Map<String, dynamic>>();
    return {for (final row in rows) row['id'] as String: row};
  }

  Map<String, dynamic> reach(
    Map<String, Map<String, dynamic>> rows,
    String id,
  ) {
    expect(rows, contains(id));
    expect(
      rows[id],
      containsPair('forward_reach', isA<Map<String, dynamic>>()),
      reason: 'Every suggested recipient must explain why they are listed',
    );
    return rows[id]!['forward_reach'] as Map<String, dynamic>;
  }

  setUp(() async {
    await mr.reset();
    await session.writer.execute('TRUNCATE public."user" CASCADE');
    for (final (i, id) in [_viewer, _a, _b, _c, _d, _e, _f].indexed) {
      await user(id, i + 1);
    }
    for (final (from, to, weight) in [
      (_viewer, _a, 0.9),
      (_viewer, _b, 0.6),
      (_a, _c, 0.2),
      (_b, _c, 0.8),
      (_c, _a, 0.3),
      (_c, _f, 0.5),
      (_f, _viewer, 0.4),
      (_c, _d, 0.3),
      (_d, _viewer, 0.8),
    ]) {
      await edge(from, to, weight);
      await mr.putEdge(nodeA: from, nodeB: to, weight: weight);
    }
    await mr.calculate();
    await sharedRequest(_request, [_e], DateTime.utc(2026, 9, 10));
    await session.writer.execute('''
INSERT INTO public.image (id, author_id, hash, width, height)
VALUES ('$_image', '$_a', 'voucher-image', 64, 48)
''');
    await session.writer.execute(
      'UPDATE public."user" SET image_id = \'$_image\' WHERE id = \'$_a\'',
    );
    // Establish that the fixture works through today's public query before
    // asking for the new field. A missing fixture must never be the RED signal.
    final existing = await candidates(enriched: false);
    expect(existing.keys, containsAll([_a, _b, _c, _d, _e, _f]));
    expect(existing[_e]!['shares_active_context'], isTrue);
  });

  group('Suggested recipient reach explanations', () {
    test(
      'direct trust takes priority over vouchers and a shared Request',
      () async {
        await edge(_b, _a, 0.7);
        await sharedRequest('Breach_direct', [_a], DateTime.utc(2026, 9, 11));
        final rows = await candidates();
        expect(reach(rows, _a)['kind'], 'direct');
        expect(reach(rows, _b)['kind'], 'direct');
      },
    );

    test(
      'two hop reach lists voucher profiles by viewer trust strength',
      () async {
        final explanation = reach(await candidates(), _c);
        expect(explanation['kind'], 'via_connection');
        expect(explanation['via_count'], 2);
        expect(explanation['via'], [
          {
            'id': _a,
            'displayName': 'Zara',
            'image': {
              'id': _image,
              'hash': 'voucher-image',
              'height': 48,
              'width': 64,
            },
          },
          {'id': _b, 'displayName': 'Ada', 'image': null},
        ]);
        expect(explanation['shared_request_id'], isNull);
        expect(explanation['shared_request_title'], isNull);
      },
    );

    test(
      'voucher previews stop at two while the total includes every voucher',
      () async {
        // D already trusts V; adding V -> D makes D a visible direct connection.
        await edge(_viewer, _d, 0.95);
        await edge(_d, _c, 0.1);
        final explanation = reach(await candidates(), _c);
        expect(explanation['kind'], 'via_connection');
        expect(explanation['via_count'], 3);
        expect(
          (explanation['via'] as List).map((v) => (v as Map)['id']),
          [_d, _a],
        );
      },
    );

    test(
      'candidate trust toward a connection does not make that connection a voucher',
      () async {
        // Keep C -> A and the published MR graph; withdraw only A/B -> C.
        await session.writer.execute('''
UPDATE public.user_trust_edge SET trust_w = 0, target_w = 0
WHERE object = '$_c' AND subject IN ('$_a', '$_b')
''');
        final explanation = reach(await candidates(), _c);
        expect(explanation['kind'], 'wider');
        expect(explanation['via'], isEmpty);
        expect(explanation['via_count'], 0);
      },
    );

    test('bond peers name their most recently active readable Request', () async {
      // IDs sort in the opposite order to activity. A newer closed Request
      // must not displace the active shared Request.
      await sharedRequest('Breach_aaa_old', [_e], DateTime.utc(2026, 8, 2));
      await sharedRequest('Breach_zzz_recent', [_e], DateTime.utc(2026, 10, 3));
      await sharedRequest(
        'Breach_closed',
        [_e],
        DateTime.utc(2026, 10, 4),
        status: 1,
      );
      final readable = await session.writer.execute(
        "SELECT public.beacon_can_read_content('Breach_zzz_recent', '$_viewer')",
      );
      expect(readable.single.single, isTrue);
      final explanation = reach(await candidates(), _e);
      expect(explanation['kind'], 'shared_request');
      expect(explanation['via'], isEmpty);
      expect(explanation['via_count'], 0);
      expect(explanation['shared_request_id'], 'Breach_zzz_recent');
      expect(explanation['shared_request_title'], 'Title Breach_zzz_recent');
    });

    test(
      'vouchers take priority over a shared Request and keep its context',
      () async {
        await sharedRequest('Breach_via_shared', [
          _c,
        ], DateTime.utc(2026, 10, 3));
        final explanation = reach(await candidates(), _c);
        expect(explanation['kind'], 'via_connection');
        expect(explanation['via_count'], 2);
        expect(explanation['shared_request_id'], 'Breach_via_shared');
        expect(explanation['shared_request_title'], 'Title Breach_via_shared');
      },
    );

    test('longer paths and incoming trust alone are wider reach', () async {
      final rows = await candidates();
      for (final id in [_d, _f]) {
        final explanation = reach(rows, id);
        expect(explanation['kind'], 'wider');
        expect(explanation['via'], isEmpty);
        expect(explanation['via_count'], 0);
        expect(explanation['shared_request_id'], isNull);
        expect(explanation['shared_request_title'], isNull);
      }
    });

    test(
      'hidden connections are excluded from voucher previews and totals',
      () async {
        await blocks.block(blockerId: _viewer, blockedId: _a, cascadeMode: 0);
        final visible = await candidates(enriched: false);
        expect(visible, isNot(contains(_a)));
        expect(visible, contains(_c));
        final explanation = reach(await candidates(), _c);
        expect(explanation['kind'], 'via_connection');
        expect(explanation['via_count'], 1);
        expect(explanation['via'], [
          {'id': _b, 'displayName': 'Ada', 'image': null},
        ]);
      },
    );

    test(
      'ordinary user sources return null reach even after listing the candidate',
      () async {
        // Read the candidate first so request-scoped metadata cannot leak into
        // later profile lookups using the same repository/schema instances.
        await candidates(enriched: false);
        await blocks.block(blockerId: _viewer, blockedId: _a, cascadeMode: 0);
        final existing = await execute('query { myBlocks { blocked { id } } }');
        expect(existing['myBlocks'] as List, hasLength(1));
        expect(((existing['myBlocks'] as List).single as Map)['blocked'], {
          'id': _a,
        });
        final result = await execute(
          'query { myBlocks { blocked { id $_reachSelection } } }',
        );
        final blocked =
            ((result['myBlocks'] as List).single as Map)['blocked'] as Map;
        expect(blocked['id'], _a);
        expect(blocked, containsPair('forward_reach', isNull));
      },
    );

    test('voucher reads use one batch for the whole candidate list', () async {
      Future<(int, List<String>)> readBatch() async {
        log.reset();
        final rows =
            await query.forwardCandidates.resolve!(null, {
                  kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
                  'context': '',
                })
                as List<Map<String, dynamic>>;
        // The existing candidate query already reads user_trust_edge once.
        // Voucher discovery may join into it or add one bulk statement, but
        // may not issue a separate edge read for each recipient.
        final trustReads = log.selects
            .where(
              (sql) => RegExp(
                r'\buser_trust_edge\b',
                caseSensitive: false,
              ).hasMatch(sql),
            )
            .toList();
        expect(trustReads, isNotEmpty);
        expect(
          trustReads.length,
          lessThanOrEqualTo(2),
          reason: trustReads.join('\n'),
        );
        for (final row in rows) {
          expect(
            row,
            containsPair('forward_reach', isA<Map<String, dynamic>>()),
          );
        }
        return (log.count, trustReads);
      }

      final small = await readBatch();
      for (var i = 0; i < 12; i++) {
        final id = 'Ureach_extra_$i';
        // Key slots are 1-9 per namespace: one namespace per extra user.
        await user(
          id,
          1,
          keyNamespace: 'x${String.fromCharCode(0x61 + i)}',
        );
        await edge(_a, id, 0.5);
        await edge(id, _viewer, 0.5);
        await mr.putEdge(nodeA: _a, nodeB: id, weight: 0.5);
        await mr.putEdge(nodeA: id, nodeB: _viewer, weight: 0.5);
      }
      await mr.calculate();
      final existing = await candidates(enriched: false);
      expect(
        existing.keys,
        containsAll(List.generate(12, (i) => 'Ureach_extra_$i')),
      );
      final large = await readBatch();
      expect(
        large.$1,
        small.$1,
        reason: 'Candidate growth must not add database round trips',
      );
      expect(large.$2.length, small.$2.length);
      final rows = await candidates();
      for (var i = 0; i < 12; i++) {
        final explanation = reach(rows, 'Ureach_extra_$i');
        expect(explanation['kind'], 'via_connection');
        expect(explanation['via_count'], 1);
        expect((explanation['via'] as List).single, containsPair('id', _a));
      }
    });
  });
}

class _StatementLog extends QueryCounter {
  final selects = <String>[];

  @override
  void reset() {
    super.reset();
    selects.clear();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add(statement);
    return super.runSelect(executor, statement, args);
  }
}
