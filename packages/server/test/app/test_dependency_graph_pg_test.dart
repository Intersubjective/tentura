@Tags(['pg'])
library;

import 'package:test/test.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';

import '../support/disposable_pg_target.dart';
import '../support/mocks/beacon_repository_mock.dart';
import '../support/test_dependency_graph_expectations.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TEST_DEPENDENCY_GRAPH_DB',
    defaultNamePrefix: 'tentura_test_di_graph',
  );
  final skipReason = await pgSkipReason(target);

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    addTearDown(() => tearDownDisposablePgWriter(session: session));
  });

  test(
    'the server test graph resolves the moved mock and application dependencies',
    () async {
      addTearDown(getIt.reset);
      await expectTestDependencyGraph(target.databaseEnv);
    },
    skip: skipReason,
  );

  test(
    'the server test graph uses test-support repositories and shares beacon state',
    () async {
      addTearDown(getIt.reset);
      await expectTestDependencyGraph(target.databaseEnv);

      final writer = getIt<BeaconRepositoryPort>();
      const authorId = 'beacon-test-graph-author';
      final created = await writer.createBeacon(
        authorId: authorId,
        title: 'Test graph beacon',
      );
      addTearDown(() => writer.deleteBeaconById(created.id, userId: authorId));
      final imageId = 'staged-for-${created.id}';
      await writer.insertStage(beaconId: created.id, imageId: imageId);
      addTearDown(() => writer.deleteStage(imageId: imageId));

      // The DI factory may return a canonical const instance. Construct a
      // fresh instance of the bound implementation to exercise shared state.
      final createMock = BeaconRepositoryMock.new;
      final reader = createMock();
      expect(reader, isNot(same(writer)));
      expect(await reader.getBeaconById(beaconId: created.id), created);

      const fixtureId = 'B20f3d51e498f';
      final fixture = await reader.getBeaconById(beaconId: fixtureId);
      expect(fixture.id, fixtureId);
      expect(fixture.title, 'Protect Our Forests');

      final stages = await reader.staleStages(
        olderThan: DateTime.timestamp().add(const Duration(minutes: 1)),
      );
      expect(
        stages
            .where((stage) => stage.beaconId == created.id)
            .map(
              (stage) => (stage.imageId, stage.authorId),
            ),
        [(imageId, authorId)],
      );

      expect(
        writer.runtimeType,
        reader.runtimeType,
        reason: 'The live test graph must use the relocated Beacon mock.',
      );
    },
    skip: skipReason,
  );
}
