import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_constellation_anchor.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura_server/env.dart';

Matcher throwsConstellationCode(int codeNumber) => throwsA(
  predicate<ConstellationException>(
    (e) => e.code.codeNumber == codeNumber,
  ),
);

Map<String, dynamic> _upsertOp(String opId, String targetId) => {
  'clientOpId': opId,
  'kind': 'UPSERT',
  'targetKind': 'PERSON',
  'targetId': targetId,
  'position': {
    'xUnits': 1.5,
    'yUnits': -2.0,
    'coordinateSpaceVersion': kConstellationCoordinateSpaceVersionV1,
  },
};

Map<String, dynamic> _deleteOp(String opId, String targetId) => {
  'clientOpId': opId,
  'kind': 'DELETE',
  'targetKind': 'PERSON',
  'targetId': targetId,
};

void main() {
  const viewer = 'U_anchors_apply_viewer';
  const peerA = 'U_anchors_apply_peer_a';
  const peerB = 'U_anchors_apply_peer_b';
  const auth = {kGlobalInputQueryJwt: JwtEntity(sub: viewer)};
  final env = Env(environment: Environment.test);
  final logger = Logger('ConstellationAnchorsApplyGraphqlTest');

  late _RecordingBatchRepository repository;
  late MutationConstellationAnchor mutation;
  late GraphQL graphQL;

  setUp(() {
    repository = _RecordingBatchRepository();
    mutation = MutationConstellationAnchor(
      constellationAnchorCase: ConstellationAnchorCase(
        repository,
        env: env,
        logger: logger,
      ),
    );
    graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.add(
            field('ping', graphQLString.nonNullable(), resolve: (_, _) => 'ok'),
          ),
        mutationType: GraphQLObjectType('Mutation', 'Mutation root')
          ..fields.addAll(mutation.all),
      ),
      customTypes: customTypes,
    );
  });

  group('batch anchor mutation schema', () {
    test('is registered with the ops list and projection arguments', () {
      expect(
        mutation.all.map((f) => f.name),
        contains('constellationAnchorsApply'),
      );
      final argNames = mutation.constellationAnchorsApply.inputs
          .map((i) => i.name)
          .toSet();
      expect(
        argNames,
        containsAll(['ops', 'showClosed', 'participatedOnly']),
      );
    });

    test('keeps the single-anchor mutations until they are retired', () {
      expect(
        mutation.all.map((f) => f.name),
        containsAll([
          'constellationAnchorUpsert',
          'constellationAnchorDelete',
        ]),
      );
    });
  });

  group('executing a two-operation batch', () {
    const document = r'''
      mutation ConstellationAnchorsApply(
        $ops: [ConstellationAnchorOpInput!]!
        $showClosed: Boolean!
        $participatedOnly: Boolean!
      ) {
        constellationAnchorsApply(
          ops: $ops
          showClosed: $showClosed
          participatedOnly: $participatedOnly
        ) {
          beforeRevision
          afterRevision
          results {
            clientOpId
            status
            reason
            resultingTargetRevision
          }
          anchorProjection {
            revision
            anchors { targetKind targetId xUnits yUnits revision }
            serverFilteredBeaconCount
          }
        }
      }
    ''';

    Future<Map<String, dynamic>> run({
      required List<Map<String, dynamic>> ops,
      bool showClosed = false,
      bool participatedOnly = false,
    }) async {
      final data =
          await graphQL.parseAndExecute(
                document,
                operationName: 'ConstellationAnchorsApply',
                variableValues: {
                  'ops': ops,
                  'showClosed': showClosed,
                  'participatedOnly': participatedOnly,
                },
                globalVariables: const {
                  kGlobalInputQueryJwt: JwtEntity(sub: viewer),
                },
              )
              as Map<String, dynamic>;
      return data['constellationAnchorsApply'] as Map<String, dynamic>;
    }

    test('returns per-op results in order plus the revision window', () async {
      final result = await run(
        ops: [_upsertOp('op-1', peerA), _deleteOp('op-2', peerB)],
      );

      expect(result['beforeRevision'], '3');
      expect(result['afterRevision'], '5');
      final results = result['results'] as List<dynamic>;
      expect(results, hasLength(2));
      expect(results[0], {
        'clientOpId': 'op-1',
        'status': 'OK',
        'reason': null,
        'resultingTargetRevision': '4',
      });
      expect(results[1], {
        'clientOpId': 'op-2',
        'status': 'REJECTED',
        'reason': 'stale',
        'resultingTargetRevision': null,
      });
    });

    test('returns the complete anchor projection at the after revision', () async {
      final result = await run(
        ops: [_upsertOp('op-1', peerA), _deleteOp('op-2', peerB)],
      );

      final projection = result['anchorProjection'] as Map<String, dynamic>;
      expect(projection['revision'], '5');
      expect(projection['serverFilteredBeaconCount'], 0);
      final anchors = projection['anchors'] as List<dynamic>;
      expect(anchors, hasLength(1));
      expect(anchors.single, {
        'targetKind': 'PERSON',
        'targetId': peerA,
        'xUnits': 1.5,
        'yUnits': -2.0,
        'revision': '4',
      });
    });

    test('hands parsed operations to the port under the JWT viewer', () async {
      await run(
        ops: [_upsertOp('op-1', peerA), _deleteOp('op-2', peerB)],
        showClosed: true,
        participatedOnly: true,
      );

      expect(repository.batchCalls, 1);
      expect(repository.lastViewerId, viewer);
      final ops = repository.lastOps!;
      expect(ops.map((o) => o.clientOpId), ['op-1', 'op-2']);
      expect(ops.map((o) => o.kind), [AnchorOpKind.upsert, AnchorOpKind.delete]);
      expect(ops[0].target, ConstellationAnchorTarget.person(peerA));
      expect(ops[0].position?.xUnits, 1.5);
      expect(ops[0].position?.yUnits, -2.0);
      expect(ops[1].target, ConstellationAnchorTarget.person(peerB));
      expect(ops[1].position, isNull);
      expect(ops[1].ifRevision, isNull);
    });

    test('forwards projection filters and pins the context server side', () async {
      await run(
        ops: [_upsertOp('op-1', peerA)],
        showClosed: true,
        participatedOnly: true,
      );

      final params = repository.lastParams!;
      expect(params.context, kConstellationContext);
      expect(
        params.filters,
        const ConstellationFieldMembershipFilters(
          showClosed: true,
          participatedOnly: true,
        ),
      );
    });

    test('parses ifRevision as a target revision precondition', () async {
      await run(
        ops: [
          {..._upsertOp('op-1', peerA), 'ifRevision': '7'},
        ],
      );

      expect(
        repository.lastOps!.single.ifRevision,
        ConstellationAnchorRevision(BigInt.from(7)),
      );
    });

    test('rejects a malformed operation kind at GraphQL coercion', () async {
      await expectLater(
        run(
          ops: [
            {..._upsertOp('op-1', peerA), 'kind': 'MOVE'},
          ],
        ),
        throwsA(isA<GraphQLException>()),
      );
      expect(repository.batchCalls, 0);
    });
  });

  group('malformed batch input', () {
    Map<String, dynamic> args(List<Map<String, dynamic>> ops) => {
      ...auth,
      'ops': ops,
      'showClosed': false,
      'participatedOnly': false,
    };

    test('upsert without a position is invalidCoordinates 1701', () async {
      final op = _upsertOp('op-1', peerA)..remove('position');

      await expectLater(
        mutation.constellationAnchorsApply.resolve!(null, args([op])),
        throwsConstellationCode(
          ConstellationExceptionCodes.codeSpace +
              ConstellationExceptionCode.invalidCoordinates.index,
        ),
      );
      expect(repository.batchCalls, 0);
    });

    test('upsert with an explicit null position is 1701', () async {
      final op = _upsertOp('op-1', peerA)..['position'] = null;

      await expectLater(
        mutation.constellationAnchorsApply.resolve!(null, args([op])),
        throwsConstellationCode(1701),
      );
      expect(repository.batchCalls, 0);
    });

    test('more than 64 operations is invalidTarget 1700', () async {
      final ops = [
        for (var i = 0; i < 65; i++) _upsertOp('op-$i', 'U_anchors_apply_$i'),
      ];

      await expectLater(
        mutation.constellationAnchorsApply.resolve!(null, args(ops)),
        throwsConstellationCode(
          ConstellationExceptionCodes.codeSpace +
              ConstellationExceptionCode.invalidTarget.index,
        ),
      );
      expect(repository.batchCalls, 0);
    });

    test('exactly 64 operations reaches the port', () async {
      final ops = [
        for (var i = 0; i < 64; i++) _upsertOp('op-$i', 'U_anchors_apply_$i'),
      ];

      await mutation.constellationAnchorsApply.resolve!(null, args(ops));

      expect(repository.batchCalls, 1);
      expect(repository.lastOps, hasLength(64));
    });

    test('duplicate client operation ids are 1700', () async {
      await expectLater(
        mutation.constellationAnchorsApply.resolve!(
          null,
          args([_upsertOp('same', peerA), _deleteOp('same', peerB)]),
        ),
        throwsConstellationCode(1700),
      );
      expect(repository.batchCalls, 0);
    });

    test('unknown target kind is 1700', () async {
      final op = _upsertOp('op-1', peerA)..['targetKind'] = 'GALAXY';

      await expectLater(
        mutation.constellationAnchorsApply.resolve!(null, args([op])),
        throwsConstellationCode(1700),
      );
      expect(repository.batchCalls, 0);
    });

    test('out of range position is 1701', () async {
      final op = _upsertOp('op-1', peerA)
        ..['position'] = {
          'xUnits': 11.0,
          'yUnits': 0.0,
          'coordinateSpaceVersion': kConstellationCoordinateSpaceVersionV1,
        };

      await expectLater(
        mutation.constellationAnchorsApply.resolve!(null, args([op])),
        throwsConstellationCode(1701),
      );
      expect(repository.batchCalls, 0);
    });

    test('missing JWT is unauthorized', () {
      expect(
        () => mutation.constellationAnchorsApply.resolve!(null, {
          'ops': [_upsertOp('op-1', peerA)],
          'showClosed': false,
          'participatedOnly': false,
        }),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('forged viewerId argument does not override jwt.sub', () async {
      await mutation.constellationAnchorsApply.resolve!(null, {
        ...args([_upsertOp('op-1', peerA)]),
        'viewerId': 'attacker',
      });

      expect(repository.lastViewerId, viewer);
    });
  });
}

final class _RecordingBatchRepository
    implements ConstellationAnchorRepositoryPort {
  int batchCalls = 0;
  String? lastViewerId;
  List<AnchorApplyOp>? lastOps;
  AnchorApplyParams? lastParams;

  static final _peerAAnchor = ConstellationAnchor(
    target: ConstellationAnchorTarget.person('U_anchors_apply_peer_a'),
    position: const ConstellationAnchorPosition(
      xUnits: 1.5,
      yUnits: -2,
      coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
    ),
    revision: ConstellationAnchorRevision(BigInt.from(4)),
    placedAt: DateTime.utc(2026, 1, 2),
  );

  @override
  Future<AnchorApplyBatchResult> applyBatch({
    required String viewerId,
    required List<AnchorApplyOp> ops,
    required AnchorApplyParams params,
  }) async {
    batchCalls++;
    lastViewerId = viewerId;
    lastOps = List.of(ops);
    lastParams = params;
    return AnchorApplyBatchResult(
      beforeRevision: ConstellationAnchorRevision(BigInt.from(3)),
      afterRevision: ConstellationAnchorRevision(BigInt.from(5)),
      results: [
        AnchorApplyOpResult(
          clientOpId: ops.first.clientOpId,
          status: AnchorOpStatus.ok,
          resultingTargetRevision: ConstellationAnchorRevision(BigInt.from(4)),
          position: _peerAAnchor.position,
        ),
        if (ops.length > 1)
          AnchorApplyOpResult(
            clientOpId: ops[1].clientOpId,
            status: AnchorOpStatus.rejected,
            reason: 'stale',
          ),
      ],
      projection: ConstellationAnchorProjection(
        revision: ConstellationAnchorRevision(BigInt.from(5)),
        anchors: [_peerAAnchor],
        pinnedPeers: const [],
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );
  }

  @override
  Future<ConstellationAnchorUpsertResult> upsertAnchor({
    required String viewerId,
    required String context,
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) => throw StateError('The batch mutation must not call single upsert');

  @override
  Future<ConstellationAnchorDeleteResult> deleteAnchor({
    required String viewerId,
    required ConstellationAnchorTarget target,
  }) => throw StateError('The batch mutation must not call single delete');

  @override
  Future<ConstellationAnchorRevision> readWatermark(String viewerId) async =>
      ConstellationAnchorRevision.zero;
}
