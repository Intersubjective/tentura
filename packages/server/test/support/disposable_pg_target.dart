import 'dart:io';
import 'dart:math';

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

/// Name of the template database disposable targets are cloned from.
///
/// Keyed by a fingerprint of the migration registry, so adding a migration
/// yields a new template name rather than a stale template: the old one is
/// simply never asked for again.
///
/// Dropping a leftover template needs one extra step, because it is marked as a
/// template and refuses connections:
///
/// ```sql
/// UPDATE pg_database SET datistemplate = false WHERE datname = '<name>';
/// DROP DATABASE "<name>";
/// ```
final String templateDatabaseName =
    'tentura_test_tpl_${_registryFingerprint()}';

/// FNV-1a over the registry, hand-rolled because `String.hashCode` is not
/// guaranteed stable across processes and every test process must agree on the
/// template name.
String _registryFingerprint() {
  // Server-only test code; the JS-rounding advice does not apply.
  // ignore: avoid_js_rounded_ints
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0xFFFFFFFFFFFFFFFF;
  for (final migration in migrationsForTesting) {
    for (final unit in [
      migration.version,
      '${migration.statements.length}',
      '${migration.statements.fold<int>(0, (a, s) => a + s.length)}',
    ]) {
      for (final byte in unit.codeUnits) {
        hash = (hash ^ byte) & mask;
        hash = (hash * prime) & mask;
      }
    }
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

var _templateReady = false;

/// Builds [templateDatabaseName] once per cluster, if it is not already there.
///
/// Must be called under the lifecycle lock: several test processes race here.
/// The template is left with `datallowconn = false`, both so nothing can hold a
/// session against it — `CREATE DATABASE … TEMPLATE` refuses while one does —
/// and so it cannot be mistaken for a disposable database.
Future<void> _ensureTemplateUnlocked(Env adminEnv, Env templateEnv) async {
  if (_templateReady) return;
  final admin = await Connection.open(
    adminEnv.pgEndpoint,
    settings: adminEnv.pgEndpointSettings,
  );
  try {
    final existing = await admin.execute(
      Sql.named('SELECT 1 FROM pg_database WHERE datname = @name'),
      parameters: {'name': templateDatabaseName},
    );
    if (existing.isNotEmpty) {
      _templateReady = true;
      return;
    }
    await admin.execute('CREATE DATABASE "$templateDatabaseName"');
  } finally {
    await admin.close();
  }

  final builder = await Connection.open(
    templateEnv.pgEndpoint,
    settings: templateEnv.pgEndpointSettings,
  );
  try {
    // Function bodies reference the pgmer2 extension's `mr_*` functions, which
    // the template deliberately does not install: `createPgmer2Extension` adds
    // it per clone, so the template stays the shape the default path expects.
    await builder.execute('SET check_function_bodies = false');
    await migrateDbSchema(builder);
  } finally {
    await builder.close();
  }

  final sealer = await Connection.open(
    adminEnv.pgEndpoint,
    settings: adminEnv.pgEndpointSettings,
  );
  try {
    await sealer.execute(
      Sql.named(
        'UPDATE pg_database SET datistemplate = true, datallowconn = false '
        'WHERE datname = @name',
      ),
      parameters: {'name': templateDatabaseName},
    );
  } finally {
    await sealer.close();
  }
  _templateReady = true;
}

/// Disposable Postgres target for tagged PG tests.
///
/// Resolves [databaseName] from [envVarName] when set; otherwise
/// `[defaultNamePrefix]_<pid>_<random>_<seq>`.
final class DisposablePgTarget {
  const DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.templateEnv,
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
        '${defaultNamePrefix}_${pid}_'
            '${Random().nextInt(1 << 30)}_'
            '${_nameSeq++}';
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
      templateEnv: envFor(templateDatabaseName),
      databaseName: databaseName,
      envVarName: envVarName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final Env templateEnv;
  final String databaseName;
  final String envVarName;

  static int _nameSeq = Random().nextInt(1 << 20);

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

  /// Clones the prebuilt template instead of running the schema build.
  ///
  /// `CREATE DATABASE … TEMPLATE` is a file copy: no migration, and crucially
  /// no `pg_advisory_lock('tentura_schema_upgrade')`, which is cluster-wide and
  /// which 95 test files were otherwise serializing on for the length of a full
  /// schema build each.
  Future<void> _recreateFromTemplateUnlocked() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute(
        'CREATE DATABASE "$databaseName" TEMPLATE "$templateDatabaseName"',
      );
    } finally {
      await connection.close();
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
  String? lastInclusiveVersion,
}) async {
  Connection? writer;
  try {
    await withDisposablePgLifecycleLock(target.adminEnv, () async {
      // A full-schema target is cloned from the prebuilt template; only a
      // partial one (`lastInclusiveVersion`) still has to run the registry,
      // since the template is at head by construction.
      if (lastInclusiveVersion == null) {
        await _ensureTemplateUnlocked(target.adminEnv, target.templateEnv);
        await target._recreateFromTemplateUnlocked();
      } else {
        await target._recreateUnlocked();
      }
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer!.execute('SET check_function_bodies = false');
      if (createPgmer2Extension) {
        await writer!.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      }
      if (lastInclusiveVersion != null) {
        await migrateDbSchemaThrough(writer!, lastInclusiveVersion);
      }
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
