import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart' show PgException;
// Decode the same wire error fields as the driver, including TimeoutException.
import 'package:postgres/src/exceptions.dart'
    show buildExceptionFromErrorFields, transformServerException;
// Wire error fields are needed to create an authentic SQLSTATE 57014 exception.
import 'package:postgres/src/messages/server_messages.dart'
    show ErrorField, ErrorFieldId;
import 'package:sentry/sentry.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/controllers/session_controller.dart';
import 'package:tentura_server/api/http/request_context_io_adapter.dart';
import 'package:tentura_server/app/sentry/sentry_event_scrub.dart';
import 'package:tentura_server/app/sentry/sentry_request_tracing.dart';
import 'package:tentura_server/data/service/main_db_scope_admission.dart';
import 'package:tentura_server/domain/entity/account_session_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/request_context.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';

import '../domain/use_case/invitation_case_mocks.mocks.dart';

const _completionBudget = Duration(seconds: 3);

void main() {
  final env = Env(
    environment: Environment.test,
    printEnv: false,
    sentryDsn: 'https://public@o123.ingest.sentry.io/1',
  );
  late List<SentryEvent> events;

  setUp(() async {
    events = [];
    await Sentry.close();
    await Sentry.init((options) {
      options
        ..dsn = env.sentryDsn
        // Deliberate: surface exceptions from test callbacks.
        // ignore: invalid_use_of_internal_member
        ..automatedTestMode = true
        ..tracesSampleRate = 1.0
        ..beforeSend = (event, hint) {
          final filtered = scrubAndFilterSentryEvent(event, hint);
          if (filtered != null) events.add(filtered);
          // Observe the final event without sending anything over the network.
          return null;
        }
        ..beforeSendTransaction = (transaction, hint) => null;
    });
  });
  tearDown(Sentry.close);

  group('Request failure telemetry', () {
    test(
      'disconnect during database admission emits no error while request '
      'deadlines and unrelated cancellation errors remain visible',
      () async {
        // The same message without a disconnect must not be filtered by text.
        final unrelated = StateError('Request cancelled');
        await _postGraphql(env, () async => throw unrelated);
        expect(events.single.throwable, same(unrelated));

        final deadline = TimeoutException('Request deadline exceeded');
        final context = RequestContext(requestId: 'expired-request');
        addTearDown(context.dispose);
        context.cancel(deadline);
        await _postGraphql(env, () async => 'unreachable', context: context);
        expect(events, hasLength(2));
        expect(events.last.throwable, same(deadline));
        events.clear();

        final admission = MainDbScopeAdmission(
          maxConcurrent: 1,
          interactiveDeadline: const Duration(seconds: 30),
        );
        final holding = Completer<void>();
        final release = Completer<void>();
        final holder = admission.run(() async {
          holding.complete();
          await release.future;
        });
        addTearDown(() async {
          if (!release.isCompleted) release.complete();
          await holder;
          admission.close();
        });
        await holding.future;
        var admitted = false;
        Future<String>? admissionResult;

        final disconnected = await _disconnectGraphql(env, () {
          // Return the real queued admission future unchanged. This resolver
          // never constructs or throws a cancellation error.
          final result = admissionResult = admission.run(() async {
            admitted = true;
            return 'unexpected work';
          });
          expect(admission.queued, 1);
          return result;
        });

        expect(admissionResult, isNotNull);
        await expectLater(
          admissionResult,
          throwsA(same(disconnected.error)),
        );
        expect(
          disconnected.context.check,
          throwsA(same(disconnected.error)),
          reason:
              'Admission must propagate the HTTP adapter cancellation itself.',
        );
        expect(
          disconnected.error,
          isA<StateError>().having(
            (error) => error.message,
            'reason',
            'Request cancelled',
          ),
        );
        expect(disconnected.context.remaining, greaterThan(Duration.zero));
        expect(release.isCompleted, isFalse);
        expect(admitted, isFalse);
        expect(admission.queued, 0);
        expect(admission.running, 1);
        expect(
          events,
          isEmpty,
          reason:
              'A disconnected caller waiting for admission is expected churn.',
        );
      },
    );

    test(
      'SQL-cancellation telemetry after disconnect emits no error while genuine '
      'statement timeouts remain visible',
      () async {
        final statementTimeout = _sqlCancellation(
          'canceling statement due to statement timeout',
        );
        await _postGraphql(env, () async => throw statementTimeout);
        expect(events.single.throwable, same(statementTimeout));

        final timeout = TimeoutException('Attention query exceeded its budget');
        await _postGraphql(env, () async => throw timeout);
        expect(events, hasLength(2));
        expect(events.last.throwable, same(timeout));
        events.clear();

        final sqlCancelled = _sqlCancellation(
          'canceling statement due to user request',
        );
        // Filter unit case: the driver error is constructed here, not produced
        // by SQL. The companion PostgreSQL test covers the database boundary.
        await _disconnectGraphql(env, () async {
          await RequestContext.current!.cancellation;
          throw sqlCancelled;
        });

        expect(
          events,
          isEmpty,
          reason:
              '57014 caused by a disconnected caller must not become an issue.',
        );
      },
    );

    test(
      'access-token telemetry for an already-produced 1704 rejection emits no '
      'error while unexpected session '
      'failures remain visible',
      () async {
        // This tests reporting of a produced capacity rejection, not whether
        // a production auth pool of a particular size should reject traffic.
        final sessions = _AdmissionLimitedSessions();
        addTearDown(sessions.admission.close);
        final logger = Logger('SessionTelemetryTest');
        final controller = SessionController(
          env,
          SessionCase(
            sessions,
            AuthCase(
              MockUserRepositoryPort(),
              MockInvitationRepositoryPort(),
              env: env,
              logger: logger,
            ),
            env: env,
            logger: logger,
          ),
        );
        final handler = requestContextIoAdapter(
          sentryRequestTracing(env: env)(controller.accessToken),
        );
        Request request() => Request(
          'POST',
          Uri.parse('http://localhost/api/v2/session/access-token'),
          headers: {'cookie': '$kCookieSessionName=active-session'},
        );

        final fault = StateError('Unexpected session store failure');
        sessions.failure = fault;
        await expectLater(handler(request()), throwsA(same(fault)));
        expect(events.single.throwable, same(fault));
        events.clear();

        sessions.failure = null;
        await expectLater(
          handler(request()),
          throwsA(
            isA<ConstellationException>().having(
              (error) => error.code.codeNumber,
              'capacity code',
              1704,
            ),
          ),
        );
        expect(sessions.lookups, 2);
        expect(
          events,
          isEmpty,
          reason:
              'Busy on token refresh is a capacity signal, not an error issue.',
        );
      },
    );
  });
}

PgException _sqlCancellation(String message) => transformServerException(
  buildExceptionFromErrorFields([
    ErrorField(ErrorFieldId.severity, 'ERROR'),
    ErrorField(ErrorFieldId.code, '57014'),
    ErrorField(ErrorFieldId.message, message),
  ]),
);

GraphqlController _graphqlController(
  Env env,
  Future<String> Function() resolve,
) => GraphqlController(
  env,
  schema: TenturaGraphQL(
    GraphQLSchema(
      queryType: GraphQLObjectType('Query', 'Query root')
        ..fields.add(
          GraphQLObjectField<String, Object?>(
            'probe',
            graphQLString,
            resolve: (_, _) async => resolve(),
          ),
        ),
    ),
  ),
);

String _graphqlBody() => jsonEncode({
  'operationName': 'TelemetryProbe',
  'query': 'query TelemetryProbe { probe }',
});

Future<void> _postGraphql(
  Env env,
  Future<String> Function() resolve, {
  RequestContext? context,
}) async {
  final handler = sentryRequestTracing(env: env)(
    _graphqlController(env, resolve).handler,
  );
  final requestContext =
      context ?? RequestContext(requestId: 'connected-caller');
  try {
    final response = await requestContext.run(
      () async => handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v2/graphql'),
          headers: {'content-type': 'application/json'},
          body: _graphqlBody(),
        ),
      ),
    );
    expect(response.statusCode, HttpStatus.ok);
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(body['errors'], isNotEmpty);
  } finally {
    requestContext.dispose();
  }
}

/// A real TCP close drives RequestContext.cancel; the test never cancels it.
Future<({RequestContext context, Object error})> _disconnectGraphql(
  Env env,
  Future<String> Function() resolve,
) async {
  final entered = Completer<RequestContext>();
  final finished = Completer<void>();
  final resolverOutcome = Completer<Object?>();
  final controller = _graphqlController(env, () {
    final result = resolve();
    entered.complete(RequestContext.current!);
    // Observe without transforming the resolver's future or manufacturing an
    // error. In the admission case, only MainDbScopeAdmission can reject it.
    unawaited(
      result.then<void>(
        (_) => resolverOutcome.complete(null),
        onError: (Object error, StackTrace _) =>
            resolverOutcome.complete(error),
      ),
    );
    return result;
  });
  final traced = sentryRequestTracing(env: env)(controller.handler);
  final listening = Completer<({Object address, int port})>();
  final server = await shelfRun(
    () => requestContextIoAdapter((request) async {
      try {
        return await traced(request);
      } finally {
        finished.complete();
      }
    }),
    defaultBindAddress: InternetAddress.loopbackIPv4,
    defaultBindPort: 0,
    defaultEnableHotReload: false,
    onStarted: (address, port) =>
        listening.complete((address: address, port: port)),
  );
  final endpoint = await listening.future;
  final socket = await Socket.connect(endpoint.address, endpoint.port);
  try {
    final body = utf8.encode(_graphqlBody());
    socket
      ..write(
        'POST /api/v2/graphql HTTP/1.1\r\n'
        'Host: localhost\r\n'
        'Content-Type: application/json\r\n'
        'Content-Length: ${body.length}\r\n\r\n',
      )
      ..add(body);
    await socket.flush();
    final context = await entered.future.timeout(_completionBudget);
    expect(context.isCancelled, isFalse);
    socket.destroy();
    await finished.future.timeout(_completionBudget);
    expect(context.isCancelled, isTrue);
    final error = await resolverOutcome.future.timeout(_completionBudget);
    expect(error, isNotNull, reason: 'The actual resolver future must fail.');
    return (context: context, error: error!);
  } finally {
    socket.destroy();
    await server.close();
  }
}

final class _AdmissionLimitedSessions implements SessionRepositoryPort {
  final admission = MainDbScopeAdmission(maxConcurrent: 0, maxQueued: 0);
  Error? failure;
  int lookups = 0;

  @override
  Future<AccountSessionEntity?> findActiveByTokenHash(String tokenHash) async {
    lookups++;
    final error = failure;
    if (error != null) throw error;
    return admission.run(() async => null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
