import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:sentry/sentry.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_version.dart';
import 'package:tentura_server/api/http/request_context_io_adapter.dart';
import 'package:tentura_server/app/sentry/sentry_request_tracing.dart';
import 'package:tentura_server/env.dart';

void main() {
  final env = Env(
    environment: Environment.test,
    printEnv: false,
    sentryDsn: 'https://public@o123.ingest.sentry.io/1',
  );
  late List<SentryEvent> events;
  late Future<({int status, Map<String, dynamic> body})> Function(String query)
  post;

  setUp(() async {
    events = [];
    await Sentry.close();
    await Sentry.init((options) {
      options
        ..dsn = env.sentryDsn
        // Surface exceptions from Sentry callbacks during the test.
        // ignore: invalid_use_of_internal_member
        ..automatedTestMode = true
        ..tracesSampleRate = 1.0
        ..beforeSend = (event, hint) {
          events.add(event);
          return null;
        }
        ..beforeSendTransaction = (transaction, hint) => null;
    });
    addTearDown(Sentry.close);

    // Use the real controller, type coercion and production version resolver.
    // Limit the schema to this public field to avoid unrelated database DI.
    final controller = GraphqlController(
      env,
      schema: TenturaGraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', 'Query root')
            ..fields.add(queryVersion),
        ),
        customTypes: customTypes,
      ),
    );
    final router = Router().plus..post('/api/v2/graphql', controller.handler);
    final listening = Completer<Uri>();
    final server = await shelfRun(
      () => requestContextIoAdapter(
        sentryRequestTracing(env: env)(router.call),
      ),
      defaultBindAddress: InternetAddress.loopbackIPv4,
      defaultBindPort: 0,
      defaultEnableHotReload: false,
      onStarted: (address, port) => listening.complete(
        Uri.parse('http://127.0.0.1:$port/api/v2/graphql'),
      ),
    );
    addTearDown(server.close);
    final endpoint = await listening.future.timeout(const Duration(seconds: 5));
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    addTearDown(() => client.close(force: true));
    post = (query) async {
      final request = await client.postUrl(endpoint);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'query': query,
          'operationName': 'VariableTypeProbe',
          'variables': {'t': '2026-11-01T00:15:00Z'},
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final wire = await utf8.decoder
          .bind(response)
          .join()
          .timeout(
            const Duration(seconds: 5),
          );
      return (
        status: response.statusCode,
        body: jsonDecode(wire) as Map<String, dynamic>,
      );
    };

    final healthy = await post('query VariableTypeProbe { version }');
    expect(healthy.status, HttpStatus.ok);
    expect(
      healthy.body['data'],
      isNotNull,
      reason: '${healthy.body}; ${events.map((event) => event.throwable)}',
    );
    expect(
      healthy.body['data'],
      containsPair(
        'version',
        isA<String>().having(
          (value) => value.isNotEmpty,
          'is not empty',
          isTrue,
        ),
      ),
    );
    expect(events, isEmpty);
  });

  group('Unknown GraphQL variable types over HTTP', () {
    test(
      'returns a validation error identifying the unsupported type',
      () async {
        final response = await post(
          r'query VariableTypeProbe($t: timestamptz) { version }',
        );

        _expectVariableTypeValidationError(response);
      },
    );

    test('does not report an unsupported variable type to Sentry', () async {
      // Prove the observer is active before checking absence of reports.
      await Sentry.captureException(StateError('telemetry observer control'));
      expect(events, hasLength(1));
      events.clear();

      final response = await post(
        r'query VariableTypeProbe($t: timestamptz) { version }',
      );
      expect(
        events,
        isEmpty,
        reason: 'An unknown client variable type is not an internal fault.',
      );
      _expectVariableTypeValidationError(response);
    });
  });
}

void _expectVariableTypeValidationError(
  ({int status, Map<String, dynamic> body}) response,
) {
  expect(response.status, isIn([HttpStatus.ok, HttpStatus.badRequest]));
  expect(response.body['data'], isNull);
  final errors = response.body['errors'];
  expect(errors, isA<List<Object?>>());
  if (errors is! List<Object?>) {
    fail('Expected a GraphQL errors array, got $errors');
  }
  expect(errors, isNotEmpty);
  final messages = <String>[];
  for (final error in errors) {
    if (error case {'message': final String message}) {
      messages.add(message);
    } else {
      fail('Expected a GraphQL error message, got $error');
    }
    final code = switch (error) {
      {'extensions': {'code': final Object code}} => code.toString(),
      _ => null,
    };
    expect(
      code,
      isNot('1000'),
      reason: 'Client validation errors must not use the internal fault code.',
    );
  }
  expect(
    messages,
    contains(contains('timestamptz')),
    reason:
        'The validation error must identify the unsupported type '
        'without prescribing its wording.',
  );
}
