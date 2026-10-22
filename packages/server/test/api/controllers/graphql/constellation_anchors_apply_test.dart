import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
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
    graphQL = TenturaGraphQL(
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
    test('is registered with only the ops list', () {
      expect(
        mutation.all.map((f) => f.name),
        contains('constellationAnchorsApply'),
      );
      final argNames = mutation.constellationAnchorsApply.inputs
          .map((i) => i.name)
          .toSet();
      expect(
        argNames,
        equals({'ops'}),
      );
    });

    test('exposes the batch mutation and the reset, no legacy ones', () {
      expect(
        mutation.all.map((f) => f.name),
        orderedEquals([
          'constellationAnchorsApply',
          'constellationAnchorsReset',
        ]),
      );
    });
  });

  group('executing a two-operation batch', () {
    const document = r'''
      mutation ConstellationAnchorsApply(
        $ops: [ConstellationAnchorOpInput!]!
      ) {
        constellationAnchorsApply(
          ops: $ops
        ) {
          beforeRevision
          afterRevision
          results {
            clientOpId
            status
            reason
            resultingTargetRevision
            replayed
            anchor { targetKind targetId xUnits yUnits revision }
          }
        }
      }
    ''';

    Future<Map<String, dynamic>> run({
      required List<Map<String, dynamic>> ops,
    }) async {
      final data =
          await graphQL.parseAndExecute(
                document,
                operationName: 'ConstellationAnchorsApply',
                variableValues: {
                  'ops': ops,
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
        'replayed': false,
        'anchor': {
          'targetKind': 'PERSON',
          'targetId': peerA,
          'xUnits': 1.5,
          'yUnits': -2.0,
          'revision': '4',
        },
      });
      expect(results[1], {
        'clientOpId': 'op-2',
        'status': 'REJECTED',
        'reason': 'stale',
        'resultingTargetRevision': null,
        'replayed': false,
        'anchor': null,
      });
    });

    test('passes each base revision on to the repository (#251)', () async {
      await run(
        ops: [
          {..._upsertOp('op-1', peerA), 'baseRevision': '9007199254740993'},
          _deleteOp('op-2', peerB),
        ],
      );

      expect(
        repository.lastOps!.map((op) => op.baseRevision?.toDecimalString()),
        ['9007199254740993', null],
      );
    });

    test('returns the stored anchor without a projection', () async {
      final result = await run(
        ops: [_upsertOp('op-1', peerA), _deleteOp('op-2', peerB)],
      );
      expect(result.keys.toSet(), {
        'beforeRevision',
        'afterRevision',
        'results',
      });
      final results = result['results'] as List<dynamic>;
      expect((results.first as Map)['anchor'], {
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
      );

      expect(repository.batchCalls, 1);
      expect(repository.lastViewerId, viewer);
      final ops = repository.lastOps!;
      expect(ops.map((o) => o.clientOpId), ['op-1', 'op-2']);
      expect(ops.map((o) => o.kind), [
        AnchorOpKind.upsert,
        AnchorOpKind.delete,
      ]);
      expect(ops[0].target, ConstellationAnchorTarget.person(peerA));
      expect(ops[0].position?.xUnits, 1.5);
      expect(ops[0].position?.yUnits, -2.0);
      expect(ops[1].target, ConstellationAnchorTarget.person(peerB));
      expect(ops[1].position, isNull);
      expect(ops[1].ifRevision, isNull);
    });

    // Web clients send an integral double such as `1.0` as the JSON number
    // `1` (JavaScript has one number type), so Float inputs must accept ints.
    test('accepts integral coordinates sent as JSON integers', () async {
      final result = await run(
        ops: [
          {
            ..._upsertOp('op-1', peerA),
            'position': {
              'xUnits': 1,
              'yUnits': -2,
              'coordinateSpaceVersion': kConstellationCoordinateSpaceVersionV1,
            },
          },
        ],
      );

      expect(
        (result['results'] as List<dynamic>).first,
        containsPair(
          'status',
          'OK',
        ),
      );
      final position = repository.lastOps!.single.position!;
      expect(position.xUnits, 1.0);
      expect(position.yUnits, -2.0);
    });

    for (final argument in ['context', 'showClosed', 'participatedOnly']) {
      test('rejects removed $argument argument', () async {
        await expectLater(
          graphQL.parseAndExecute(
            'mutation { constellationAnchorsApply(ops: [], $argument: '
            '${argument == 'context' ? '"test"' : 'true'}) '
            '{ beforeRevision } }',
            globalVariables: const {
              kGlobalInputQueryJwt: JwtEntity(sub: viewer),
            },
          ),
          throwsA(isA<GraphQLException>()),
        );
        expect(repository.batchCalls, 0);
      });
    }

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

  test(
    'the reset runs for the JWT viewer and maps its outcome (#251)',
    () async {
      final data =
          await graphQL.parseAndExecute(
                r'''
              mutation Reset($clientOpId: String!) {
                constellationAnchorsReset(clientOpId: $clientOpId) {
                  beforeRevision afterRevision clearedCount replayed
                }
              }
              ''',
                operationName: 'Reset',
                variableValues: {'clientOpId': 'reset-op-1'},
                globalVariables: const {
                  kGlobalInputQueryJwt: JwtEntity(sub: viewer),
                },
              )
              as Map<String, dynamic>;

      expect(data['constellationAnchorsReset'], {
        'beforeRevision': '5',
        'afterRevision': '9007199254740993',
        'clearedCount': 3,
        'replayed': false,
      });
      expect(repository.lastViewerId, viewer);
      expect(repository.lastResetOpId, 'reset-op-1');
    },
  );
}

final class _RecordingBatchRepository
    implements ConstellationAnchorRepositoryPort {
  int batchCalls = 0;
  String? lastViewerId;
  List<AnchorApplyOp>? lastOps;

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
  }) async {
    batchCalls++;
    lastViewerId = viewerId;
    lastOps = List.of(ops);
    return AnchorApplyBatchResult(
      beforeRevision: ConstellationAnchorRevision(BigInt.from(3)),
      afterRevision: ConstellationAnchorRevision(BigInt.from(5)),
      results: [
        AnchorApplyOpResult(
          clientOpId: ops.first.clientOpId,
          status: AnchorOpStatus.ok,
          resultingTargetRevision: ConstellationAnchorRevision(BigInt.from(4)),
          position: _peerAAnchor.position,
          anchor: _peerAAnchor,
        ),
        if (ops.length > 1)
          AnchorApplyOpResult(
            clientOpId: ops[1].clientOpId,
            status: AnchorOpStatus.rejected,
            reason: 'stale',
          ),
      ],
    );
  }

  @override
  Future<ConstellationAnchorRevision> readWatermark(String viewerId) async =>
      ConstellationAnchorRevision.zero;

  String? lastResetOpId;

  @override
  Future<AnchorResetResult> resetAll({
    required String viewerId,
    required String clientOpId,
  }) async {
    lastViewerId = viewerId;
    lastResetOpId = clientOpId;
    return AnchorResetResult(
      beforeRevision: ConstellationAnchorRevision(BigInt.from(5)),
      afterRevision: ConstellationAnchorRevision(
        BigInt.parse('9007199254740993'),
      ),
      clearedCount: 3,
    );
  }
}
