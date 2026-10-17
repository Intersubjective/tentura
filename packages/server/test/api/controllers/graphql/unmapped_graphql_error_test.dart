// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart' show PgException;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql/unmapped_graphql_error.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/env.dart';

/// The FK violation from #342, as the driver reports it.
PgException _fkViolation() => PgException(
  '23503: insert or update on table "ego_witness_window" violates '
  'foreign key constraint "ego_witness_window_witness_user_id_fkey" '
  'detail: Key (witness_user_id)=(Vde0a2ed44ac8) is not present in '
  'table "user"',
);

/// The real controller over a one-field schema whose resolver throws [error].
Future<Map<String, dynamic>> _postThrowing(Object error) async {
  final controller = GraphqlController(
    Env(environment: Environment.test),
    schema: TenturaGraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.add(
            GraphQLObjectField<String, Object?>(
              'boom',
              graphQLString,
              resolve: (_, _) => throw error,
            ),
          ),
      ),
    ),
  );
  final response = await controller.handler(
    Request(
      'POST',
      Uri.parse('http://localhost/api/v2/graphql'),
      body: jsonEncode({
        'operationName': 'Boom',
        'query': 'query Boom { boom }',
      }),
      headers: {'content-type': 'application/json'},
    ),
  );
  expect(response.statusCode, 200);
  return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
}

const _leaks = [
  '23503',
  'ego_witness_window',
  'fkey',
  'Vde0a2ed44ac8',
  'pool connect',
  'TimeoutException',
];

void main() {
  group('unmappedGraphqlError', () {
    test('never forwards a database driver error to the client', () {
      final error = PgException(
        '23503: insert or update on table "ego_witness_window" violates '
        'foreign key constraint "ego_witness_window_witness_user_id_fkey" '
        'detail: Key (witness_user_id)=(Vde0a2ed44ac8) is not present in '
        'table "user"',
      );

      final entry = unmappedGraphqlError(error);

      expect(entry['message'], kUnmappedDatabaseErrorMessage);
      expect(entry['extensions'], containsPair('code', '1000'));
      final text = entry.toString();
      for (final leak in [
        '23503',
        'ego_witness_window',
        'fkey',
        'Vde0a2ed44ac8',
        'Severity',
      ]) {
        expect(text, isNot(contains(leak)));
      }
    });

    test('never forwards the text of any other unmapped exception', () {
      for (final error in <Object>[
        StateError('Main DB admission re-entry is not allowed'),
        TimeoutException('pool connect', const Duration(seconds: 5)),
        Exception('Unexpected type'),
      ]) {
        final entry = unmappedGraphqlError(error);

        expect(entry['message'], kUnmappedDatabaseErrorMessage);
        expect(entry['extensions'], containsPair('code', '1000'));
        for (final leak in ['Bad state', 'admission', 'pool', 'Unexpected']) {
          expect(entry.toString(), isNot(contains(leak)));
        }
      }
    });
  });

  // #593 review: the leak was the controller's raw `e.toString()`; this goes
  // through the actual handler, so it fails if the handler stops sanitizing.
  group('GraphqlController.handler', () {
    for (final (name, error) in <(String, Object)>[
      ('a database error', _fkViolation()),
      (
        'a pool timeout',
        TimeoutException('pool connect', const Duration(seconds: 5)),
      ),
    ]) {
      test('answers $name thrown by a resolver with code 1000 only', () async {
        final body = await _postThrowing(error);

        final entry = (body['errors'] as List).single as Map<String, dynamic>;
        expect(entry['message'], kUnmappedDatabaseErrorMessage);
        expect(entry['extensions'], containsPair('code', '1000'));
        final text = jsonEncode(body);
        for (final leak in _leaks) {
          expect(text, isNot(contains(leak)));
        }
      });
    }
  });
}
