// One-off helper: apply pending schema migrations to the local dev/test DB.
// Usage: dart run bin/utils/run_migrations_once.dart
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final env = Env(
    environment: Environment.test,
    pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
    pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
    pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
    printEnv: false,
    isDebugModeOn: false,
  );
  final connection = await Connection.open(
    env.pgEndpoint,
    settings: env.pgEndpointSettings,
  );
  await migrateDbSchema(connection);
  await connection.close();
  stdout.writeln('Migrations applied.');
}
