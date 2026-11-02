@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

// The real postPublish mutation, over a real PostgreSQL lock wait that outlasts
// the request's own lock_timeout: the client must get the retryable busy answer
// (1704 + retryAfterMs), never a generic server error or a Sentry issue.
import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:sentry/sentry.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_post.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/http/request_context_io_adapter.dart';
import 'package:tentura_server/app/sentry/sentry_event_scrub.dart';
import 'package:tentura_server/app/sentry/sentry_request_tracing.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/post_publish_pg_support.dart';

const _publish = r'''
mutation PostPublish($id: String!, $body: String, $recipientIds: [String!]) {
  postPublish(id: $id, body: $body, recipientIds: $recipientIds,
      forwardPolicy: 1) {
    beaconId rootMessageId
  }
}
''';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_PUBLISH_LOCK_TIMEOUT_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_publish_lock_timeout',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Post publication lock timeout requires reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

  group('Publishing a Post while PostgreSQL holds a conflicting lock', () {
    final env = Env(
      environment: Environment.test,
      printEnv: false,
      sentryDsn: 'https://public@example.invalid/1',
    );
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late Handler handler;
    late List<SentryEvent> events;

    setUpAll(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      db = TenturaDb(target.databaseEnv);
      final posts = PostPublishHarness.build(db, target.databaseEnv).posts;
      final controller = GraphqlController(
        env,
        schema: TenturaGraphQL(
          GraphQLSchema(
            queryType: GraphQLObjectType('Query', 'Query root')
              ..fields.add(
                GraphQLObjectField<String, Object?>(
                  'health',
                  graphQLString,
                  resolve: (_, _) => 'ok',
                ),
              ),
            mutationType: GraphQLObjectType('Mutation', 'Mutation root')
              ..fields.add(MutationPost(postCase: posts).postPublish),
          ),
          customTypes: customTypes,
        ),
      );
      // Same layering as production: request budget outside Sentry tracing,
      // the authenticated author in the request context.
      handler = requestContextIoAdapter(
        sentryRequestTracing(env: env)(
          (request) => controller.handler(
            request.change(
              context: {kContextJwtKey: JwtEntity(sub: postPublishAuthor(0))},
            ),
          ),
        ),
      );
    });

    setUp(() async {
      await seedPostPublishFixture(writer);
      events = [];
      await Sentry.close();
      await Sentry.init((options) {
        options
          ..dsn = env.sentryDsn
          // Observe classification without sending telemetry anywhere.
          // ignore: invalid_use_of_internal_member
          ..automatedTestMode = true
          ..beforeSend = (event, hint) {
            final filtered = scrubAndFilterSentryEvent(event, hint);
            if (filtered != null) events.add(filtered);
            return null;
          }
          ..beforeSendTransaction = (transaction, hint) => null;
      });
    });

    tearDown(Sentry.close);

    tearDownAll(() async {
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });

    /// Runs the real mutation while [hold] keeps a lock in another session,
    /// releasing it only after the response is complete.
    Future<({int status, Map<String, dynamic> payload, bool waitedOnLock})>
    publishWhileHeld(String hold) async {
      await writer.execute('BEGIN');
      try {
        await writer.execute(
          Sql.named(hold),
          parameters: {'post': postPublishId('race', 0)},
        );
        final pending = Future.value(
          handler(
            Request(
              'POST',
              Uri.parse('http://localhost/api/v2/graphql'),
              headers: {'content-type': 'application/json'},
              body: jsonEncode({
                'operationName': 'PostPublish',
                'query': _publish,
                'variables': {
                  'id': postPublishId('race', 0),
                  'body': postPublishBody(0),
                  'recipientIds': [postPublishRecipient],
                },
              }),
            ),
          ),
        ).timeout(const Duration(seconds: 30));
        // Observe, from outside, that the publisher really queued behind the
        // held lock (so a failure here is lock contention, not a bad fixture).
        var done = false;
        unawaited(
          pending.whenComplete(() => done = true).then((_) {}, onError: (_) {}),
        );
        var waitedOnLock = false;
        while (!done && !waitedOnLock) {
          // The writer is inside a transaction: drop its cached stats snapshot.
          await writer.execute('SELECT pg_stat_clear_snapshot()');
          final rows = await writer.execute(
            'SELECT 1 FROM pg_stat_activity WHERE datname = current_database() '
            "AND pid <> pg_backend_pid() AND wait_event_type = 'Lock'",
          );
          waitedOnLock = rows.isNotEmpty;
          if (!waitedOnLock) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        }
        final response = await pending;
        final body = await response.readAsString();
        return (
          status: response.statusCode,
          payload: jsonDecode(body) as Map<String, dynamic>,
          waitedOnLock: waitedOnLock,
        );
      } finally {
        await writer.execute('ROLLBACK');
      }
    }

    Future<List<Object?>> draftState() async => (await writer.execute(
      Sql.named(
        'SELECT status, post_root_message_id FROM public.beacon WHERE id = @id',
      ),
      parameters: {'id': postPublishId('race', 0)},
    )).single.toList();

    void expectRetryableBusy(Map<String, dynamic> payload, int status) {
      expect(status, lessThan(500), reason: 'lock contention is not a 500');
      final errors = payload['errors'] as List?;
      expect(errors, isNotNull, reason: 'expected a busy error: $payload');
      final error = errors!.single as Map<String, dynamic>;
      expect(
        error['extensions'],
        allOf(
          containsPair('code', '1704'),
          containsPair('retryAfterMs', allOf(isA<int>(), greaterThan(0))),
        ),
        reason: 'a lock timeout must map to the retryable busy answer',
      );
      expect(
        error['message'],
        ConstellationException(
          constellationCode: ConstellationExceptionCode.retryLater,
        ).toMap['message'],
      );
      expect(jsonEncode(payload), isNot(contains('55P03')));
      expect(
        payload['data'],
        anyOf(isNull, containsPair('postPublish', isNull)),
      );
    }

    test(
      'a Post row held past the request lock timeout returns retryable '
      'busy, leaves the draft unpublished and reports nothing to Sentry',
      () async {
        // Every remedy keeps the Post row lock, so this wait is a genuine
        // PostgreSQL 55P03 on the publish path regardless of how it is narrowed.
        final result = await publishWhileHeld(
          'SELECT 1 FROM public.beacon WHERE id = @post FOR UPDATE',
        );
        expect(
          result.waitedOnLock,
          isTrue,
          reason: 'publication must have waited on the held Post row',
        );
        expectRetryableBusy(result.payload, result.status);
        expect(await draftState(), [3, null]);
        expect(
          events,
          isEmpty,
          reason: 'expected lock contention is retryable, not a server fault',
        );
      },
    );

    test('a hierarchy mutation holding the hierarchy scope past the request '
        'lock timeout lets publication finish or answers retryable busy', () async {
      // A long budding/re-parenting transaction holds the shared hierarchy key.
      final result = await publishWhileHeld(
        "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0)), "
        'cast(@post AS text)',
      );
      final errors = result.payload['errors'] as List?;
      if (errors == null || errors.isEmpty) {
        // The narrowed publish never waits on the hierarchy scope.
        final data = (result.payload['data'] as Map)['postPublish'] as Map;
        expect(data['beaconId'], postPublishId('race', 0));
        expect((await draftState()).first, 0);
      } else {
        expect(
          result.waitedOnLock,
          isTrue,
          reason: 'a busy answer must come from waiting on the held scope',
        );
        expectRetryableBusy(result.payload, result.status);
        expect(await draftState(), [3, null]);
      }
      expect(events, isEmpty);
    });
  });
}
