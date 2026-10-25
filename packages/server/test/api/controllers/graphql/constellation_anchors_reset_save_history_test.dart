import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_constellation_anchor.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura_server/env.dart';

/// `constellationAnchorsReset(saveHistory: true)` asks the repository to write
/// the undo snapshot inside the reset transaction; without the argument no
/// snapshot is requested.
void main() {
  const viewer = 'U_reset_viewer';
  late _ResetRecordingRepository repository;
  late GraphQL graphQL;

  Future<void> run(String document) => graphQL.parseAndExecute(
    document,
    globalVariables: {kGlobalInputQueryJwt: const JwtEntity(sub: viewer)},
  );

  setUp(() {
    repository = _ResetRecordingRepository();
    graphQL = GraphQL(
      graphQLSchema(
        queryType: objectType(
          'Query',
          fields: [
            field('ping', graphQLString, resolve: (_, _) => 'pong'),
          ],
        ),
        mutationType: objectType(
          'Mutation',
          fields: MutationConstellationAnchor(
            constellationAnchorCase: ConstellationAnchorCase(
              repository,
              env: Env(environment: Environment.test),
              logger: Logger('ConstellationAnchorsResetSaveHistoryTest'),
            ),
          ).all,
        ),
      ),
    );
  });

  test('saveHistory: true is passed to the repository reset', () async {
    await run('''
mutation {
  constellationAnchorsReset(clientOpId: "op-1", saveHistory: true) {
    clearedCount
  }
}
''');

    expect(repository.saveHistoryFlags, [true]);
  });

  test('a reset without saveHistory requests no snapshot', () async {
    await run('''
mutation {
  constellationAnchorsReset(clientOpId: "op-2") { clearedCount }
}
''');

    expect(repository.saveHistoryFlags, [false]);
  });
}

class _ResetRecordingRepository implements ConstellationAnchorRepositoryPort {
  final saveHistoryFlags = <bool>[];

  @override
  Future<AnchorResetResult> resetAll({
    required String viewerId,
    required String clientOpId,
    bool saveHistory = false,
  }) async {
    saveHistoryFlags.add(saveHistory);
    return AnchorResetResult(
      beforeRevision: ConstellationAnchorRevision(BigInt.one),
      afterRevision: ConstellationAnchorRevision(BigInt.two),
      clearedCount: 0,
    );
  }

  @override
  Future<AnchorApplyBatchResult> applyBatch({
    required String viewerId,
    required List<AnchorApplyOp> ops,
  }) => throw UnimplementedError();

  @override
  Future<ConstellationAnchorRevision> readWatermark(String viewerId) =>
      throw UnimplementedError();
}
