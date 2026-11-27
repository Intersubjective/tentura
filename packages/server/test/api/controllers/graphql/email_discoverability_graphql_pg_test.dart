@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/middleware/auth_middleware.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/sentry_trace_capture.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'Uaaaaaaaaaaaa';
const _other = 'Ubbbbbbbbbbbb';
const _get = '{ emailDiscoverability }';
const _set = r'''
mutation SetEmailDiscoverability($enabled: Boolean!) {
  emailDiscoverabilitySet(enabled: $enabled)
}
''';
const _notificationPreferences = '{ notificationPreferences { accountId } }';
const _origin = 'http://127.0.0.1:2080';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_EMAIL_DISCOVERABILITY_TEST_DB',
    defaultNamePrefix: 'tentura_test_email_discoverability',
  );
  final skip = await pgSkipReason(target);

  group('Account email discoverability through V2', () {
    late Connection writer;
    late Handler api;
    late Map<String, String> tokens;

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
      final env = Env(
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
      );
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });
      await configureSessionDatabaseTestGraph(env);
      api = getIt<AuthMiddleware>().extractJwtClaims(
        getIt<GraphqlController>().handler,
      );
      final auth = getIt<AuthCase>();
      tokens = {
        for (final id in [_owner, _other])
          id: auth.issueAccessToken(id).rawToken,
      };
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      for (final id in [_owner, _other]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
    });

    Future<Response> request(
      String query, {
      String? token,
      Map<String, Object?> variables = const {},
    }) async => api(
      Request(
        'POST',
        Uri.parse('$_origin$kPathGraphQLEndpointV2'),
        headers: {
          'content-type': 'application/json',
          if (token != null) 'authorization': 'Bearer $token',
        },
        body: jsonEncode({'query': query, 'variables': variables}),
      ),
    );

    Future<Map<String, Object?>> payload(Response response) async {
      final body = await response.readAsString();
      expect(response.statusCode, 200, reason: body);
      final result = jsonDecode(body) as Map<String, Object?>;
      final errors = (result['errors'] as List?) ?? const [];
      for (final error in errors) {
        if (error case {'message': final String message}) {
          expect(message.toLowerCase(), isNot(contains('phantom')));
        } else {
          fail('Expected a GraphQL error with a string message: $error');
        }
      }
      return result;
    }

    Future<Map<String, Object?>> data(
      String query, {
      String caller = _owner,
      Map<String, Object?> variables = const {},
    }) async {
      final result = await payload(
        await request(query, token: tokens[caller], variables: variables),
      );
      expect(result['errors'], isNull, reason: jsonEncode(result));
      return result['data']! as Map<String, Object?>;
    }

    Future<Object?> read({String caller = _owner}) async =>
        (await data(_get, caller: caller))['emailDiscoverability'];

    Future<Object?> write({required bool enabled}) async => (await data(
      _set,
      variables: {'enabled': enabled},
    ))['emailDiscoverabilitySet'];

    Future<SentryTraceCapture> startSqlCapture() async {
      final capture = SentryTraceCapture();
      await capture.start();
      addTearDown(capture.stop);

      // A signed-in request through the same handler must register real SQL.
      final control = capture.beginRequest();
      final result = await data(_notificationPreferences);
      expect(result['notificationPreferences'], {'accountId': _owner});
      final trace = await capture.finish(control);
      expect(trace.spansWithOperation('db.sql'), isNotEmpty);
      return capture;
    }

    Future<List<Object?>> storedValues(String userId) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT enabled FROM public.user_privacy_setting WHERE user_id = @id',
        ),
        parameters: {'id': userId},
      );
      return rows.map((row) => row.single).toList();
    }

    test('a new account reads ON without creating a preference row', () async {
      expect(await read(), isTrue);
      expect(await storedValues(_owner), isEmpty);
    });

    test('turning discoverability OFF returns and persists false', () async {
      expect(await write(enabled: false), isFalse);
      expect(await read(), isFalse);
      expect(await storedValues(_owner), [false]);
    });

    test('turning discoverability back ON twice keeps one ON row', () async {
      expect(await write(enabled: false), isFalse);
      expect(await write(enabled: true), isTrue);
      expect(await write(enabled: true), isTrue);
      expect(await read(), isTrue);
      expect(await storedValues(_owner), [true]);
    });

    test('a signed-in account can only change its own preference', () async {
      expect(await write(enabled: false), isFalse);
      expect(await read(caller: _other), isTrue);
      expect(await storedValues(_other), isEmpty);
      expect(await read(), isFalse);
    });

    test(
      'the V2 schema describes the preference without an account selector',
      () async {
        final schema = await data('''
        {
          query: __type(name: "Query") { ...PreferenceFields }
          mutation: __type(name: "Mutation") { ...PreferenceFields }
        }
        fragment PreferenceFields on __Type {
          fields(includeDeprecated: true) {
            name description deprecationReason args { name description }
          }
        }
      ''');

        Map<String, Object?> field(String root, String name) {
          final fields = (schema[root]! as Map)['fields'] as List;
          final preferenceNames = RegExp(
            'email.*discover|discover.*email',
            caseSensitive: false,
          );
          for (final definition in fields.cast<Map<String, Object?>>()) {
            if (!preferenceNames.hasMatch(definition['name']! as String)) {
              continue;
            }
            expect(
              jsonEncode(definition).toLowerCase(),
              isNot(contains('phantom')),
            );
          }
          final matches = fields.cast<Map<String, Object?>>().where(
            (field) => field['name'] == name,
          );
          expect(
            matches,
            hasLength(1),
            reason: '$name must be available in V2',
          );
          return matches.single;
        }

        final query = field('query', 'emailDiscoverability');
        final mutation = field('mutation', 'emailDiscoverabilitySet');
        expect(query['args'], isEmpty);
        expect(
          (mutation['args']! as List).map((arg) => (arg as Map)['name']),
          ['enabled'],
        );
      },
    );

    test(
      'a malformed preference value is rejected without changing the stored value',
      () async {
        expect(await write(enabled: false), isFalse);
        for (final value in [null, 'on']) {
          final result = await payload(
            await request(
              _set,
              token: tokens[_owner],
              variables: {'enabled': value},
            ),
          );
          expect(result['data'], isNull);
          expect(result['errors'], isNotEmpty);
        }
        expect(await read(), isFalse);
        expect(await storedValues(_owner), [false]);
      },
    );

    test(
      'missing credentials get the V2 error without accessing preferences',
      () async {
        ({Object? code, Object? message}) authenticationError(
          Map<String, Object?> response,
        ) {
          expect(response['data'], isNull);
          expect(response['errors'], hasLength(1));
          final error = (response['errors']! as List).single as Map;
          return (
            code: (error['extensions'] as Map?)?['code'],
            message: error['message'],
          );
        }

        final capture = await startSqlCapture();
        final reference = await payload(
          await request(_notificationPreferences),
        );
        final expectedError = authenticationError(reference);
        expect(expectedError.code, '1102');
        expect(
          expectedError.message,
          isA<String>().having(
            (message) => message.trim(),
            'message',
            isNotEmpty,
          ),
        );

        final trace = capture.beginRequest();
        final read = await payload(await request(_get));
        final write = await payload(
          await request(_set, variables: {'enabled': false}),
        );
        final observed = await capture.finish(trace);
        expect(observed.spansWithOperation('db.sql'), isEmpty);
        expect(authenticationError(read), expectedError);
        expect(authenticationError(write), expectedError);
        final rows = await writer.execute(
          'SELECT user_id FROM public.user_privacy_setting',
        );
        expect(rows, isEmpty);
      },
    );

    test(
      'an invalid bearer cannot read or change the preference',
      () async {
        final capture = await startSqlCapture();
        final invalid = '${tokens[_owner]}invalid';
        final reference = await request(
          _notificationPreferences,
          token: invalid,
        );
        expect(reference.statusCode, 401);
        final unauthorized = contains(
          RegExp(r'\bunauthorized\b', caseSensitive: false),
        );
        expect(await reference.readAsString(), unauthorized);

        final trace = capture.beginRequest();
        for (final (query, variables) in [
          (_get, const <String, Object?>{}),
          (_set, const <String, Object?>{'enabled': false}),
        ]) {
          final denied = await request(
            query,
            token: invalid,
            variables: variables,
          );
          expect(denied.statusCode, reference.statusCode);
          final body = await denied.readAsString();
          expect(body, unauthorized);
          expect(body.toLowerCase(), isNot(contains('phantom')));
        }
        final observed = await capture.finish(trace);
        expect(observed.spansWithOperation('db.sql'), isEmpty);
        expect(await read(), isTrue);
        expect(await storedValues(_owner), isEmpty);
      },
    );

    test('deleting an account also deletes its stored preference', () async {
      expect(await write(enabled: false), isFalse);
      expect(await storedValues(_owner), [false]);
      final deleted = await writer.execute(
        Sql.named('DELETE FROM public."user" WHERE id = @id RETURNING id'),
        parameters: {'id': _owner},
      );
      expect(deleted.single.single, _owner);
      expect(await storedValues(_owner), isEmpty);
    });
  }, skip: skip);
}
