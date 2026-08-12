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

  group('m0142 derived tables and context normalization', () {
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
      'fresh schema creates all A2 tables, indexes, and singleton epoch row',
      () async {
        await migrateDbSchema(writer);
        await _expectA2Schema(writer);
      },
      skip: skipReason,
    );

    test(
      'upgrade from m0141 applies A2 schema and enforces constraints',
      () async {
        await migrateDbSchema(writer);
        await _rollBackM0142ForTest(writer);

        await _seedFixture(writer);

        await migrateDbSchema(writer);
        await _expectA2Schema(writer);

        await expectLater(
          writer.execute(r'''
INSERT INTO public.capability_evidence_edge (
  observer_user_id, subject_user_id, tag_slug
) VALUES (
  'Um0142user1', 'Um0142user1', 'transport'
)
'''),
          throwsA(isA<Exception>()),
        );

        await writer.execute(r'''
INSERT INTO public.capability_evidence_edge (
  observer_user_id, subject_user_id, tag_slug
) VALUES (
  'Um0142obs1', 'Um0142sub1', 'transport'
)
''');

        await writer.execute(r'''
INSERT INTO public.capability_evidence_generation (
  observer_user_id, subject_user_id, tag_slug, generation
) VALUES (
  'Um0142obs1', 'Um0142sub1', 'transport', 1
)
''');

        await writer.execute(r'''
INSERT INTO public.ego_witness_window (
  ego_user_id, context, witness_user_id, m, admitted, mr_epoch
) VALUES (
  'Um0142obs1', 'work', 'Um0142sub1', 0.5, true, 0
)
''');

        await writer.execute(r'''
INSERT INTO public.capability_routing_mute (user_id, tag_slug)
VALUES ('Um0142obs1', 'transport')
''');

        final normalizeFn = await writer.execute(r'''
SELECT count(*)::int
FROM pg_proc
WHERE proname = 'cap_normalize_context'
''');
        expect(normalizeFn.single.single, 1);

        final mvuUsesNormalize = await writer.execute(r'''
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname = 'mutually_visible_users'
  AND n.nspname = 'public'
''');
        expect(
          mvuUsesNormalize.single.single,
          contains('cap_normalize_context(context)'),
        );
      },
      skip: skipReason,
    );
  });
}

Future<void> _expectA2Schema(Connection writer) async {
  final tables = await writer.execute(r'''
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'capability_evidence_edge',
    'capability_evidence_generation',
    'ego_witness_window',
    'capability_routing_mute',
    'mr_publish_epoch'
  )
ORDER BY table_name
''');
  expect(
    tables.map((r) => r[0]).toList(),
    [
      'capability_evidence_edge',
      'capability_evidence_generation',
      'capability_routing_mute',
      'ego_witness_window',
      'mr_publish_epoch',
    ],
  );

  final indexes = await writer.execute(r'''
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
    'cee_projection_idx',
    'cee_expiry_idx',
    'eww_gc_idx'
  )
ORDER BY indexname
''');
  expect(
    indexes.map((r) => r[0]).toList(),
    ['cee_expiry_idx', 'cee_projection_idx', 'eww_gc_idx'],
  );

  final selfCheck = await writer.execute(r'''
SELECT conname
FROM pg_constraint
WHERE conname = 'cee_no_self'
''');
  expect(selfCheck, hasLength(1));

  final epochRows = await writer.execute(r'''
SELECT id, epoch
FROM public.mr_publish_epoch
ORDER BY id
''');
  expect(epochRows, hasLength(1));
  expect(epochRows.single[0], true);
  expect(epochRows.single[1], 0);
}

Future<void> _seedFixture(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Um0142obs1', 'Observer', 'pk-obs'),
  ('Um0142sub1', 'Subject', 'pk-sub'),
  ('Um0142user1', 'Self', 'pk-self')
ON CONFLICT DO NOTHING
''');
}

Future<void> _rollBackM0142ForTest(Connection connection) async {
  for (final statement in const [
    r'''
CREATE OR REPLACE FUNCTION public.mutually_visible_users(
  context text,
  hasura_session json
) RETURNS SETOF public."user"
  LANGUAGE sql
  STABLE
  AS $$
SELECT u.*
FROM public."user" u
INNER JOIN public.person_visibility_peers(
  hasura_session ->> 'x-hasura-user-id',
  context
) p ON u.id = p.peer_id
WHERE nullif(trim(hasura_session ->> 'x-hasura-user-id'), '') IS NOT NULL
  AND u.id <> (hasura_session ->> 'x-hasura-user-id')
  AND p.is_mutually_visible
  AND NOT public.block_hides(
    hasura_session ->> 'x-hasura-user-id',
    u.id
  );
$$;
''',
    'DROP FUNCTION IF EXISTS public.cap_normalize_context(text)',
    'DROP INDEX IF EXISTS public.cee_expiry_idx',
    'DROP INDEX IF EXISTS public.cee_projection_idx',
    'DROP TABLE IF EXISTS public.capability_evidence_edge CASCADE',
    'DROP TABLE IF EXISTS public.capability_evidence_generation CASCADE',
    'DROP INDEX IF EXISTS public.eww_gc_idx',
    'DROP TABLE IF EXISTS public.ego_witness_window CASCADE',
    'DROP TABLE IF EXISTS public.capability_routing_mute CASCADE',
    'DROP TABLE IF EXISTS public.mr_publish_epoch CASCADE',
    "DELETE FROM public.schema_version WHERE version = '0142'",
  ]) {
    await connection.execute(statement);
  }
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
        Platform.environment['TENTURA_M0142_MIGRATION_TEST_DB'] ??
        'tentura_test_m0142_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_M0142_MIGRATION_TEST_DB',
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
