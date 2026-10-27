@Tags(['pg', 'mr', 'repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
// ignore: depend_on_referenced_packages
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/middleware/auth_middleware.dart';
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';

import '../../client/test/support/person_untrust_mutation_contract.dart';
import 'support/disposable_pg_target.dart';
import 'support/profile_trust_graph_pg_fixture.dart';

const _me = ProfileTrustGraphPgFixture.alice;
const _bob = ProfileTrustGraphPgFixture.bob;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_UNTRUST_GRAPH_READERS_TEST_DB',
    defaultNamePrefix: 'tentura_test_untrust_readers',
  );
  final reachable = await canReachPostgresAdmin(target);
  late ProfileTrustGraphPgFixture fixture;
  late TrustPublishRepository publisher;
  late HttpServer api;
  late AuthCase auth;

  Future<void> untrustThroughApi() async {
    // Use the independently pinned production contract, also checked against
    // the actual profile, People and graph-card requests in the client test.
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:${api.port}/api/v2/graphql'),
      );
      request.headers
        ..contentType = ContentType.json
        ..set('authorization', 'Bearer ${auth.issueAccessToken(_me).rawToken}');
      request.write(
        jsonEncode(personUntrustMutationRequest(_bob)),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      expect(response.statusCode, HttpStatus.ok, reason: body);
      expect(jsonDecode(body), {
        'data': {'__typename': 'Mutation', 'userVote': 0},
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<void> publishPending() async {
    final token = await publisher.acquireLease('untrust-graph-readers-test');
    expect(token, isNotNull);
    final rows = await publisher.readBatch(100);
    for (final row in rows) {
      await publisher.publish(row);
    }
    await publisher.sync();
    await publisher.ack(token!, rows);
  }

  Future<Set<(String, String)>> graphEdges() async => {
    for (final row in await fixture.db.customSelect('''
SELECT src, dst
FROM (VALUES ('$_me'), ('$_bob')) AS focus(id)
CROSS JOIN LATERAL public.graph(
  focus.id, '', true, '{"x-hasura-user-id":"$_me"}'::json)
WHERE src IN ('$_me', '$_bob') AND dst IN ('$_me', '$_bob')
''').get())
      (row.read<String>('src'), row.read<String>('dst')),
  };

  Future<Set<(String, String)>> publishedEdges() async => {
    for (final row in await fixture.db.customSelect('''
SELECT src, dst FROM public.mr_edgelist()
WHERE src IN ('$_me', '$_bob') AND dst IN ('$_me', '$_bob')
  AND weight > 0
''').get())
      (row.read<String>('src'), row.read<String>('dst')),
  };

  if (reachable) {
    setUpAll(() async {
      fixture = ProfileTrustGraphPgFixture(target);
      await fixture.open();
      await fixture.session.writer.execute(
        'CREATE EXTENSION IF NOT EXISTS pgmer2',
      );
      publisher = TrustPublishRepository(fixture.db);
      final env = Env.test();
      auth = AuthCase(
        _UnusedUsers(),
        _UnusedInvitations(),
        env: env,
        logger: Logger('untrust-api-auth'),
      );
      final controller = GraphqlController(env, schema: fixture.graphQL);
      // Match RootRouter's production GraphQL route and auth middleware;
      // the schema contains the production MutationUserVote resolver backed
      // by the real transactional case and PostgreSQL repositories.
      final router = Router().plus
        ..post(
          '/api/v2/graphql',
          controller.handler,
          use: AuthMiddleware(
            auth,
            SessionCase(
              _UnusedSessions(),
              auth,
              env: env,
              logger: Logger('untrust-api-session'),
            ),
          ).extractJwtClaims,
        );
      api = await shelf_io.serve(router.call, InternetAddress.loopbackIPv4, 0);
    });
    setUp(() async {
      await fixture.seedPublishedMutualTrust();
      // Match an already published mutual pair in the actual MR service.
      // Publication after untrust goes through the production publisher.
      for (final (src, dst) in [(_me, _bob), (_bob, _me)]) {
        await fixture.db.customStatement(
          "SELECT public.mr_put_edge('$src', '$dst', 0.5, '', 0)",
        );
      }
      await publisher.sync();
      expect(await graphEdges(), {(_me, _bob), (_bob, _me)});
      expect(await publishedEdges(), {(_me, _bob), (_bob, _me)});
    });
    tearDownAll(() async {
      try {
        await api.close(force: true);
        for (final (src, dst) in [(_me, _bob), (_bob, _me)]) {
          await fixture.db.customStatement(
            "SELECT public.mr_delete_edge('$src', '$dst')",
          );
        }
        await publisher.sync();
      } finally {
        await fixture.close();
      }
    });
  }

  group(
    'Untrust preserves only the incoming direction in both graph readers',
    () {
      // There is one server mutation, not separate profile and card mutations.
      // The independent client contract checks all three production callers.
      for (final publish in [false, true]) {
        test(
          publish
              ? 'publishing zero UserVote preserves the incoming MeritRank '
                    'edge and one-way graph readers'
              : 'zero UserVote commits one-way graph readers before '
                    'publication acknowledges the change',
          () async {
            await untrustThroughApi();
            expect(await fixture.voteAmount(_me, _bob), 0);
            expect(await fixture.voteAmount(_bob, _me), 1);

            final outgoing = await fixture.db.customSelect('''
SELECT target_w, prev_sent_weight FROM public.user_trust_edge
WHERE subject = '$_me' AND object = '$_bob'
''').getSingle();
            expect(outgoing.read<double>('target_w'), 0);
            expect(outgoing.read<double>('prev_sent_weight'), 0.5);
            final pending = await publisher.readBatch(100);
            expect(
              pending.map((row) => (row.subject, row.object, row.target)),
              [(_me, _bob, 0.0)],
            );
            // MR still has the old outgoing edge; readers must use the
            // committed projection even before publication acknowledges it.
            expect(await publishedEdges(), {(_me, _bob), (_bob, _me)});
            expect(await fixture.edges(), {(_bob, _me)});
            expect(await graphEdges(), {(_bob, _me)});

            if (publish) {
              await publishPending();

              expect(await publisher.readBatch(100), isEmpty);
              expect(await publishedEdges(), {(_bob, _me)});
              expect(await fixture.edges(), {(_bob, _me)});
              expect(await graphEdges(), {(_bob, _me)});
            }
          },
        );
      }

      test(
        'untrust reconciles outgoing graph projections even when the vote '
        'is unchanged',
        () async {
          // Reproduce the persisted mismatch: the profile has stopped
          // trusting, but the committed projection and MR are still mutual.
          // This is setup for recovery, not a claim that the current
          // UserVote resolver created the mismatch.
          await fixture.db.customStatement('''
UPDATE public.vote_user SET amount = 0
WHERE subject = '$_me' AND object = '$_bob'
''');
          expect(await fixture.voteAmount(_me, _bob), 0);
          expect(await fixture.voteAmount(_bob, _me), 1);
          expect(await fixture.edges(), {(_me, _bob), (_bob, _me)});
          expect(await graphEdges(), {(_me, _bob), (_bob, _me)});
          expect(await publisher.readBatch(100), isEmpty);

          // Retry the exact production profile untrust mutation. A successful
          // response must reconcile its graph projection even if the desired
          // vote value has already been committed by an earlier write.
          await untrustThroughApi();
          expect(await fixture.voteAmount(_me, _bob), 0);
          expect(await fixture.voteAmount(_bob, _me), 1);
          expect(
            {
              'graph': await graphEdges(),
              'graph_edges_between': await fixture.edges(),
            },
            {
              'graph': {(_bob, _me)},
              'graph_edges_between': {(_bob, _me)},
            },
            reason:
                'an acknowledged profile untrust must leave only Bob→Me '
                'in both committed graph readers',
          );
          final outgoing = await fixture.db.customSelect('''
SELECT target_w, prev_sent_weight FROM public.user_trust_edge
WHERE subject = '$_me' AND object = '$_bob'
''').getSingle();
          expect(outgoing.read<double>('target_w'), 0);
          expect(outgoing.read<double>('prev_sent_weight'), 0.5);
          expect(
            (await publisher.readBatch(
              100,
            )).map((row) => (row.subject, row.object, row.target)),
            [(_me, _bob, 0.0)],
          );

          await publishPending();

          expect(await publishedEdges(), {(_bob, _me)});
          expect(await publisher.readBatch(100), isEmpty);
          expect(await fixture.edges(), {(_bob, _me)});
          expect(await graphEdges(), {(_bob, _me)});
        },
      );
    },
    skip: reachable ? false : 'Postgres admin unreachable',
  );
}

final class _UnusedUsers extends Fake implements UserRepositoryPort {}

final class _UnusedInvitations extends Fake
    implements InvitationRepositoryPort {}

final class _UnusedSessions extends Fake implements SessionRepositoryPort {}
