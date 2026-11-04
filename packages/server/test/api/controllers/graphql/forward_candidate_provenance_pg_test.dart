@Tags(['pg', 'mr'])
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
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/forward_candidate_context_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';

const _viewer = 'Uprovenance_viewer';
const _candidate = 'Uprovenance_candidate';
const _a = 'Uprovenance_a';
const _b = 'Uprovenance_b';
const _middle = 'Uprovenance_middle';

// Real database -> repository -> case -> GraphQL response. UI input,
// viewport and locale are n/a: this contract changes only the server API.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CANDIDATE_PROVENANCE_TEST_DB',
    defaultNamePrefix: 'tentura_test_candidate_provenance',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late MeritrankRepository meritRank;
  late GraphQL graphQL;

  setUpAll(() async {
    final env = Env(environment: Environment.test);
    GetIt.I.registerSingleton<Env>(env);
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    db = openDisposablePgDatabase(target);
    meritRank = MeritrankRepository(db);
    final query = QueryForwardCandidateContext(
      forwardCandidateContextCase: ForwardCandidateContextCase(
        ForwardCandidateContextRepository(db),
        env: env,
        logger: Logger('CandidateProvenanceTest'),
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
    await meritRank.reset();
    await tearDownDisposablePgWriter(session: session, drift: db);
    await GetIt.I.reset();
  });

  setUp(() async {
    await meritRank.reset();
    await session.writer.execute('TRUNCATE public."user" CASCADE');
    for (final (i, id) in [_viewer, _candidate, _a, _b, _middle].indexed) {
      await session.writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @key, '2025-03-04T12:34:56+02:00', '2026-10-01T00:00:00Z')
'''),
        parameters: {'id': id, 'key': pgTestPublicKey('provenance', i + 1)},
      );
    }
    // Eligibility is independent of the path snapshot, including longPath.
    await db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES ('$_viewer', '$_candidate', 1), ('$_candidate', '$_viewer', 1)
''');
  });

  Future<void> edge(String from, String to, double trust) async {
    await session.writer.execute(
      Sql.named('''
INSERT INTO public.user_trust_edge (subject, object, trust_w, target_w)
VALUES (@subject, @object, @trust, @trust)
'''),
      parameters: {'subject': from, 'object': to, 'trust': trust},
    );
    await meritRank.putEdge(
      nodeA: from,
      nodeB: to,
      weight: trust,
      context: 'personal',
    );
  }

  Future<Map<String, dynamic>> response({bool joined = false}) async {
    final data =
        await graphQL.parseAndExecute(
              'query { forwardCandidateContext(candidateId: "$_candidate", context: "personal") '
              '{ status nodes { id } ${joined ? 'candidate_joined_at' : ''} } }',
              globalVariables: {
                kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
              },
            )
            as Map<String, dynamic>;
    return data['forwardCandidateContext'] as Map<String, dynamic>;
  }

  Future<void> expectJoinedAt(String status) async {
    // Establish a functioning real-path fixture before requesting the new field.
    expect((await response())['status'], status);
    final introspection =
        await graphQL.parseAndExecute(
              'query { __type(name: "ForwardCandidateContext") { fields { name } } }',
            )
            as Map<String, dynamic>;
    final fields =
        ((introspection['__type'] as Map<String, dynamic>)['fields'] as List)
            .cast<Map<String, dynamic>>();
    expect(
      fields.map((field) => field['name']),
      contains('candidate_joined_at'),
      reason:
          'Candidate details must expose account creation time in the context response',
    );
    final result = await response(joined: true);
    expect(result, contains('candidate_joined_at'));
    if (status == 'unavailable') {
      expect(result['candidate_joined_at'], isNull);
    } else {
      final rows = await session.writer.execute(
        Sql.named('SELECT created_at FROM public."user" WHERE id = @id'),
        parameters: {'id': _candidate},
      );
      final raw = result['candidate_joined_at'];
      expect(raw, isNotNull);
      final at = raw is DateTime ? raw : DateTime.parse(raw as String);
      expect(at.isUtc, isTrue);
      expect(at, (rows.single.single as DateTime).toUtc());
    }
  }

  test(
    'path response includes candidate account creation time in UTC',
    () async {
      await edge(_viewer, _middle, 0.8);
      await edge(_middle, _candidate, 0.7);
      await meritRank.calculate();
      await expectJoinedAt('path');
    },
  );

  test(
    'longPath response includes candidate account creation time in UTC',
    () async {
      // Privacy filtering removes the bridge while keeping the candidate
      // eligible and the viewer's visible component in the bounded snapshot.
      await edge(_viewer, _middle, 0.8);
      await edge(_middle, _a, 0.7);
      await edge(_a, _candidate, 0.6);
      await db.customStatement('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_viewer', '$_a', '$_a')
''');
      await meritRank.calculate();
      await expectJoinedAt('longPath');
    },
  );

  test(
    'unavailable response explicitly returns null candidate account creation time',
    () async {
      await db.customStatement('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_viewer', '$_candidate', '$_candidate')
''');
      await meritRank.calculate();
      await expectJoinedAt('unavailable');
    },
  );
}
