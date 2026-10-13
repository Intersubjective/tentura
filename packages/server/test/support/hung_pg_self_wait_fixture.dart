// Not a test file of its own (no `_test` suffix): run as a child process by
// `hung_pg_test_diagnostics_pg_test.dart`. It hangs on purpose and relies only
// on the shared disposable-database harness (`setUpDisposablePgWriter`,
// `openDisposablePgDatabase`) for diagnostics: the fixture installs no guard,
// watchdog or timeout of its own.
//
// The scenario is chosen with [hungSuiteScenarioEnvVar].
import 'dart:io';

import 'package:postgres/postgres.dart' show Connection;
import 'package:test/test.dart';

import 'disposable_pg_target.dart';

const hungSuiteScenarioEnvVar = 'TENTURA_HUNG_SUITE_FIXTURE_SCENARIO';

/// A transaction on a database from `openDisposablePgDatabase` whose statement
/// waits on a lock another session holds.
const hungExecutorWaitScenario = 'executor-wait';

/// A test that waits on the harness writer connection, with no Drift executor
/// involved, until the runner's own timeout.
const hungSuiteScenario = 'suite-hang';

const hungSuiteHardTimeout = Duration(seconds: 20);
const hungSuiteLockedStatement = 'hung_suite_locked_statement';
const _advisoryKey = 7240127;

void main() {
  final scenario = Platform.environment[hungSuiteScenarioEnvVar];
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HUNG_SUITE_FIXTURE_DB',
    defaultNamePrefix: 'tentura_test_hung_suite',
  );
  late DisposablePgWriterSession session;
  late Connection holder;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
  });
  setUp(() async {
    holder = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    await holder.execute('SELECT pg_advisory_lock($_advisoryKey)');
  });
  // Closing the holder releases the lock, so the abandoned statement finishes
  // and nothing keeps the database from being dropped.
  tearDown(() => holder.close());
  tearDownAll(() => tearDownDisposablePgWriter(session: session));

  const lockStatement =
      "SELECT '$hungSuiteLockedStatement', pg_advisory_lock($_advisoryKey)";

  test(
    'a transaction on a leased connection waits on a lock held elsewhere',
    () async {
      final db = openDisposablePgDatabase(target);
      addTearDown(db.close);
      await db.withTransaction(() async {
        // Only the harness may end this wait, whatever lock timeout the
        // database carries.
        await db.customStatement('SET LOCAL lock_timeout = 0');
        await db.customSelect(lockStatement).get();
      });
    },
    skip: scenario == hungExecutorWaitScenario
        ? false
        : 'scenario is not $hungExecutorWaitScenario',
    timeout: const Timeout(hungSuiteHardTimeout),
  );

  test(
    'the writer connection waits on a lock held elsewhere',
    () async {
      await session.writer.execute('SET lock_timeout = 0');
      await session.writer.execute(lockStatement);
    },
    skip: scenario == hungSuiteScenario
        ? false
        : 'scenario is not $hungSuiteScenario',
    timeout: const Timeout(hungSuiteHardTimeout),
  );
}
