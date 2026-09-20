@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('m0141 person_capability_event ledger extension', () {
    late Connection writer;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
    });

    tearDownAll(() async {
      await writer.close();
      await target.drop();
    });

    test(
      'fresh schema gains provenance columns, CHECK, and indexes',
      () async {
        await migrateDbSchema(writer);

        final columns = await writer.execute(r'''
SELECT column_name, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'person_capability_event'
  AND column_name IN ('forward_edge_id', 'invitation_id')
ORDER BY column_name
''');
        expect(
          columns.map((r) => [r[0], r[1]]).toList(),
          [
            ['forward_edge_id', 'YES'],
            ['invitation_id', 'YES'],
          ],
        );

        final constraints = await writer.execute(r'''
SELECT conname
FROM pg_constraint
WHERE conname = 'pce_source_type_ck'
''');
        expect(constraints, hasLength(1));

        final indexes = await writer.execute(r'''
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
    'pce_seed_attestation_uq',
    'pce_forward_reason_uq',
    'pce_close_ack_uq',
    'pce_aggregation_idx'
  )
ORDER BY indexname
''');
        expect(
          indexes.map((r) => r[0]).toList(),
          [
            'pce_aggregation_idx',
            'pce_close_ack_uq',
            'pce_forward_reason_uq',
            'pce_seed_attestation_uq',
          ],
        );
      },
      skip: skipReason,
    );

  });
}

Future<void> _seedFixture(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Upcem0141obs1', 'Observer', 'pk-obs'),
  ('Upcem0141sub1', 'Subject', 'pk-sub'),
  ('Upcem0141auth1', 'Author', 'pk-auth')
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES ('Bpcem0141bcn1', 'Upcem0141auth1', 'Beacon', 'd')
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  'Fpcem0141edge1', 'Bpcem0141bcn1', 'Upcem0141obs1', 'Upcem0141sub1', now()
)
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.invitation (id, user_id, created_at, updated_at)
VALUES ('Ipcem0141inv1', 'Upcem0141obs1', now(), now())
ON CONFLICT DO NOTHING
''');
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
        Platform.environment['TENTURA_M0141_MIGRATION_TEST_DB'] ??
        'tentura_test_m0141_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_M0141_MIGRATION_TEST_DB',
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
