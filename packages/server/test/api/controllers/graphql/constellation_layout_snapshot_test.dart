import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_constellation_layout_snapshot.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_layout_snapshots.dart';
import 'package:tentura_server/domain/entity/constellation_layout_snapshot.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/constellation_layout_snapshot_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_layout_snapshot_case.dart';
import 'package:tentura_server/env.dart';

/// The V2 surface for saved Field layouts: list, save and restore resolve the
/// viewer from the JWT and pass the wire arguments to the use case.
void main() {
  const viewer = 'U_layout_viewer';
  final env = Env(environment: Environment.test);

  late _RecordingRepository repository;
  late GraphQL graphQL;

  Future<Map<String, dynamic>> run(
    String document, [
    Map<String, dynamic> variables = const {},
  ]) async =>
      await graphQL.parseAndExecute(
            document,
            variableValues: variables,
            globalVariables: {
              kGlobalInputQueryJwt: const JwtEntity(sub: viewer),
            },
          )
          as Map<String, dynamic>;

  setUp(() {
    repository = _RecordingRepository();
    final useCase = ConstellationLayoutSnapshotCase(
      repository,
      env: env,
      logger: Logger('ConstellationLayoutSnapshotGraphqlTest'),
    );
    graphQL = GraphQL(
      graphQLSchema(
        queryType: objectType(
          'Query',
          fields: QueryConstellationLayoutSnapshots(
            constellationLayoutSnapshotCase: useCase,
          ).all,
        ),
        mutationType: objectType(
          'Mutation',
          fields: MutationConstellationLayoutSnapshot(
            constellationLayoutSnapshotCase: useCase,
          ).all,
        ),
      ),
    );
  });

  test('constellationLayoutSnapshots lists the viewer snapshots', () async {
    final data = await run('''
query { constellationLayoutSnapshots { id kind reason anchorCount } }
''');

    final list = data['constellationLayoutSnapshots'] as List<dynamic>;
    expect(list, hasLength(1));
    expect((list.single as Map)['id'], 'LS_listed');
    expect(repository.listedFor, viewer);
  });

  test('constellationLayoutSnapshotSave saves for the JWT viewer', () async {
    final data = await run(
      r'''
mutation($op: String!) {
  constellationLayoutSnapshotSave(kind: 0, reason: 0, clientOpId: $op) {
    id anchorCount
  }
}
''',
      {'op': 'op-1'},
    );

    expect(
      (data['constellationLayoutSnapshotSave'] as Map)['id'],
      'LS_saved',
    );
    expect(repository.saved.single.viewerId, viewer);
    expect(repository.saved.single.clientOpId, 'op-1');
    expect(
      repository.saved.single.kind,
      ConstellationLayoutSnapshotKind.favourite,
    );
  });

  test(
    'constellationLayoutSnapshotRestore restores for the JWT viewer',
    () async {
      await run(
        r'''
mutation($op: String!) {
  constellationLayoutSnapshotRestore(snapshotId: "LS_x", clientOpId: $op) {
    id
  }
}
''',
        {'op': 'op-2'},
      );

      expect(repository.restored.single.viewerId, viewer);
      expect(repository.restored.single.snapshotId, 'LS_x');
      expect(repository.restored.single.clientOpId, 'op-2');
    },
  );
}

class _RecordingRepository
    implements ConstellationLayoutSnapshotRepositoryPort {
  String? listedFor;
  final saved =
      <
        ({
          String viewerId,
          ConstellationLayoutSnapshotKind kind,
          String clientOpId,
        })
      >[];
  final restored =
      <({String viewerId, String snapshotId, String clientOpId})>[];

  ConstellationLayoutSnapshot _snapshot(String id) =>
      ConstellationLayoutSnapshot(
        id: id,
        kind: ConstellationLayoutSnapshotKind.history,
        reason: ConstellationLayoutSnapshotReason.manual,
        anchorCount: 0,
        createdAt: DateTime.utc(2026),
      );

  @override
  Future<List<ConstellationLayoutSnapshot>> list(String viewerId) async {
    listedFor = viewerId;
    return [_snapshot('LS_listed')];
  }

  @override
  Future<ConstellationLayoutSnapshot> save({
    required String viewerId,
    required ConstellationLayoutSnapshotKind kind,
    required ConstellationLayoutSnapshotReason reason,
    required String clientOpId,
  }) async {
    saved.add((viewerId: viewerId, kind: kind, clientOpId: clientOpId));
    return _snapshot('LS_saved');
  }

  @override
  Future<ConstellationLayoutSnapshot> restore({
    required String viewerId,
    required String snapshotId,
    required String clientOpId,
  }) async {
    restored.add((
      viewerId: viewerId,
      snapshotId: snapshotId,
      clientOpId: clientOpId,
    ));
    return _snapshot(snapshotId);
  }
}
