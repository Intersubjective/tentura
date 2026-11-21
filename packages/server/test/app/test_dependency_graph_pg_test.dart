@Tags(['pg'])
library;

import 'package:test/test.dart';
import 'package:tentura_server/app/di.dart';

import '../support/disposable_pg_target.dart';
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
}
