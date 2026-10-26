import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_constellation_tag_magnet.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_tag_magnets.dart';
import 'package:tentura_server/domain/entity/constellation_tag_magnet.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_tag_magnet_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_tag_magnet_case.dart';
import 'package:tentura_server/env.dart';

/// The V2 surface for tag magnets: list, upsert and remove resolve the viewer
/// from the JWT (the wire has no viewer argument), pass `clientOpId` through
/// and reject malformed input before the repository is reached.
void main() {
  const viewer = 'U_magnet_viewer';
  final env = Env(environment: Environment.test);

  late _RecordingRepository repository;
  late ConstellationTagMagnetCase useCase;
  late GraphQL graphQL;

  Future<Map<String, dynamic>> run(
    String document, [
    Map<String, dynamic> variables = const {},
    String sub = viewer,
  ]) async =>
      await graphQL.parseAndExecute(
            document,
            variableValues: variables,
            globalVariables: {
              kGlobalInputQueryJwt: JwtEntity(sub: sub),
            },
          )
          as Map<String, dynamic>;

  setUp(() {
    repository = _RecordingRepository();
    useCase = ConstellationTagMagnetCase(
      repository,
      env: env,
      logger: Logger('ConstellationTagMagnetGraphqlTest'),
    );
    graphQL = GraphQL(
      graphQLSchema(
        queryType: objectType(
          'Query',
          fields: QueryConstellationTagMagnets(
            constellationTagMagnetCase: useCase,
          ).all,
        ),
        mutationType: objectType(
          'Mutation',
          fields: MutationConstellationTagMagnet(
            constellationTagMagnetCase: useCase,
          ).all,
        ),
      ),
    );
  });

  test('constellationTagMagnets lists the magnets of the JWT viewer', () async {
    repository.stored = [
      const ConstellationTagMagnet(
        tagId: 'PT_one',
        xUnits: 2.5,
        yUnits: -1,
        revision: 3,
      ),
    ];

    final data = await run(
      'query { constellationTagMagnets { tagId xUnits yUnits revision } }',
    );

    expect(data['constellationTagMagnets'], [
      {'tagId': 'PT_one', 'xUnits': 2.5, 'yUnits': -1.0, 'revision': 3},
    ]);
    expect(repository.listedFor, viewer);
  });

  test('constellationTagMagnetUpsert writes for the JWT viewer', () async {
    final data = await run(
      r'''
mutation($op: String!) {
  constellationTagMagnetUpsert(
    tagId: "PT_one", xUnits: 4.5, yUnits: -6, clientOpId: $op
  ) { tagId xUnits yUnits revision }
}
''',
      {'op': 'op-upsert'},
    );

    expect((data['constellationTagMagnetUpsert'] as Map)['tagId'], 'PT_one');
    expect(repository.upserts, [
      (
        viewerId: viewer,
        tagId: 'PT_one',
        xUnits: 4.5,
        yUnits: -6.0,
        clientOpId: 'op-upsert',
      ),
    ]);
  });

  test('constellationTagMagnetRemove removes for the JWT viewer', () async {
    final data = await run(
      r'''
mutation($op: String!) {
  constellationTagMagnetRemove(tagId: "PT_one", clientOpId: $op)
}
''',
      {'op': 'op-remove'},
    );

    expect(data['constellationTagMagnetRemove'], isTrue);
    expect(repository.removals, [
      (viewerId: viewer, tagId: 'PT_one', clientOpId: 'op-remove'),
    ]);
  });

  test('the viewer is never read from an argument', () async {
    await run(
      'mutation { constellationTagMagnetRemove(tagId: "PT_one", clientOpId: "a") }',
      const {},
      'U_someone_else',
    );

    expect(repository.removals.single.viewerId, 'U_someone_else');
  });

  group('mutations validate before the repository', () {
    Future<void> expectRejected(
      String document,
      Map<String, dynamic> vars,
    ) async {
      Object? error;
      try {
        await run(document, vars);
      } on Object catch (e) {
        error = e;
      }
      expect(error, isNotNull, reason: 'the mutation must fail');
    }

    test('an empty or over-long clientOpId fails the mutation', () async {
      for (final op in ['', 'x' * 65]) {
        await expectRejected(
          r'''
mutation($op: String!) {
  constellationTagMagnetUpsert(tagId: "PT_one", xUnits: 0, yUnits: 0, clientOpId: $op) { tagId }
}
''',
          {'op': op},
        );
        await expectRejected(
          r'''
mutation($op: String!) {
  constellationTagMagnetRemove(tagId: "PT_one", clientOpId: $op)
}
''',
          {'op': op},
        );
      }
      expect(repository.upserts, isEmpty);
      expect(repository.removals, isEmpty);
    });

    test('out-of-range coordinates fail the mutation', () async {
      for (final (x, y) in [(1e9, 0.0), (0.0, -1e9)]) {
        await expectRejected(
          r'''
mutation($x: Float!, $y: Float!) {
  constellationTagMagnetUpsert(tagId: "PT_one", xUnits: $x, yUnits: $y, clientOpId: "op") { tagId }
}
''',
          {'x': x, 'y': y},
        );
      }
      expect(repository.upserts, isEmpty);
    });
  });

  group('validation before the repository', () {
    Future<ConstellationExceptionCode> codeOf(Future<Object?> call) async {
      try {
        await call;
      } on ConstellationException catch (e) {
        return (e.code as ConstellationExceptionCodes).exceptionCode;
      }
      fail('expected a ConstellationException');
    }

    test('an empty or over-long clientOpId is rejected', () async {
      for (final op in ['', 'x' * 65]) {
        expect(
          await codeOf(
            useCase.upsert(
              viewerId: viewer,
              tagId: 'PT_one',
              xUnits: 0,
              yUnits: 0,
              clientOpId: op,
            ),
          ),
          ConstellationExceptionCode.invalidTarget,
        );
        expect(
          await codeOf(
            useCase.remove(viewerId: viewer, tagId: 'PT_one', clientOpId: op),
          ),
          ConstellationExceptionCode.invalidTarget,
        );
      }
      expect(repository.upserts, isEmpty);
      expect(repository.removals, isEmpty);
    });

    test(
      'non-finite or out-of-range coordinates are invalidCoordinates',
      () async {
        for (final (x, y) in [
          (double.nan, 0.0),
          (0.0, double.infinity),
          (1e9, 0.0),
          (0.0, -1e9),
        ]) {
          expect(
            await codeOf(
              useCase.upsert(
                viewerId: viewer,
                tagId: 'PT_one',
                xUnits: x,
                yUnits: y,
                clientOpId: 'op',
              ),
            ),
            ConstellationExceptionCode.invalidCoordinates,
            reason: '($x, $y)',
          );
        }
        expect(repository.upserts, isEmpty);
      },
    );
  });
}

class _RecordingRepository implements ConstellationTagMagnetRepositoryPort {
  List<ConstellationTagMagnet> stored = const [];
  String? listedFor;
  final upserts =
      <
        ({
          String viewerId,
          String tagId,
          double xUnits,
          double yUnits,
          String clientOpId,
        })
      >[];
  final removals = <({String viewerId, String tagId, String clientOpId})>[];

  @override
  Future<List<ConstellationTagMagnet>> list(String viewerId) async {
    listedFor = viewerId;
    return stored;
  }

  @override
  Future<ConstellationTagMagnet> upsert({
    required String viewerId,
    required String tagId,
    required double xUnits,
    required double yUnits,
    required String clientOpId,
  }) async {
    upserts.add((
      viewerId: viewerId,
      tagId: tagId,
      xUnits: xUnits,
      yUnits: yUnits,
      clientOpId: clientOpId,
    ));
    return ConstellationTagMagnet(
      tagId: tagId,
      xUnits: xUnits,
      yUnits: yUnits,
      revision: 1,
    );
  }

  @override
  Future<void> remove({
    required String viewerId,
    required String tagId,
    required String clientOpId,
  }) async {
    removals.add((viewerId: viewerId, tagId: tagId, clientOpId: clientOpId));
  }
}
