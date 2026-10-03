// What a Post draft and a `postPublish` call look like on the wire: the
// client schema and documents expose `kind`, `forwardPolicy`, an optional
// title and the `postPublish` mutation, and the real `BeaconRepository` sends
// a Post draft with kind 1, no title and not discoverable.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';

import '../../support/test_realtime_sync.dart';

File? _findDocument(String name) {
  for (final entity in Directory('lib/features').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('/$name')) return entity;
  }
  return null;
}

void main() {
  late final String schema;

  setUpAll(() {
    schema = File('lib/data/gql/schema.graphql').readAsStringSync();
  });

  group('client GraphQL schema', () {
    test('beaconCreate takes kind and forwardPolicy and an optional title', () {
      final line = schema
          .split('\n')
          .firstWhere((l) => l.trimLeft().startsWith('beaconCreate('));
      expect(line, contains('kind: Int'));
      expect(line, contains('forwardPolicy: Int'));
      expect(line, contains('title: String'));
      expect(line, isNot(contains('title: String!')));
    });

    test('exposes the postPublish mutation and its result type', () {
      expect(schema, contains('postPublish('));
      expect(schema, contains('type v2_PostPublishResult {'));
      expect(schema, contains('rootMessageId: String!'));
    });
  });

  group('client GraphQL documents', () {
    test(
      'beacon_create.graphql declares kind, forwardPolicy and a nullable title',
      () {
        final doc = File(
          'lib/features/beacon/data/gql/beacon_create.graphql',
        ).readAsStringSync();
        expect(doc, contains(r'$kind: Int'));
        expect(doc, contains(r'$forwardPolicy: Int'));
        expect(doc, isNot(contains(r'$title: String!')));
        expect(doc, contains(r'kind: $kind'));
        expect(doc, contains(r'forwardPolicy: $forwardPolicy'));
      },
    );

    test('post_publish.graphql sends the first attachment as an upload', () {
      final file = _findDocument('post_publish.graphql');
      expect(file, isNotNull, reason: 'post_publish.graphql must exist');
      final doc = file!.readAsStringSync();
      expect(doc, contains('mutation PostPublish'));
      expect(doc, contains('postPublish('));
      expect(doc, contains('v2_Upload'));
      expect(doc, contains('rootMessageId'));
    });
  });

  group('BeaconRepository.create for a Post draft', () {
    test('sends kind 1, no title and isDiscoverable false', () async {
      final variables = await _createVariables(
        Beacon.empty.copyWith(
          kind: BeaconKind.post,
          title: '',
          isDiscoverable: false,
        ),
      );

      expect(variables['kind'], 1);
      expect(variables['title'], isNull);
      expect(variables['isDiscoverable'], isFalse);
      expect(variables['draft'], isTrue);
    });

    test(
      'sends the open forward policy (1) for a Post that may be forwarded',
      () async {
        final variables = await _createVariables(
          Beacon.empty.copyWith(
            kind: BeaconKind.post,
            title: '',
            isDiscoverable: false,
            forwardPolicy: BeaconForwardPolicyValue.open,
          ),
        );

        expect(variables['forwardPolicy'], 1);
      },
    );

    test(
      'sends the closed forward policy (0) for a Post that may not be forwarded',
      () async {
        final variables = await _createVariables(
          Beacon.empty.copyWith(
            kind: BeaconKind.post,
            title: '',
            isDiscoverable: false,
            forwardPolicy: BeaconForwardPolicyValue.closed,
          ),
        );

        expect(variables['forwardPolicy'], 0);
      },
    );
  });
}

/// Runs the real [BeaconRepository.create] over a mocked transport and returns
/// the variables of the `BeaconCreate` request it sent.
Future<Map<String, dynamic>> _createVariables(Beacon beacon) async {
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
        final repository = BeaconRepository(remote, sync.port);
        try {
          await repository.create(beacon, draft: true);
        } on Object {
          // The follow-up fetch has no canned response; only the create
          // request's variables matter here.
        }
      } finally {
        await remote.close();
        await sync.port.dispose();
      }
    },
    () => MockClient((request) async {
      if (request.url.path.endsWith('/session/access-token')) {
        return http.Response(
          jsonEncode({
            'subject': 'Uauthor000001',
            'access_token': 'test-token',
            'expires_in': 3600,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final json = jsonDecode(request.body) as Map<String, dynamic>;
      if (json['operationName'] == 'BeaconCreate') {
        sent.add((json['variables'] as Map).cast<String, dynamic>());
        return http.Response(
          jsonEncode({
            'data': {
              'beaconCreate': {
                '__typename': 'v2_Beacon',
                'id': 'Bpostdraft001',
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
