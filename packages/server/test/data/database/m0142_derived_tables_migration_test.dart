@Tags(['pg'])
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0142_MIGRATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0142',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  Future<void> migrateLocked(Connection connection) async {
    await withDisposablePgLifecycleLock(
      target.adminEnv,
      () => migrateDbSchema(connection),
    );
  }

  group('m0142 derived tables and context normalization', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await tearDownDisposablePgWriter(session: session);
    });

    test(
      'fresh schema creates all A2 tables, indexes, and singleton epoch row',
      () async {
        await migrateLocked(writer);
        await _expectA2Schema(writer);
      },
      skip: skipReason,
    );

    test(
      'upgrade from m0141 applies A2 schema and enforces constraints',
      () async {
        await migrateLocked(writer);
        await _rollBackM0142ForTest(writer);

        await _seedFixture(writer);

        for (final statement in m0142.statements) {
          await writer.execute(statement);
        }
        await writer.execute(
          "INSERT INTO public.schema_version (version, applied_at) "
          "VALUES ('0142', now()) "
          'ON CONFLICT DO NOTHING',
        );
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
