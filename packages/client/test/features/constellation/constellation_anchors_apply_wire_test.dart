// Client wire layer for the batched anchor mutation: the refreshed schema, V2
// routing, the request the repository sends, and the mapping of the response
// into the Freezed port result.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tentura/data/service/remote_api_client/build_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_anchor_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

Map<String, Object?> _applyPayload() => {
  '__typename': 'v2_ConstellationAnchorsApplyResult',
  'beforeRevision': '9007199254740990',
  'afterRevision': '9007199254740993',
  'results': [
    {
      '__typename': 'v2_ConstellationAnchorOpResult',
      'clientOpId': 'op-upsert',
      'status': 'OK',
      'reason': null,
      'resultingTargetRevision': '9007199254740992',
      'anchor': {
        '__typename': 'v2_ConstellationAnchor',
        'targetKind': 'PERSON',
        'targetId': 'peer-a',
        'xUnits': 1.5,
        'yUnits': -2.25,
        'coordinateSpaceVersion': 1,
        'revision': '9007199254740992',
        'placedAt': '2026-09-09T11:00:00.000Z',
      },
      'replayed': false,
    },
    {
      '__typename': 'v2_ConstellationAnchorOpResult',
      'clientOpId': 'op-delete',
      'status': 'REJECTED',
      'reason': 'stale_revision',
      'resultingTargetRevision': null,
      'anchor': null,
      'replayed': false,
    },
  ],
};

ConstellationAnchorApplyOp _upsertOp({String? ifRevision}) =>
    ConstellationAnchorApplyOp(
      clientOpId: 'op-upsert',
      kind: ConstellationAnchorOpKind.upsert,
      target: ConstellationAnchorTarget.person('peer-a'),
      position: const ConstellationAnchorPosition(
        xUnits: 1.5,
        yUnits: -2.25,
        coordinateSpaceVersion: 1,
      ),
      ifRevision: ifRevision == null
          ? null
          : ConstellationAnchorRevision(BigInt.parse(ifRevision)),
    );

ConstellationAnchorApplyOp _deleteOp() => ConstellationAnchorApplyOp(
  clientOpId: 'op-delete',
  kind: ConstellationAnchorOpKind.delete,
  target: ConstellationAnchorTarget.beacon('B_shared'),
);

void _expectMappedResult(ConstellationAnchorApplyResult result) {
  expect(result.beforeRevision.value, BigInt.parse('9007199254740990'));
  expect(result.afterRevision.value, BigInt.parse('9007199254740993'));

  expect(result.results.map((r) => r.clientOpId), ['op-upsert', 'op-delete']);
  final accepted = result.results.first;
  expect(accepted.status, ConstellationAnchorOpStatus.ok);
  expect(accepted.reason, isNull);
  expect(
    accepted.resultingTargetRevision?.value,
    BigInt.parse('9007199254740992'),
  );
  final rejected = result.results.last;
  expect(rejected.status, ConstellationAnchorOpStatus.rejected);
  expect(rejected.reason, 'stale_revision');
  expect(rejected.resultingTargetRevision, isNull);

  expect(accepted.target, ConstellationAnchorTarget.person('peer-a'));
  expect(accepted.replayed, isFalse);
  final anchor = accepted.anchor!;
  expect(anchor.target, ConstellationAnchorTarget.person('peer-a'));
  expect(anchor.position.xUnits, 1.5);
  expect(anchor.position.yUnits, -2.25);
  expect(anchor.revision.value, BigInt.parse('9007199254740992'));
  expect(anchor.placedAt, DateTime.utc(2026, 9, 9, 11));
  expect(rejected.anchor, isNull);
}

void main() {
  group('anchors apply operation routing', () {
    test('ConstellationAnchorsApply is called on Tentura V2 directly', () {
      expect(isTenturaDirectOperation('ConstellationAnchorsApply'), isTrue);
    });

    test('the build_client direct-operation list names it', () {
      final source = File(
        'lib/data/service/remote_api_client/build_client.dart',
      ).readAsStringSync();
      expect(source, contains("'ConstellationAnchorsApply'"));
    });
  });

  group('refreshed client schema', () {
    test('exposes the batched anchor mutation and its result types', () {
      final schema = File('lib/data/gql/schema.graphql').readAsStringSync();

      expect(schema, contains('constellationAnchorsApply('));
      expect(schema, contains('input v2_ConstellationAnchorOpInput {'));
      expect(schema, contains('input v2_ConstellationAnchorPositionInput {'));
      expect(schema, contains('enum v2_ConstellationAnchorOpKind {'));
      expect(schema, contains('enum v2_ConstellationAnchorOpStatus {'));
      expect(schema, contains('type v2_ConstellationAnchorOpResult {'));
      expect(schema, contains('type v2_ConstellationAnchorsApplyResult {'));
    });
  });

  group('anchors apply client document', () {
    test('is a mutation named ConstellationAnchorsApply selecting the '
        'revisions and the per-op results with the stored anchor row', () {
      final document = File(
        'lib/features/constellation/data/gql/constellation_anchors_apply.graphql',
      ).readAsStringSync();

      expect(document, contains('mutation ConstellationAnchorsApply('));
      expect(document, contains('constellationAnchorsApply('));
      for (final field in const [
        'beforeRevision',
        'afterRevision',
        'clientOpId',
        'status',
        'reason',
        'resultingTargetRevision',
        'anchor',
        'replayed',
      ]) {
        expect(document, contains(field), reason: field);
      }
      expect(document, isNot(contains('anchorProjection')));
    });
  });

  group('ConstellationAnchorRepository.apply', () {
    late List<Map<String, dynamic>> graphqlBodies;
    late List<String> graphqlPaths;
    late MockClient server;

    setUp(() {
      graphqlBodies = [];
      graphqlPaths = [];
      server = MockClient((request) async {
        if (request.url.path.endsWith('/session/access-token')) {
          return http.Response(
            jsonEncode({
              'subject': 'Uviewer000001',
              'access_token': 'test-token',
              'expires_in': 3600,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        graphqlPaths.add(request.url.path);
        graphqlBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'data': {'constellationAnchorsApply': _applyPayload()},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
    });

    Future<T> withRepository<T>(
      Future<T> Function(ConstellationAnchorRepository repository) body,
    ) => http.runWithClient(() async {
      final remote = RemoteApiService(
        const Env(),
        const WebSocketClientRealtimeSocketFactory(),
      );
      try {
        await remote.setSessionAuth();
        return await body(ConstellationAnchorRepository(remote));
      } finally {
        await remote.close();
      }
    }, () => server);

    test('returns the mapped batch result with BigInt-precise revisions', () {
      return withRepository((repository) async {
        final result = await repository.apply(
          ops: [_upsertOp(), _deleteOp()],
          params: ConstellationFieldMembershipFilters.defaults,
        );
        _expectMappedResult(result);
      });
    });

    test('sends ops in order with wire kinds, positions and ifRevision to the '
        'V2 endpoint', () {
      return withRepository((repository) async {
        await repository.apply(
          ops: [
            _upsertOp(ifRevision: '9007199254740991'),
            _deleteOp(),
          ],
          params: const ConstellationFieldMembershipFilters(
            showClosed: true,
            participatedOnly: true,
          ),
        );

        expect(graphqlBodies, hasLength(1));
        expect(graphqlPaths.single, endsWith(kPathGraphQLEndpointV2));
        final body = graphqlBodies.single;
        expect(body['operationName'], 'ConstellationAnchorsApply');
        final variables = body['variables']! as Map<String, dynamic>;
        expect(variables.keys, ['ops']);

        final ops = (variables['ops']! as List).cast<Map<String, dynamic>>();
        expect(ops, hasLength(2));
        expect(ops[0]['clientOpId'], 'op-upsert');
        expect(ops[0]['kind'], 'UPSERT');
        expect(ops[0]['targetKind'], 'PERSON');
        expect(ops[0]['targetId'], 'peer-a');
        expect(ops[0]['ifRevision'], '9007199254740991');
        final position = ops[0]['position']! as Map<String, dynamic>;
        expect(position['xUnits'], 1.5);
        expect(position['yUnits'], -2.25);
        expect(position['coordinateSpaceVersion'], 1);

        expect(ops[1]['clientOpId'], 'op-delete');
        expect(ops[1]['kind'], 'DELETE');
        expect(ops[1]['targetKind'], 'BEACON');
        expect(ops[1]['targetId'], 'B_shared');
        expect(ops[1]['position'], isNull);
        expect(ops[1]['ifRevision'], isNull);
      });
    });
  });
}
