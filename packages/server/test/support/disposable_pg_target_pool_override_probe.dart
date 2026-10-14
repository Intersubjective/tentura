import 'dart:convert';
import 'dart:io';

import 'package:tentura_server/data/database/main_db_pool.dart';

import 'disposable_pg_target.dart';

/// Prints the pool sizing a disposable target resolves to in this process.
/// Database-free: nothing here opens a connection.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POOL_OVERRIDE_PROBE_TEST_DB',
    defaultNamePrefix: 'tentura_test_pool_override_probe',
  );
  final pool = MainDbPool(target.databaseEnv);
  final admissionSlots = pool.admission.maxConcurrent;
  await pool.close();
  stdout.writeln(
    jsonEncode({
      'database': target.databaseEnv.pgPoolSettings.maxConnectionCount,
      'admin': target.adminEnv.pgPoolSettings.maxConnectionCount,
      'template': target.templateEnv.pgPoolSettings.maxConnectionCount,
      'constellationDbMaxConcurrent':
          target.databaseEnv.constellationDbMaxConcurrent,
      'admissionSlots': admissionSlots,
    }),
  );
}
