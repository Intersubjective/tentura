@Tags(['pg'])
library;

import 'package:get_it/get_it.dart';
import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_forward_candidate_context.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_candidate_context_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/forward_candidate_context_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';

const _viewer = 'Uordering_viewer';
const _candidate = 'Uordering_candidate';
const _a = 'Uordering_a';
const _b = 'Uordering_b';
const _prefix = 'Uordering_prefix';
const _secondPrefix = 'Uordering_second_prefix';
const _reverse = 'Uordering_0reverse';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CANDIDATE_PATH_ORDERING_TEST_DB',
    defaultNamePrefix: 'tentura_test_candidate_path_ordering',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late GraphQL graphQL;

  setUpAll(() async {
    final env = Env(environment: Environment.test);
    GetIt.I.registerSingleton<Env>(env);
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    db = openDisposablePgDatabase(target);

    // A deterministic external graph-provider fixture, local to this disposable
    // database. The live MR service may return only one route, so it cannot
    // reliably exercise competing shortest paths. Keep its real row signature
    // and return committed positive trust weights without computing any path.
    // The production SQL, repository, case, mapper and GraphQL remain in use;
    // no test-only edge subclass or invented domain property carries weights.
    await session.writer.execute(r'''
CREATE OR REPLACE FUNCTION public.mr_graph(
  ego text, focus text, context text DEFAULT '',
  positive_only boolean DEFAULT false, index bigint DEFAULT 0, count bigint DEFAULT 16
) RETURNS TABLE (
  src text, dst text, weight double precision,
  score_value_of_dst double precision, score_value_of_ego double precision,
  score_cluster_of_dst integer, score_cluster_of_ego integer
) LANGUAGE sql STABLE AS $snapshot$
  SELECT e.subject, e.object, e.target_w,
         0::double precision, 0::double precision, 0::integer, 0::integer
  FROM public.user_trust_edge e
  WHERE e.target_w > 0
$snapshot$
''');

    final query = QueryForwardCandidateContext(
      forwardCandidateContextCase: ForwardCandidateContextCase(
        ForwardCandidateContextRepository(db),
        env: env,
        logger: Logger('CandidatePathOrderingTest'),
      ),
    );
    graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.addAll(query.all),
      ),
    );
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: db);
    await GetIt.I.reset();
  });

  setUp(() async {
    await session.writer.execute('TRUNCATE public."user" CASCADE');
    for (final (i, id) in [
      _viewer,
      _candidate,
      _a,
      _b,
      _prefix,
      _secondPrefix,
      _reverse,
    ].indexed) {
      await session.writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) VALUES (@id, @id, @key)',
        ),
        parameters: {'id': id, 'key': pgTestPublicKey('path-ordering', i + 1)},
      );
    }
    // Canonical eligibility is independent of the controlled path snapshot.
    await db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES ('$_viewer', '$_candidate', 1), ('$_candidate', '$_viewer', 1)
''');
  });

  Future<void> expectPath(
    List<(String, String, double)> edges,
    List<String> expected,
  ) async {
    for (final (from, to, trust) in edges) {
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.user_trust_edge (subject, object, trust_w, target_w)
VALUES (@subject, @object, @trust, @trust)
'''),
        parameters: {'subject': from, 'object': to, 'trust': trust},
      );
    }
    // Prove that every competing weighted arc reaches the real provider
    // boundary, rather than testing an already-pruned single-route fixture.
    final raw = await session.writer.execute(
      Sql.named('''
SELECT src, dst, weight FROM public.mr_graph(@viewer, @candidate, 'personal', true, 0, 100)
'''),
      parameters: {'viewer': _viewer, 'candidate': _candidate},
    );
    expect(raw.map((row) => (row[0], row[1], row[2])), unorderedEquals(edges));
    final snapshot = await ForwardCandidateContextRepository(db).loadSnapshot(
      viewerId: _viewer,
      candidateId: _candidate,
      context: 'personal',
    );
    expect(snapshot.candidateEligible, isTrue);
    expect(
      snapshot.edges.map((edge) => (edge.a, edge.b)),
      unorderedEquals(edges.map((edge) => (edge.$1, edge.$2))),
    );

    final data =
        await graphQL.parseAndExecute(
              'query { forwardCandidateContext(candidateId: "$_candidate", context: "personal") '
              '{ status nodes { id } } }',
              globalVariables: {
                kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
              },
            )
            as Map<String, dynamic>;
    final result = data['forwardCandidateContext'] as Map<String, dynamic>;
    expect(result['status'], 'path');
    expect(
      (result['nodes'] as List).map((node) => (node as Map)['id']),
      expected,
    );
  }

  test(
    'equal length directed paths prefer the strongest viewer trust',
    () async {
      await expectPath(
        [
          (_viewer, _a, 0.2),
          (_a, _candidate, 0.9),
          (_viewer, _b, 0.9),
          (_b, _candidate, 0.2),
        ],
        [_viewer, _b, _candidate],
      );
    },
  );

  for (final depth in [1, 2]) {
    test(
      'shared $depth hop prefix prefers stronger incoming trust at the next hop',
      () async {
        final prefix = [_viewer, _prefix, if (depth == 2) _secondPrefix];
        await expectPath(
          [
            for (var i = 1; i < prefix.length; i++)
              (prefix[i - 1], prefix[i], 0.8),
            (prefix.last, _a, 0.2),
            (_a, _candidate, 0.9),
            (prefix.last, _b, 0.9),
            (_b, _candidate, 0.2),
          ],
          [...prefix, _b, _candidate],
        );
      },
    );
  }

  for (final depth in [0, 1, 2]) {
    test(
      'equal incoming trust at hop ${depth + 1} chooses the smaller id',
      () async {
        final prefix = [
          _viewer,
          if (depth >= 1) _prefix,
          if (depth == 2) _secondPrefix,
        ];
        await expectPath(
          [
            for (var i = 1; i < prefix.length; i++)
              (prefix[i - 1], prefix[i], 0.8),
            // Seed larger B first. Once trust ties, A's ID wins even though
            // B's following edge has more trust. The rule applies at every hop.
            (prefix.last, _b, 0.7), (_b, _candidate, 0.9),
            (prefix.last, _a, 0.7), (_a, _candidate, 0.2),
            // A reverse-only shortcut must not displace either directed route.
            // ID sorting already exists today; the missing direction rule makes
            // this combined regression red while retaining the ID fallback check.
            (_candidate, _reverse, 0.9), (_reverse, _viewer, 0.9),
          ],
          [...prefix, _a, _candidate],
        );
      },
    );
  }
}
