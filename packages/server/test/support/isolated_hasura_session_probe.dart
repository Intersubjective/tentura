// Child process for `isolated_hasura_session_port_pg_test.dart` (tentura-acz).
//
// Stands in for one Hasura pg test *file* running in its own `dart test`
// process: it starts an [IsolatedHasuraSession] for the given disposable
// database, reports it, and keeps it alive until told to stop. Not a test
// itself (no `_test.dart` suffix), so `dart test` never picks it up.
//
// Protocol (line based): prints `READY`, waits for `go`, then prints
// `SESSION <json>` (or `ERROR <message>`), then waits for `stop` / EOF.
//
// Usage: dart run test/support/isolated_hasura_session_probe.dart <database>
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'beacon_hierarchy_fixture.dart';
import 'hasura_pg_jwt_keys.dart';
import 'isolated_hasura_session.dart';

Future<void> main(List<String> args) async {
  final target = BeaconHierarchyDisposablePgTarget.fromEnvironment(
    databaseNameOverride: args.single,
  );
  final jwtKeys = loadJwtKeysForHasuraPgTests();
  final input = StreamIterator(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );

  stdout.writeln('READY');
  if (!await input.moveNext() || input.current != 'go') {
    return;
  }

  IsolatedHasuraSession? session;
  try {
    session = await IsolatedHasuraSession.start(
      databaseEnv: target.databaseEnv,
      jwtPublicPem: jwtKeys.publicKey,
    );
    await session.applyRepoMetadata();
    stdout.writeln(
      'SESSION ${jsonEncode({'baseUrl': session.baseUrl, 'port': session.port, 'containerName': session.containerName})}',
    );
    // `stop` or EOF (parent gone) both end the session.
    await input.moveNext();
  } on Object catch (e) {
    stdout.writeln('ERROR ${e.toString().replaceAll('\n', ' ')}');
    exitCode = 1;
  } finally {
    await session?.stop();
  }
}
