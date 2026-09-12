import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:migrant_db_postgresql/migrant_db_postgresql.dart';
import 'package:postgres/postgres.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/env.dart';

/// Cross-process lock: concurrent `migrateDbSchema` / `run_migrations_once` on
/// the same disposable database raises [RaceCondition] from migrant (55P03 /
/// version skew). Serialize recreate → migrate and close → drop at the harness.
const _lifecycleAdvisoryLockKey = 'tentura_disposable_pg_lifecycle';

/// Disposable Postgres target for tagged PG tests.
///
/// Resolves [databaseName] from [envVarName] when set; otherwise
/// `[defaultNamePrefix]_<pid>_<micros>`.
final class DisposablePgTarget {
  const DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
    required this.envVarName,
  });

  factory DisposablePgTarget.fromNamedEnvironment({
    required String envVarName,
    required String defaultNamePrefix,
    String? databaseNameOverride,
  }) {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        databaseNameOverride ??
        Platform.environment[envVarName] ??
        '${defaultNamePrefix}_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    validateDisposableDatabaseName(databaseName, envVarName);

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
      envVarName: envVarName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;
  final String envVarName;

  static void validateDisposableDatabaseName(
    String databaseName,
    String envVarName,
  ) {
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        envVarName,
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }
  }

  Future<void> _recreateUnlocked() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> _dropUnlocked() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}

/// Writer connection plus metadata after a successful locked bootstrap.
final class DisposablePgWriterSession {
  DisposablePgWriterSession({
    required this.target,
    required this.writer,
  }) : setupComplete = true;

  final DisposablePgTarget target;
  final Connection writer;
  final bool setupComplete;
}

Future<bool> canReachPostgresAdmin(DisposablePgTarget target) async {
  try {
    final connection = await Connection.open(
      target.adminEnv.pgEndpoint,
      settings: target.adminEnv.pgEndpointSettings,
    ).timeout(const Duration(seconds: 2));
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

Future<T> withDisposablePgLifecycleLock<T>(
  Env adminEnv,
  Future<T> Function() action,
) async {
  final connection = await Connection.open(
    adminEnv.pgEndpoint,
    settings: adminEnv.pgEndpointSettings,
  );
  try {
    await connection.execute(
      Sql.named('SELECT pg_advisory_lock(hashtext(@key))'),
      parameters: {'key': _lifecycleAdvisoryLockKey},
    );
    return await action();
  } finally {
    await connection.execute(
      Sql.named('SELECT pg_advisory_unlock(hashtext(@key))'),
      parameters: {'key': _lifecycleAdvisoryLockKey},
    );
    await connection.close();
  }
}

/// Recreate, migrate, and prove `current_database()` under the lifecycle lock.
Future<DisposablePgWriterSession> setUpDisposablePgWriter({
  required DisposablePgTarget target,
  bool createPgmer2Extension = false,
}) async {
  Connection? writer;
  try {
    await withDisposablePgLifecycleLock(target.adminEnv, () async {
      await target._recreateUnlocked();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer!.execute('SET check_function_bodies = false');
      if (createPgmer2Extension) {
        await writer!.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      }
      await migrateDbSchema(writer!);
      final current = await writer!.execute('SELECT current_database()');
      final name = current.first.first as String;
      if (name != target.databaseName) {
        throw StateError(
          'Expected database ${target.databaseName}, connected to $name',
        );
      }
    });
    return DisposablePgWriterSession(target: target, writer: writer!);
  } on Object catch (error, stackTrace) {
    if (writer != null) {
      await writer!.close();
    }
    await withDisposablePgLifecycleLock(target.adminEnv, () async {
      await target._dropUnlocked();
    });
    final detail = error is RaceCondition
        ? '${error.message} (schema_version LOCK TABLE NOWAIT / version skew)'
        : error;
    Error.throwWithStackTrace(
      StateError(
        'Disposable PostgreSQL setup failed for ${target.databaseName} '
        '(${target.envVarName}): $detail',
      ),
      stackTrace,
    );
  }
}

TenturaDb openDisposablePgDatabase(DisposablePgTarget target) =>
    TenturaDb(target.databaseEnv);

/// Closes [drift] then [session.writer], then drops the database (locked).
/// No-op when [session.setupComplete] is false.
Future<void> tearDownDisposablePgWriter({
  required DisposablePgWriterSession session,
  TenturaDb? drift,
}) async {
  if (!session.setupComplete) {
    return;
  }
  await withDisposablePgLifecycleLock(session.target.adminEnv, () async {
    if (drift != null) {
      await drift.close();
    }
    await session.writer.close();
    await session.target._dropUnlocked();
  });
}
