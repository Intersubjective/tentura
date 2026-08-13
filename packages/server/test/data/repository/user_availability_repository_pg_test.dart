@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('UserAvailabilityRepository — disposable Postgres', () {
    late Connection writer;
    late TenturaDb db;
    late UserAvailabilityRepository repo;

    const userId = 'Uuavailrepo01';
    final resumeOn = DateTime.utc(2026, 9, 15);

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      db = TenturaDb(target.databaseEnv);
      repo = UserAvailabilityRepository(db);
    });

    setUp(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        "DELETE FROM public.user_availability WHERE user_id = '$userId'",
      );
      await writer.execute(
        "DELETE FROM public.\"user\" WHERE id = '$userId'",
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@userId, 'Availability repo', @publicKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {
          'userId': userId,
          'publicKey': pgTestPublicKey('uavailrepo', 1),
        },
      );
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await db.close();
      await writer.close();
      await target.drop();
    });

    Future<({bool? isLimited, DateTime? resumeOn})?> readRow() async {
      final rows = await writer.execute(
        Sql.named('''
SELECT is_limited, resume_on
FROM public.user_availability
WHERE user_id = @userId
'''),
        parameters: {'userId': userId},
      );
      if (rows.isEmpty) {
        return null;
      }
      final row = rows.single;
      final resumeRaw = row[1];
      DateTime? resumeOnValue;
      if (resumeRaw != null) {
        if (resumeRaw is DateTime) {
          resumeOnValue = DateTime.utc(
            resumeRaw.year,
            resumeRaw.month,
            resumeRaw.day,
          );
        } else {
          final text = resumeRaw.toString();
          final parts = text.split('-');
          resumeOnValue = DateTime.utc(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2].substring(0, 2)),
          );
        }
      }
      return (isLimited: row[0] as bool?, resumeOn: resumeOnValue);
    }

    test(
      'setLimited(true) then setLimited(false) ends open with no row',
      () async {
        await repo.setLimited(userId: userId, isLimited: true);
        expect(await readRow(), (isLimited: true, resumeOn: null));

        await repo.setLimited(userId: userId, isLimited: false);
        expect(await readRow(), isNull);
      },
      skip: skipReason,
    );

    test(
      'setLimited(false) preserves an existing pause',
      () async {
        await repo.pause(userId: userId, resumeOn: resumeOn);
        await repo.setLimited(userId: userId, isLimited: true);
        expect(await readRow(), (isLimited: true, resumeOn: resumeOn));

        await repo.setLimited(userId: userId, isLimited: false);
        expect(await readRow(), (isLimited: false, resumeOn: resumeOn));
      },
      skip: skipReason,
    );

    test(
      'setLimited(true) then first pause yields combined limited+paused row',
      () async {
        await repo.setLimited(userId: userId, isLimited: true);
        await repo.pause(userId: userId, resumeOn: resumeOn);

        expect(await readRow(), (isLimited: true, resumeOn: resumeOn));
      },
      skip: skipReason,
    );

    test(
      'resume removes pause and drops row only when not limited',
      () async {
        await repo.pause(userId: userId, resumeOn: resumeOn);
        expect(await readRow(), (isLimited: false, resumeOn: resumeOn));

        await repo.resume(userId: userId);
        expect(await readRow(), isNull);

        await repo.setLimited(userId: userId, isLimited: true);
        await repo.pause(userId: userId, resumeOn: resumeOn);
        expect(await readRow(), (isLimited: true, resumeOn: resumeOn));

        await repo.resume(userId: userId);
        expect(await readRow(), (isLimited: true, resumeOn: null));
      },
      skip: skipReason,
    );
  });
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_USER_AVAILABILITY_REPOSITORY_TEST_DB'] ??
        'tentura_test_uavailrepo_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_USER_AVAILABILITY_REPOSITORY_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

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

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
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

  Future<void> drop() async {
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
