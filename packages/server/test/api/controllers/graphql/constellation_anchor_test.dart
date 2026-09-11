import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_anchor.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';

String _exceptionWireCode(ExceptionBase exception) =>
    '${exception.code.codeNumber}';

Matcher throwsConstellationCode(int codeNumber) => throwsA(
  predicate<ConstellationException>(
    (e) => e.code.codeNumber == codeNumber,
  ),
);

Future<Map<String, dynamic>> _execute({
  required GraphQL graphQL,
  required String document,
  Map<String, dynamic> variables = const {},
  JwtEntity? jwt,
  String? operationName,
}) async {
  final result = await graphQL.parseAndExecute(
    document,
    operationName: operationName,
    variableValues: variables,
    globalVariables: {
      if (jwt != null) kGlobalInputQueryJwt: jwt,
    },
  );
  return result as Map<String, dynamic>;
}

void main() {
  const viewer = 'U_constellation_viewer';
  const peer = 'U_constellation_peer';
  const auth = {kGlobalInputQueryJwt: JwtEntity(sub: viewer)};
  final env = Env(environment: Environment.test);
  final logger = Logger('ConstellationAnchorGraphqlTest');

  late _RecordingAnchorRepository anchorRepo;
  late _RecordingFieldRepository fieldRepo;
  late ConstellationAnchorCase anchorCase;
  late ConstellationFieldCase fieldCase;
  late MutationConstellationAnchor mutation;
  late QueryConstellationField query;
  late GraphQL graphQL;

  setUp(() {
    anchorRepo = _RecordingAnchorRepository();
    fieldRepo = _RecordingFieldRepository();
    anchorCase = ConstellationAnchorCase(
      anchorRepo,
      env: env,
      logger: logger,
    );
    fieldCase = ConstellationFieldCase(
      fieldRepo,
      env: env,
      logger: logger,
    );
    mutation = MutationConstellationAnchor(constellationAnchorCase: anchorCase);
    query = QueryConstellationField(constellationFieldCase: fieldCase);
    graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.addAll(query.all),
        mutationType: GraphQLObjectType('Mutation', 'Mutation root')
          ..fields.addAll(mutation.all),
      ),
      customTypes: customTypes,
    );
  });

  group('emitted schema', () {
    test('registers constellation field args and anchor mutations', () {
      final field = QueryConstellationField(
        constellationFieldCase: fieldCase,
      ).constellationField;
      final argNames = field.inputs.map((i) => i.name).toSet();
      expect(argNames, containsAll(['showClosed', 'participatedOnly', 'projection']));
      expect(argNames, isNot(contains('context')));

      final mutationNames = mutation.all.map((f) => f.name).toSet();
      expect(
        mutationNames,
        containsAll(['constellationAnchorUpsert', 'constellationAnchorDelete']),
      );

      final upsert = mutation.constellationAnchorUpsert;
      expect(
        upsert.inputs.map((i) => i.name).toSet(),
        containsAll([
          'targetKind',
          'targetId',
          'xUnits',
          'yUnits',
          'coordinateSpaceVersion',
        ]),
      );
      expect(query.all.map((f) => f.name), contains('constellationField'));
    });

    test('constellationField defaults projection to FULL', () async {
      fieldRepo.snapshot = _emptySnapshot();
      final result = await _execute(
        graphQL: graphQL,
        document: r'''
          query ConstellationFieldFetch {
            constellationField {
              context
              anchorProjection { revision }
            }
          }
        ''',
        jwt: const JwtEntity(sub: viewer),
        operationName: 'ConstellationFieldFetch',
      );

      expect(fieldRepo.lastProjection, ConstellationProjection.full);
      expect(
        result['constellationField'],
        isA<Map>().having((m) => m['context'], 'context', kConstellationContext),
      );
    });

    test('constellationField ANCHORS projection is forwarded', () async {
      fieldRepo.snapshot = _emptySnapshot();
      await _execute(
        graphQL: graphQL,
        document: r'''
          query ConstellationAnchorsFetch {
            constellationField(projection: ANCHORS) {
              peers { id }
              anchorProjection { revision }
            }
          }
        ''',
        jwt: const JwtEntity(sub: viewer),
        operationName: 'ConstellationAnchorsFetch',
      );
      expect(fieldRepo.lastProjection, ConstellationProjection.anchors);
    });

    test('malformed projection enum fails GraphQL coercion', () async {
      await expectLater(
        _execute(
          graphQL: graphQL,
          document: r'''
            query Bad {
              constellationField(projection: NOT_A_MODE) { loadedAt }
            }
          ''',
          jwt: const JwtEntity(sub: viewer),
        ),
        throwsA(isA<GraphQLException>()),
      );
    });
  });

  group('JWT viewer', () {
    test('missing JWT is unauthorized', () {
      expect(
        () => query.constellationField.resolve!(null, {}),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('forged viewerId argument does not override jwt.sub', () async {
      fieldRepo.snapshot = _emptySnapshot();
      await query.constellationField.resolve!(null, {
        ...auth,
        'viewerId': 'attacker',
        'showClosed': false,
        'participatedOnly': false,
        'projection': 'FULL',
      });
      expect(fieldRepo.lastViewerId, viewer);
    });

    test('mutation uses jwt.sub only', () async {
      anchorRepo.upsertResult = _sampleUpsertResult(peer);
      await mutation.constellationAnchorUpsert.resolve!(null, {
        ...auth,
        'viewerId': 'attacker',
        'targetKind': 'PERSON',
        'targetId': peer,
        'xUnits': 0.0,
        'yUnits': 0.0,
        'coordinateSpaceVersion': kConstellationCoordinateSpaceVersionV1,
      });
      expect(anchorRepo.lastUpsertViewerId, viewer);
    });
  });

  group('domain error codes', () {
    test('ego person upsert is invalidTarget 1700', () {
      expect(
        () => mutation.constellationAnchorUpsert.resolve!(null, {
          ...auth,
          'targetKind': 'PERSON',
          'targetId': viewer,
          'xUnits': 0.0,
          'yUnits': 0.0,
          'coordinateSpaceVersion': kConstellationCoordinateSpaceVersionV1,
        }),
        throwsConstellationCode(
          ConstellationExceptionCodes.codeSpace +
              ConstellationExceptionCode.invalidTarget.index,
        ),
      );
    });

    test('empty target id delete is invalidTarget 1700', () {
      expect(
        () => mutation.constellationAnchorDelete.resolve!(null, {
          ...auth,
          'targetKind': 'PERSON',
          'targetId': '',
        }),
        throwsConstellationCode(1700),
      );
    });

    test('out of range coordinates are invalidCoordinates 1701', () {
      expect(
        () => mutation.constellationAnchorUpsert.resolve!(null, {
          ...auth,
          'targetKind': 'PERSON',
          'targetId': peer,
          'xUnits': 11.0,
          'yUnits': 0.0,
          'coordinateSpaceVersion': kConstellationCoordinateSpaceVersionV1,
        }),
        throwsConstellationCode(1701),
      );
    });

    test('unsupported coordinate space is 1702', () {
      expect(
        () => mutation.constellationAnchorUpsert.resolve!(null, {
          ...auth,
          'targetKind': 'PERSON',
          'targetId': peer,
          'xUnits': 0.0,
          'yUnits': 0.0,
          'coordinateSpaceVersion': 99,
        }),
        throwsConstellationCode(1702),
      );
    });

    test('targetUnavailable 1703 from repository', () async {
      anchorRepo.upsertError = ConstellationException(
        constellationCode: ConstellationExceptionCode.targetUnavailable,
      );
      await expectLater(
        mutation.constellationAnchorUpsert.resolve!(null, {
          ...auth,
          'targetKind': 'PERSON',
          'targetId': peer,
          'xUnits': 0.0,
          'yUnits': 0.0,
          'coordinateSpaceVersion': kConstellationCoordinateSpaceVersionV1,
        }),
        throwsConstellationCode(1703),
      );
    });

    test('missing and forbidden targets share 1703 and description', () async {
      final missing = ConstellationException(
        constellationCode: ConstellationExceptionCode.targetUnavailable,
      );
      final forbidden = ConstellationException(
        constellationCode: ConstellationExceptionCode.targetUnavailable,
      );
      expect(_exceptionWireCode(missing), '1703');
      expect(_exceptionWireCode(forbidden), '1703');
      expect(missing.description, forbidden.description);
      expect(missing.description, isNot(contains(peer)));
    });
  });

  group('mutations', () {
    test('idempotent delete returns target and revision', () async {
      anchorRepo.deleteResult = ConstellationAnchorDeleteResult(
        target: ConstellationAnchorTarget.person(peer),
        watermark: ConstellationAnchorWatermark(
          ConstellationAnchorRevision(BigInt.from(4)),
        ),
      );
      final result =
          await mutation.constellationAnchorDelete.resolve!(null, {
                ...auth,
                'targetKind': 'PERSON',
                'targetId': peer,
              })
              as Map<String, dynamic>;
      expect(result['targetKind'], 'PERSON');
      expect(result['targetId'], peer);
      expect(result['revision'], '4');
    });

    test('upsert returns authoritative anchor and watermark revision', () async {
      anchorRepo.upsertResult = _sampleUpsertResult(peer);
      final result =
          await mutation.constellationAnchorUpsert.resolve!(null, {
                ...auth,
                'targetKind': 'PERSON',
                'targetId': peer,
                'xUnits': 1.5,
                'yUnits': -2.0,
                'coordinateSpaceVersion': kConstellationCoordinateSpaceVersionV1,
              })
              as Map<String, dynamic>;
      final anchor = result['anchor'] as Map<String, dynamic>;
      expect(anchor['targetKind'], 'PERSON');
      expect(anchor['targetId'], peer);
      expect(anchor['xUnits'], 1.5);
      expect(anchor['yUnits'], -2.0);
      expect(anchor['revision'], '9');
      expect(result['revision'], '10');
    });
  });
}

ConstellationFieldSnapshot _emptySnapshot() => ConstellationFieldSnapshot(
  loadedAt: DateTime.utc(2026, 1, 1),
  context: kConstellationContext,
  peers: const [],
  edges: const [],
  requests: const [],
  peersCapped: false,
  requestsCapped: false,
);

ConstellationAnchorUpsertResult _sampleUpsertResult(String peerId) =>
    ConstellationAnchorUpsertResult(
      anchor: ConstellationAnchor(
        target: ConstellationAnchorTarget.person(peerId),
        position: const ConstellationAnchorPosition(
          xUnits: 1.5,
          yUnits: -2,
          coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
        ),
        revision: ConstellationAnchorRevision(BigInt.from(9)),
        placedAt: DateTime.utc(2026, 1, 2),
      ),
      watermark: ConstellationAnchorWatermark(
        ConstellationAnchorRevision(BigInt.from(10)),
      ),
    );

final class _RecordingAnchorRepository implements ConstellationAnchorRepositoryPort {
  String? lastUpsertViewerId;
  ConstellationAnchorUpsertResult? upsertResult;
  ConstellationAnchorDeleteResult? deleteResult;
  Object? upsertError;

  @override
  Future<ConstellationAnchorUpsertResult> upsertAnchor({
    required String viewerId,
    required String context,
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    lastUpsertViewerId = viewerId;
    if (upsertError != null) {
      throw upsertError!;
    }
    return upsertResult!;
  }

  @override
  Future<ConstellationAnchorDeleteResult> deleteAnchor({
    required String viewerId,
    required ConstellationAnchorTarget target,
  }) async =>
      deleteResult!;

  @override
  Future<ConstellationAnchorRevision> readWatermark(String viewerId) async =>
      ConstellationAnchorRevision.zero;
}

final class _RecordingFieldRepository implements ConstellationFieldRepositoryPort {
  ConstellationFieldSnapshot? snapshot;
  String? lastViewerId;
  ConstellationProjection? lastProjection;
  int readCalls = 0;

  @override
  Future<ConstellationFieldSnapshot> readSnapshot({
    required String viewerId,
    required String context,
    required ConstellationFieldReadParams params,
  }) async {
    readCalls++;
    lastViewerId = viewerId;
    lastProjection = params.projection;
    return snapshot!;
  }

  @override
  Future<({Set<String> ids, bool capped})> visibleGraphPeerIds({
    required String viewerId,
    required String context,
    required int cap,
  }) async =>
      (ids: <String>{}, capped: false);

  @override
  Future<List<ConstellationEdgeRecord>> trustEdges({
    required String viewerId,
    required String context,
    required Set<String> nodeIds,
  }) async =>
      const [];

  @override
  Future<List<ConstellationRequestRecord>> ownRequests({
    required String viewerId,
  }) async =>
      const [];

  @override
  Future<List<ConstellationRequestRecord>> discoverableRequests({
    required String viewerId,
    required String context,
    required int cap,
  }) async =>
      const [];

  @override
  Future<List<ConstellationPeerRecord>> peerProfiles({
    required Set<String> ids,
  }) async =>
      const [];
}
