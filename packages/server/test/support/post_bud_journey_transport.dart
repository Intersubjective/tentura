// Test-only HTTP fixture for the client Post bud journey. GraphQL documents
// go to production resolvers or to Hasura with the viewer's signed token.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:postgres/postgres.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/repository/notification_identity_repository.dart';
import 'package:tentura_server/data/repository/notification_outbox_repository.dart';
import 'package:tentura_server/data/repository/notification_preference_repository.dart';
import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/data/service/email/templates/email_template_renderer.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import 'package:tentura_server/env.dart';

import 'disposable_pg_target.dart';
import 'hasura_pg_jwt_keys.dart';
import 'isolated_hasura_session.dart';
import 'pg_test_public_keys.dart';
import 'session_database_di_harness.dart';

const _people = {
  'Ubudjourney0A': 'Anna',
  'Ubudjourney0B': 'Bob',
  'Ubudjourney0C': 'Carol',
  'Ubudjourney0K': 'Kira',
  'Ubudjourney0D': 'Dina',
  'Ubudjourney0E': 'Eli',
};
const _postCases = ['private', 'public', 'close'];
const _anna = 'Ubudjourney0A';
const _carol = 'Ubudjourney0C';
const _dina = 'Ubudjourney0D';
const _eli = 'Ubudjourney0E';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_JOURNEY_TEST_DB',
    defaultNamePrefix: 'tentura_test_bud_journey',
  );
  final pg = await setUpDisposablePgWriter(
    target: target,
    createPgmer2Extension: true,
  );
  final database = openDisposablePgDatabase(target);
  HttpServer? server;
  IsolatedHasuraSession? hasura;
  try {
    final keys = loadJwtKeysForHasuraPgTests();
    final db = target.databaseEnv;
    final env = Env(
      environment: Environment.dev,
      serverUri: Uri.parse('http://127.0.0.1:2080'),
      publicOrigin: 'http://127.0.0.1:2080',
      pgHost: db.pgHost,
      pgPort: db.pgPort,
      pgDatabase: db.pgDatabase,
      pgUsername: db.pgUsername,
      pgPassword: db.pgPassword,
      publicKey: keys.publicKey,
      privateKey: keys.privateKey,
      unsubscribeSigningSecret: 'bud-journey-test',
      emailDigestHour: 8,
      printEnv: false,
    );
    await configureSessionDatabaseTestGraph(env);
    final schema = graphqlSchema;
    final auth = getIt<AuthCase>();
    await _seed(pg.writer);
    final hasuraSession = hasura = await IsolatedHasuraSession.start(
      databaseEnv: db,
      jwtPublicPem: keys.publicKey,
    );
    await hasuraSession.applyRepoMetadata();

    final shutdown = Completer<void>();
    final transport = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server = transport;
    transport.listen((request) async {
      final response = request.response;
      response.headers.contentType = ContentType.json;
      try {
        if (request.uri.path == '/close') {
          response.write('{}');
          await response.close();
          shutdown.complete();
          return;
        }
        final viewer = request.uri.queryParameters['viewer']!;
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        switch (request.uri.path) {
          case '/hasura':
            final result = await http.post(
              Uri.parse('${hasuraSession.baseUrl}/v1/graphql'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization':
                    'Bearer ${auth.issueAccessToken(viewer).rawToken}',
              },
              body: jsonEncode(body),
            );
            response
              ..statusCode = result.statusCode
              ..write(result.body);
          case '/stored-actions':
            final rows = await pg.writer.execute(
              Sql.named('''
SELECT
  EXISTS (SELECT 1 FROM public.beacon_forward_edge
          WHERE beacon_id = @id AND sender_id = @viewer AND recipient_id = @recipient
            AND cancelled_at IS NULL),
  EXISTS (SELECT 1 FROM public.beacon_help_offer
          WHERE beacon_id = @id AND user_id = @viewer AND message = @message)
'''),
              parameters: {
                'id': body['id'],
                'viewer': viewer,
                'recipient': body['recipient'],
                'message': body['message'],
              },
            );
            response.write(jsonEncode(rows.single.toList()));
          case '/stored-involvement':
            final rows = await pg.writer.execute(
              Sql.named('''
SELECT EXISTS (
  SELECT 1 FROM public.inbox_item WHERE beacon_id = @id AND user_id = @viewer
  UNION ALL
  SELECT 1 FROM public.beacon_forward_edge
  WHERE beacon_id = @id AND (sender_id = @viewer OR recipient_id = @viewer)
  UNION ALL
  SELECT 1 FROM public.beacon_participant WHERE beacon_id = @id AND user_id = @viewer
  UNION ALL
  SELECT 1 FROM public.beacon_help_offer WHERE beacon_id = @id AND user_id = @viewer
)
'''),
              parameters: {'id': body['id'], 'viewer': viewer},
            );
            response.write(jsonEncode(rows.single.single));
          case '/digests':
            final mail = _CapturedDigest();
            await EmailDigestCase(
              NotificationPreferenceRepository(database),
              NotificationOutboxRepository(database),
              _Contacts(),
              mail,
              EmailLinkBuilder(env),
              env,
              Logger('PostBudJourneyDigest'),
              identity: NotificationIdentityRepository(database),
            ).runDue(
              now: DateTime.timestamp().copyWith(hour: env.emailDigestHour),
            );
            response.write(jsonEncode(mail.byAccount));
          case '/graphql':
            final data = await schema.parseAndExecute(
              body['query'] as String,
              variableValues:
                  (body['variables'] as Map?)?.cast<String, dynamic>() ??
                  const {},
              globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
            );
            response.write(jsonEncode({'data': data}));
          default:
            response.statusCode = HttpStatus.notFound;
        }
      } on Object catch (error, stack) {
        stderr.writeln('$error\n$stack');
        Object? details;
        try {
          details = jsonDecode(error.toString());
        } on FormatException {
          details = {'message': error.toString()};
        }
        response.write(
          jsonEncode({
            'data': null,
            'errors': [details],
          }),
        );
      } finally {
        await response.close();
      }
    });
    stdout.writeln('TENTURA_RECEIPT_TRANSPORT {"ready": ${transport.port}}');
    await shutdown.future;
  } finally {
    await server?.close(force: true);
    await hasura?.stop();
    await getIt.reset();
    await tearDownDisposablePgWriter(session: pg, drift: database);
  }
}

Future<void> _seed(Connection writer) async {
  for (final (index, entry) in _people.entries.indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
      parameters: {
        'id': entry.key,
        'name': entry.value,
        'key': pgTestPublicKey('bud-journey', index + 1),
      },
    );
  }

  for (final (left, right) in [
    (_anna, _carol),
    (_anna, _dina),
    (_carol, _eli),
    (_dina, _eli),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@left, @right, 1), (@right, @left, 1)
'''),
      parameters: {'left': left, 'right': right},
    );
  }

  for (final kind in _postCases) {
    final post = 'Bbudj-${kind.padRight(7, '0')}';
    final root = 'Rbudj-${kind.padRight(7, '0')}';
    await writer.runTx((tx) async {
      await tx.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status, kind,
                           forward_policy, is_discoverable, published_at)
VALUES (@post, @anna, '', '', 0, 1, 1, false, now())
'''),
        parameters: {'post': post, 'anna': _anna},
      );
      await tx.execute(
        Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@root, @post, @anna, 'Plans for the neighborhood garden')
'''),
        parameters: {'post': post, 'root': root, 'anna': _anna},
      );
      await tx.execute(
        Sql.named('''
UPDATE public.beacon SET post_root_message_id = @root WHERE id = @post
'''),
        parameters: {'post': post, 'root': root},
      );
      await tx.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES (@post, @anna, 'Ubudjourney0B'), (@post, @anna, 'Ubudjourney0C'),
       (@post, @anna, 'Ubudjourney0K')
'''),
        parameters: {'post': post, 'anna': _anna},
      );
    });
  }

  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, kind,
                           is_discoverable, published_at)
VALUES ('Bbudj-control', '$_anna', 'Fix the greenhouse door',
        'Bring a screwdriver.', 0, 0, true, now())
''');
}

final class _Contacts extends Fake implements VerifiedContactRepositoryPort {
  @override
  Future<String?> getPrimaryEmailForAccount(String accountId) async =>
      '$accountId@example.test';
}

final class _CapturedDigest extends Fake implements EmailSenderPort {
  final byAccount = <String, List<String>>{};

  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async {
    final email = const EmailTemplateRenderer().renderDigest(
      content: content,
      locale: locale,
    );
    byAccount.putIfAbsent(to.split('@').first, () => []).addAll([
      email.subject,
      email.html,
      email.text,
    ]);
  }
}
