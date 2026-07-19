import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final env = Env(
    environment: Environment.dev,
    pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
    pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
    pgDatabase: Platform.environment['POSTGRES_DBNAME'] ?? 'postgres',
    pgUsername: Platform.environment['POSTGRES_USERNAME'] ?? 'postgres',
    pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
    genealogyNodeKeySecret:
        Platform.environment['GENEALOGY_NODE_KEY_SECRET'] ?? 'migrate-only',
  );
  final connection = await Connection.open(
    env.pgEndpoint,
    settings: env.pgEndpointSettings,
  );
  await migrateDbSchema(connection);
  await connection.close();
  stdout.writeln('migrate: schema upgrade complete');
}
