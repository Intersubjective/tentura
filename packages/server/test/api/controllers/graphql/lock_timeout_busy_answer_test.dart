// SPDX-License-Identifier: AGPL-3.0-only
//
// A PostgreSQL lock timeout (SQLSTATE 55P03) is contention, not a server
// fault: whatever resolver hits it, the client gets the retryable busy answer
// (1704 + retryAfterMs) and nothing is reported to Sentry.
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart' show PgException, ServerException;
// Decode the same wire error fields as the driver does for a real 55P03.
import 'package:postgres/src/exceptions.dart'
    show buildExceptionFromErrorFields, transformServerException;
import 'package:postgres/src/messages/server_messages.dart'
    show ErrorField, ErrorFieldId;
import 'package:sentry/sentry.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/http/request_context_io_adapter.dart';
import 'package:tentura_server/app/sentry/sentry_event_scrub.dart';
import 'package:tentura_server/app/sentry/sentry_request_tracing.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/env.dart';

/// The error the driver raises when `pg_advisory_xact_lock` or
/// `SELECT … FOR UPDATE` waits longer than the session `lock_timeout`.
PgException _lockTimeout() => transformServerException(
  buildExceptionFromErrorFields([
    ErrorField(ErrorFieldId.severity, 'ERROR'),
    ErrorField(ErrorFieldId.code, '55P03'),
    ErrorField(ErrorFieldId.message, 'canceling statement due to lock timeout'),
    ErrorField(
      ErrorFieldId.where,
      r'SQL statement "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))"',
    ),
  ]),
);

/// A different SQLSTATE: still an internal fault.
PgException _fkViolation() => transformServerException(
  buildExceptionFromErrorFields([
    ErrorField(ErrorFieldId.severity, 'ERROR'),
    ErrorField(ErrorFieldId.code, '23503'),
    ErrorField(
      ErrorFieldId.message,
      'insert or update on table "beacon" violates foreign key constraint',
    ),
  ]),
);

void main() {
  final env = Env(
    environment: Environment.test,
    printEnv: false,
    sentryDsn: 'https://public@example.invalid/1',
  );
  late List<SentryEvent> events;

  setUp(() async {
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

  /// Posts [document] through the production layering (request budget
  /// outside Sentry tracing) to a schema whose resolvers throw [error].
  Future<({int status, Map<String, dynamic> payload})> post(
    String operationName,
    String document,
    Exception error,
  ) async {
    GraphQLObjectField<String, Object?> throwing(String name) =>
        GraphQLObjectField<String, Object?>(
          name,
          graphQLString,
          resolve: (_, _) async => throw error,
        );
    final controller = GraphqlController(
      env,
      schema: TenturaGraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', 'Query root')
            ..fields.add(throwing('probe')),
          mutationType: GraphQLObjectType('Mutation', 'Mutation root')
            ..fields.add(throwing('publishProbe')),
        ),
      ),
    );
    final handler = requestContextIoAdapter(
      sentryRequestTracing(env: env)(controller.handler),
    );
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v2/graphql'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'operationName': operationName, 'query': document}),
      ),
    );
    return (
      status: response.statusCode,
      payload:
          jsonDecode(await response.readAsString()) as Map<String, dynamic>,
    );
  }

  void expectRetryableBusy(({int status, Map<String, dynamic> payload}) r) {
    expect(r.status, lessThan(500), reason: 'lock contention is not a 500');
    final errors = r.payload['errors'] as List?;
    expect(errors, isNotNull, reason: 'expected a busy error: ${r.payload}');
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
    // The client never sees the SQLSTATE or the locked statement.
    final text = jsonEncode(r.payload);
    for (final leak in ['55P03', 'lock timeout', 'pg_advisory_xact_lock']) {
      expect(text, isNot(contains(leak)));
    }
  }

  group('A PostgreSQL lock timeout reaching GraphQL', () {
    test('in a mutation answers retryable busy and reports nothing to '
        'Sentry', () async {
      expect(
        _lockTimeout(),
        isA<ServerException>().having((e) => e.code, 'SQLSTATE', '55P03'),
      );
      final result = await post(
        'PublishProbe',
        'mutation PublishProbe { publishProbe }',
        _lockTimeout(),
      );
      expectRetryableBusy(result);
      expect(
        events,
        isEmpty,
        reason: 'expected lock contention is retryable, not a server fault',
      );
    });

    test('in a query answers retryable busy and reports nothing to '
        'Sentry', () async {
      final result = await post(
        'Probe',
        'query Probe { probe }',
        _lockTimeout(),
      );
      expectRetryableBusy(result);
      expect(events, isEmpty);
    });

    test('other database errors stay a generic server error reported to '
        'Sentry', () async {
      final result = await post(
        'PublishProbe',
        'mutation PublishProbe { publishProbe }',
        _fkViolation(),
      );
      final error = (result.payload['errors'] as List).single as Map;
      expect(error['extensions'], containsPair('code', '1000'));
      expect(events, hasLength(1));
    });
  });
}
