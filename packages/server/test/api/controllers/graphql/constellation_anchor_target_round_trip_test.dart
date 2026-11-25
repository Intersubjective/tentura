import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

void main() {
  const viewer = 'Uanchviewer01';
  late TenturaGraphQL graphQL;
  late _PlacementRepository repository;

  setUp(() {
    repository = _PlacementRepository();
    final mutation = MutationConstellationAnchor(
      constellationAnchorCase: ConstellationAnchorCase(
        repository,
        env: Env(environment: Environment.test),
        logger: Logger('AnchorTargetRoundTrip'),
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

  test('the pin target enum exposes the three supported kinds', () async {
    final result = await graphQL.parseAndExecute('''
      query {
        __type(name: "ConstellationAnchorTargetKind") {
          kind
          enumValues { name }
        }
      }
    ''');
    expect(result, {
      '__type': {
        'kind': 'ENUM',
        'enumValues': unorderedEquals([
          {'name': 'PERSON'},
          {'name': 'BEACON'},
          {'name': 'PHANTOM'},
        ]),
      },
    });
  });

  test(
    'the pin mutation preserves each target kind on input and output',
    () async {
      const targets = {
        'PERSON': 'Uanchperson01',
        'BEACON': 'Banchbeacon01',
        'PHANTOM': 'PH0123456789ab',
      };
      final result = await graphQL.parseAndExecute(
        r'''
      mutation PlacePins($ops: [ConstellationAnchorOpInput!]!) {
        constellationAnchorsApply(ops: $ops) {
          results {
            clientOpId
            status
            anchor { targetKind targetId xUnits yUnits coordinateSpaceVersion }
          }
        }
      }
      ''',
        operationName: 'PlacePins',
        variableValues: {
          'ops': [
            for (final MapEntry(key: kind, value: id) in targets.entries)
              {
                'clientOpId': 'place-$kind',
                'kind': 'UPSERT',
                'targetKind': kind,
                'targetId': id,
                'position': {
                  'xUnits': 1.5,
                  'yUnits': -2.0,
                  'coordinateSpaceVersion': 1,
                },
              },
          ],
        },
        globalVariables: const {
          kGlobalInputQueryJwt: JwtEntity(sub: viewer),
        },
      );

      expect(repository.targets, [
        isA<ConstellationAnchorPersonTarget>().having(
          (target) => target.id,
          'id',
          targets['PERSON'],
        ),
        isA<ConstellationAnchorBeaconTarget>().having(
          (target) => target.id,
          'id',
          targets['BEACON'],
        ),
        isA<ConstellationAnchorTarget>()
            .having((target) => target.kind.name, 'kind', 'phantom')
            .having((target) => target.id, 'id', targets['PHANTOM']),
      ]);
      expect(result, {
        'constellationAnchorsApply': {
          'results': [
            for (final MapEntry(key: kind, value: id) in targets.entries)
              {
                'clientOpId': 'place-$kind',
                'status': 'OK',
                'anchor': {
                  'targetKind': kind,
                  'targetId': id,
                  'xUnits': 1.5,
                  'yUnits': -2.0,
                  'coordinateSpaceVersion': 1,
                },
              },
          ],
        },
      });
    },
  );
}

// Return the targets and positions delivered by the mutation to exercise both
// API mappers without substituting any test-generated target or wire kind.
final class _PlacementRepository implements ConstellationAnchorRepositoryPort {
  List<ConstellationAnchorTarget> targets = const [];

  @override
  Future<ConstellationAnchorRevision> readWatermark(String viewerId) =>
      throw UnsupportedError('Only pin placement is exercised');

  @override
  Future<AnchorResetResult> resetAll({
    required String viewerId,
    required String clientOpId,
    bool saveHistory = false,
  }) => throw UnsupportedError('Only pin placement is exercised');

  @override
  Future<AnchorApplyBatchResult> applyBatch({
    required String viewerId,
    required List<AnchorApplyOp> ops,
  }) async {
    targets = ops.map((op) => op.target).toList();
    final revision = ConstellationAnchorRevision(BigInt.from(ops.length));
    return AnchorApplyBatchResult(
      beforeRevision: ConstellationAnchorRevision.zero,
      afterRevision: revision,
      results: [
        for (final op in ops)
          AnchorApplyOpResult(
            clientOpId: op.clientOpId,
            status: AnchorOpStatus.ok,
            resultingTargetRevision: revision,
            position: op.position,
            anchor: ConstellationAnchor(
              target: op.target,
              position: op.position!,
              revision: revision,
              placedAt: DateTime.utc(2026, 1, 2),
            ),
          ),
      ],
    );
  }
}
