@Tags(['pg'])
library;

import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';
import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/session_database_di_harness.dart';

const _origin = 'http://127.0.0.1:2080';
const _inviter = 'Uaaaaaaaaaaaa';
const _landingAccount = 'Ubbbbbbbbbbbb';
const _newName = 'Ada Lovelace';
const _signup = r'''
mutation SignUp($token: String!, $name: String!, $discoverability: Boolean!) {
  signUp(
    authRequestToken: $token
    displayName: $name
    discoverability: $discoverability
  ) {
    subject
    access_token
  }
}
''';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SIGNUP_DISCOVERABILITY_TEST_DB',
    defaultNamePrefix: 'tentura_test_signup_discoverability',
  );
  final skip = await pgSkipReason(target);

  group('Email discoverability during signup', () {
    late Handler api;
    late Connection writer;

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      writer = session.writer;
      final db = target.databaseEnv;
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });
      await configureSessionDatabaseTestGraph(
        Env(
          environment: Environment.dev,
          serverUri: Uri.parse(_origin),
          publicOrigin: _origin,
          publicKey: Env.kJwtPublicKey,
          privateKey: Env.kJwtPrivateKey,
          pgHost: db.pgHost,
          pgPort: db.pgPort,
          pgDatabase: db.pgDatabase,
          pgUsername: db.pgUsername,
          pgPassword: db.pgPassword,
          workersCount: 1,
          printEnv: false,
          isDebugModeOn: false,
          isNeedInvite: true,
          genealogyNodeKeySecret: 'test-genealogy-secret',
        ),
      );
      api = (await getIt.getAsync<RootRouter>()).routeHandler();
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      for (final (slot, id) in [_inviter, _landingAccount].indexed) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, 'New member', @key)
'''),
          parameters: {
            'id': id,
            'key': pgTestPublicKey('signup-privacy', slot + 1),
          },
        );
      }
    });

    Future<Map<String, Object?>> jsonResponse(Response response) async {
      final body = await response.readAsString();
      expect(response.statusCode, 200, reason: body);
      return jsonDecode(body) as Map<String, Object?>;
    }

    Future<Map<String, Object?>> graphql(
      String query, {
      String? accessToken,
      Map<String, Object?> variables = const {},
    }) async {
      final response = await api(
        Request(
          'POST',
          Uri.parse('$_origin$kPathGraphQLEndpointV2'),
          headers: {
            'content-type': 'application/json',
            if (accessToken != null) 'authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({'query': query, 'variables': variables}),
        ),
      );
      final payload = await jsonResponse(response);
      expect(payload['errors'], isNull, reason: jsonEncode(payload));
      return payload['data']! as Map<String, Object?>;
    }

    Future<void> expectStoredChoice({
      required String accountId,
      required String accessToken,
      required bool choice,
    }) async {
      final returned = await graphql(
        '{ emailDiscoverability }',
        accessToken: accessToken,
      );
      final rows = await writer.execute(
        Sql.named(
          'SELECT enabled FROM public.user_privacy_setting WHERE user_id = @id',
        ),
        parameters: {'id': accountId},
      );
      // An absent row reads as true. Verify persistence even for Yes.
      expect(
        [
          returned['emailDiscoverability'],
          rows.map((row) => row.single).toList(),
        ],
        [
          choice,
          [choice],
        ],
        reason: 'The API and the saved preference must agree',
      );
    }

    for (final choice in [false, true]) {
      final answer = choice ? 'Yes' : 'No';
      test(
        'invited native signup creates an account with $answer saved',
        () async {
          final invite = await getIt<InvitationCase>().create(
            userId: _inviter,
            addresseeName: _newName,
          );
          final result = await graphql(
            _signup,
            variables: {
              'token': _signupRequest(invite.id),
              'name': _newName,
              'discoverability': choice,
            },
          );
          final signup = result['signUp']! as Map<String, Object?>;
          final newAccountId = signup['subject']! as String;
          expect(newAccountId, isNot(isIn([_inviter, _landingAccount])));
          final accounts = await writer.execute(
            Sql.named('SELECT display_name FROM public."user" WHERE id = @id'),
            parameters: {'id': newAccountId},
          );
          expect(accounts.map((row) => row.single), [_newName]);
          await expectStoredChoice(
            accountId: newAccountId,
            accessToken: signup['access_token']! as String,
            choice: choice,
          );
        },
      );

      test(
        'landing name save with a session cookie records $answer for that account',
        () async {
          final sessions = getIt<SessionCase>();
          final session = await sessions.createSession(
            accountId: _landingAccount,
          );
          final response = await api(
            Request(
              'PATCH',
              Uri.parse('$_origin/api/v2/accounts/me/profile'),
              headers: {
                'content-type': 'application/json',
                'cookie': '${sessions.sessionCookieName()}=$session',
              },
              body: jsonEncode({
                'displayName': _newName,
                'discoverability': choice,
              }),
            ),
          );
          final profile = await jsonResponse(response);
          expect(profile, containsPair('id', _landingAccount));
          expect(profile, containsPair('displayName', _newName));
          await expectStoredChoice(
            accountId: _landingAccount,
            accessToken: getIt<AuthCase>()
                .issueAccessToken(_landingAccount)
                .rawToken,
            choice: choice,
          );
          final otherRows = await writer.execute(
            Sql.named(
              'SELECT user_id FROM public.user_privacy_setting WHERE user_id <> @id',
            ),
            parameters: {'id': _landingAccount},
          );
          expect(otherRows, isEmpty);
        },
      );
    }
  }, skip: skip);
}

String _signupRequest(String inviteCode) {
  final publicKey = EdDSAPublicKey.fromPEM(
    Env.kJwtPublicKey.replaceAll(r'\n', '\n'),
  );
  final privateKey = EdDSAPrivateKey.fromPEM(
    Env.kJwtPrivateKey.replaceAll(r'\n', '\n'),
  );
  return JWT({
    AuthRequestIntent.keyPublicKey: base64UrlEncode(publicKey.bytes),
    AuthRequestIntentSignUp.keyCode: inviteCode,
  }).sign(
    privateKey,
    algorithm: JWTAlgorithm.EdDSA,
    expiresIn: const Duration(minutes: 5),
  );
}
