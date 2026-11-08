@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

// Public API contract: a Post/Request id that does not exist answers with the
// typed not-found wire code (1002), never the generic unmapped 1000 entry, and
// nothing is reported to Sentry: it is a client mistake, not a server fault.
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:sentry/sentry.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/http/request_context_io_adapter.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/app/sentry/sentry_event_scrub.dart';
import 'package:tentura_server/app/sentry/sentry_request_tracing.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _viewer = 'Uviewer000001';
const _missing = 'Bmissing00001';
const _hidden = 'Bhidden000001';
const _otherAuthor = 'Uother0000001';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MISSING_TARGET_ERROR_TEST_DB',
    defaultNamePrefix: 'tentura_test_missing_target',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('missing-target error codes require reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

  group('Unknown Post and Request ids over the V2 GraphQL endpoint', () {
    late DisposablePgWriterSession session;
    late Handler graphql;
    final events = <SentryEvent>[];

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      await session.writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$_viewer', 'Viewer', '${pgTestPublicKey('missingtarget', 1)}'),
       ('$_otherAuthor', 'Other', '${pgTestPublicKey('missingtarget', 2)}')
''');
      await session.writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable)
VALUES ('$_hidden', '$_otherAuthor', 'Private', '', 0, false)
''');
      final db = target.databaseEnv;
      final env = Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicOrigin: 'http://127.0.0.1:2080',
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        maxConnectionCount: 8,
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
        sentryDsn: 'https://public@example.invalid/1',
      );
      await Sentry.close();
      await Sentry.init((options) {
        options
          ..dsn = env.sentryDsn
          // Observe what would be reported without sending telemetry.
          // ignore: invalid_use_of_internal_member
          ..automatedTestMode = true
          ..beforeSend = (event, hint) {
            final filtered = scrubAndFilterSentryEvent(event, hint);
            if (filtered != null) events.add(filtered);
            return null;
          }
          ..beforeSendTransaction = (transaction, hint) => null;
      });
      getIt
        ..skipDoubleRegistration = true
        ..registerFactory<TenturaDb>(
          () => TenturaDb.scoped(getIt<MainDbPool>()),
        );
      await configureSessionDatabaseTestGraph(env);
      final controller = GraphqlController(env);
      // Production layering: Sentry request context outside the controller.
      graphql = requestContextIoAdapter(
        sentryRequestTracing(env: env)(
          (request) => controller.handler(
            request.change(
              context: {kContextJwtKey: const JwtEntity(sub: _viewer)},
            ),
          ),
        ),
      );
    });

    tearDownAll(() async {
      await Sentry.close();
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    Future<Map<String, dynamic>> run(
      String query,
      Map<String, Object?> variables,
    ) async {
      events.clear();
      final response = await graphql(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v2/graphql'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'query': query, 'variables': variables}),
        ),
      );
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    }

    void expectNotFound(Map<String, dynamic> body) {
      final errors = body['errors'] as List<dynamic>?;
      expect(errors, isNotNull, reason: jsonEncode(body));
      final entry = errors!.single as Map<String, dynamic>;
      expect(
        entry['extensions'],
        containsPair('code', '1002'),
        reason: jsonEncode(body),
      );
      expect(entry['message'], isNot(contains('Something went wrong')));
      // A typed not-found must not take the unmapped-error path, which
      // reports the exception to Sentry.
      expect(
        events,
        isEmpty,
        reason: 'unknown id must not be reported as a server fault',
      );
    }

    for (final mutation in [
      'postLeave',
      'postReturn',
      'postClose',
    ]) {
      test('$mutation on an unknown Post id answers with code 1002', () async {
        expectNotFound(
          await run(
            'mutation (\$id: String!) { $mutation(id: \$id) }',
            {'id': _missing},
          ),
        );
      });
    }

    test('postShorten on an unknown Post id answers with code 1002', () async {
      expectNotFound(
        await run(
          r'mutation ($id: String!, $at: String!) '
          r'{ postShorten(id: $id, expiresAt: $at) }',
          {
            'id': _missing,
            'at': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        ),
      );
    });

    test('postPublish on an unknown Post id answers with code 1002', () async {
      expectNotFound(
        await run(
          r'mutation ($id: String!) { postPublish(id: $id, body: "Hello", '
          'recipientIds: [], forwardPolicy: 0) { beaconId } }',
          {'id': _missing},
        ),
      );
    });

    test(
      'pinning a fact on an unknown Request id answers with code 1002',
      () async {
        expectNotFound(
          await run(
            r'mutation ($id: String!) { BeaconFactCardPin( '
            r'beaconId: $id, factText: "A fact", visibility: 0) }',
            {'id': _missing},
          ),
        );
      },
    );

    test(
      'a Request query on an existing Request the viewer cannot read still '
      'answers unauthorized, not not-found',
      () async {
        // Existence is not revealed to a viewer without access: the access
        // guard answers first, before any beacon is loaded.
        final body = await run(
          r'query ($id: String!) { beaconForwardGraph(id: $id) { beaconId } }',
          {'id': _hidden},
        );
        final entry = (body['errors'] as List).single as Map<String, dynamic>;
        expect(entry['extensions'], containsPair('code', '1102'));
        expect(events, isEmpty);
      },
    );

    test(
      'postSummary on an unknown id still answers null without error',
      () async {
        final body = await run(
          r'query ($id: String!) { postSummary(id: $id) { id } }',
          {'id': _missing},
        );
        expect(body['errors'], isNull, reason: jsonEncode(body));
        expect((body['data'] as Map<String, dynamic>)['postSummary'], isNull);
      },
    );
  });
}
