import 'dart:convert';
import 'dart:io';

import 'disposable_pg_target.dart';

/// Prints the pool settings a disposable target's database Env resolves to in
/// this process, so a test can vary the ambient environment per process.
void main() {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ENV_PROBE_TEST_DB',
    defaultNamePrefix: 'tentura_test_env_probe',
  );
  stdout.writeln(
    jsonEncode({
      'database': target.databaseEnv.driftTransactionPinnedPoolEnabled,
      'admin': target.adminEnv.driftTransactionPinnedPoolEnabled,
      'template': target.templateEnv.driftTransactionPinnedPoolEnabled,
    }),
  );
}
