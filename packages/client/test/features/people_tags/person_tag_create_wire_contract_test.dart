// What creating a tag from an automatic tag looks like on the wire: the client
// schema accepts `fromAutoKind`, and the real `PeopleTagsRepository` sends it
// as a variable of the `PersonTagCreate` request, and only when it was given.
//
// Reads the schema by relative path: run from `packages/client`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';

import '../../support/test_realtime_sync.dart';

void main() {
  group('client GraphQL schema', () {
    test('personTagCreate accepts fromAutoKind', () {
      final schema = File('lib/data/gql/schema.graphql').readAsStringSync();
      final line = RegExp(
        r'\bpersonTagCreate\s*\(([^)]*)\)',
      ).firstMatch(schema)?.group(1);

      expect(line, isNotNull, reason: 'personTagCreate is not in the schema');
      expect(line, matches(RegExp(r'fromAutoKind:\s*Int\b')));
      expect(line, isNot(matches(RegExp(r'fromAutoKind:\s*Int!'))));
    });
  });

  group('PeopleTagsRepository.personTagCreate', () {
    test('sends the automatic tag kind it was given', () async {
      final variables = await _createVariables(fromAutoKind: 3);

      expect(variables['fromAutoKind'], 3);
      expect(variables['name'], 'Helped me');
      expect(variables['clientOpId'], 'op-1');
    });

    test('sends no automatic tag kind for a plain new tag', () async {
      final variables = await _createVariables();

      expect(variables['fromAutoKind'], isNull);
      expect(variables['name'], 'Helped me');
    });
  });
}

/// Runs the real [PeopleTagsRepository.personTagCreate] over a mocked
/// transport and returns the variables of the `PersonTagCreate` request.
Future<Map<String, dynamic>> _createVariables({int? fromAutoKind}) async {
  final sent = <Map<String, dynamic>>[];
  await http.runWithClient(
    () async {
      final remote = RemoteApiService(
        const Env(),
        const WebSocketClientRealtimeSocketFactory(),
      );
      final sync = buildTestRealtimeSync();
      try {
        await remote.setSessionAuth();
        // Dynamic, so that a missing parameter fails this test at run time.
        final repository = PeopleTagsRepository(remote) as dynamic;
        final created = await Function.apply(
          repository.personTagCreate as Function,
          const [],
          {
            #name: 'Helped me',
            #clientOpId: 'op-1',
            #fromAutoKind: ?fromAutoKind,
          },
        );
        expect((created as PersonTag).id, 'Tnew');
      } finally {
        await remote.close();
        await sync.port.dispose();
      }
    },
    () => MockClient((request) async {
      if (request.url.path.endsWith('/session/access-token')) {
        return http.Response(
          jsonEncode({
            'subject': 'Uowner0000001',
            'access_token': 'test-token',
            'expires_in': 3600,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final json = jsonDecode(request.body) as Map<String, dynamic>;
      if (json['operationName'] == 'PersonTagCreate') {
        sent.add((json['variables'] as Map).cast<String, dynamic>());
        return http.Response(
          jsonEncode({
            'data': {
              'personTagCreate': {
                '__typename': 'v2_PersonTag',
                'id': 'Tnew',
                'name': 'Helped me',
                'glyph': 'H',
                'color': 1,
                'ord': 1,
                'count': 2,
                'countOffField': 0,
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'data': null}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  expect(sent, hasLength(1));
  return sent.single;
}
